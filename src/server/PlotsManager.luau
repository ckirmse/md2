--!strict

local PlotsManager = {}
PlotsManager.__index = PlotsManager

local collectionService = game:GetService("CollectionService")
local playersService = game:GetService("Players")

local Level = workspace:WaitForChild("Level")
local PerPlotElements = Level:WaitForChild("PerPlotElements")
local ClonedPlotElements = Level:WaitForChild("ClonedPlotElements")
local MergePlot = Level:WaitForChild("MergePlot")
local Land = MergePlot:WaitForChild("Land")

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ServerStorage = game:GetService("ServerStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")


local DEFAULT_LAND_PLOT_INNER_NAME = "Land Plot Inner Template"
local DEFAULT_LAND_PLOT_OUTER_NAME = "Land Plot Outer Template"

local DEFAULT_EXPANSION_INNER_NAME = "Expansion Inner Template"
local DEFAULT_EXPANSION_OUTER_NAME = "Expansion Outer Template"

local NUM_PLOTS = 6

-- vanity component data comes from GameData modules and bounds records are simple min/max pairs,
-- so both stay untyped
type PlotsManagerFields = {
	mainPlotInnerDatas: { [string]: any },
	mainPlotOuterDatas: { [string]: any },
	fenceDatas: { [string]: any },
	expansionInnerDatas: { [string]: any },
	expansionOuterDatas: { [string]: any },
	plotPartCFrames: { [string]: CFrame },
	assignments: { [number]: number },
	mainBounds: { [number]: any },
	expansionBounds: { [number]: { [number]: any } },
	allVanityComponentNames: { string }?,
}

export type PlotsManager = typeof(setmetatable({} :: PlotsManagerFields, PlotsManager))

function PlotsManager.getNumPlots(self: PlotsManager): number
	return NUM_PLOTS
end

function PlotsManager.translatePositionPlotToWorld(self: PlotsManager, position: Vector3, index: number): Vector3
	-- an unknown plot index crashed here before typing too
	return (PlotHelpers.getPlotCFrame(index) :: CFrame) * position
end

function PlotsManager.translatePositionWorldToPlot(self: PlotsManager, position: Vector3, index: number): Vector3
	return (PlotHelpers.getPlotCFrame(index) :: CFrame):Inverse() * position
end

function PlotsManager.getNumEndCaps(self: PlotsManager): number
	local endCaps = collectionService:GetTagged("EndCap")
	return #endCaps
end

function PlotsManager.getEndCapCFrame(self: PlotsManager, endCapIndex: number): CFrame
	local endCaps = collectionService:GetTagged("EndCap")
	return (endCaps[endCapIndex] :: any).WorldCFrame
end

function PlotsManager.translatePositionEndCapToWorld(self: PlotsManager, position: Vector3, index: number): Vector3
	return self:getEndCapCFrame(index) * position
end

-- returns position in workspace coordinates
function PlotsManager.getGroundPositionFromPlotPosition(self: PlotsManager, plotPosition: Vector3, index: number): Vector3
	local position = self:translatePositionPlotToWorld(plotPosition, index)
	return utils.getGroundPositionForLocation(position)
end

function PlotsManager.createItemOnPlot(self: PlotsManager, index: number, name: any, plotPosition: Vector3, userId: number)
	local item = itemManager:createItem(name, userId)
	if not item then
		warn("failed to create item on plot", name)
		return
	end
	local obj = item:getObj()

	obj:PivotTo(CFrame.new(self:getGroundPositionFromPlotPosition(plotPosition, index)))
	obj.Parent = workspace
end

function PlotsManager.addAllChildrenAndMapCFramesForPlotIndex(self: PlotsManager, plotIndex: number, root: any, holder: Instance)
	for _, inst in root:GetChildren() do
		local newInst = inst:Clone()
		newInst:SetAttribute(Attributes.INDEX, plotIndex)
		for _, descendantInst in newInst:GetDescendants() do
			descendantInst:SetAttribute(Attributes.INDEX, plotIndex)
		end

		local currentCFrame = PlotHelpers.translateCFrameWorldToPlot(newInst:GetPivot(), 1)
		newInst:PivotTo(PlotHelpers.translateCFramePlotToWorld(currentCFrame, plotIndex))
		newInst.Parent = holder
	end
end

function PlotsManager.removeAllChildrenForPlotIndex(self: PlotsManager, plotIndex: number, holder: Instance)
	for _, inst in holder:GetChildren() do
		if inst:GetAttribute(Attributes.INDEX) == plotIndex then
			inst:Destroy()
		end
	end
end

function PlotsManager.setupPlotIndexForJoiningPlayer(self: PlotsManager, plotIndex: number)
	self:addAllChildrenAndMapCFramesForPlotIndex(plotIndex, PerPlotElements, ClonedPlotElements)

	local player = playersService:GetPlayerByUserId(self.assignments[plotIndex])
	if not player then
		return
	end

	local sign = utils.findFirstDescendantWithNameAndAttribute(Level, "Sign", Attributes.INDEX, plotIndex)
	if sign then
		local nameInst = utils.findFirstDescendant(sign, "Name");
		-- a missing Name label crashed here before typing too
		(nameInst :: any).Text = player.Name
	end
end

function PlotsManager.notifyAddUserId(self: PlotsManager, userId: number): number?
	for plotIndex = 1, NUM_PLOTS do
		if self.assignments[plotIndex] then
			continue
		end

		self.assignments[plotIndex] = userId

		self:setupPlotIndexForJoiningPlayer(plotIndex)
		return plotIndex
	end

	warn("server: cannot add player, no plots free")
	return nil
end

function PlotsManager.removeAllVanity(self: PlotsManager, plotIndex: number)
	self:restoreInnerPlot(plotIndex)
	self:restoreOuterPlot(plotIndex)
	for _, vanityPlacement in enums.getAllValues(enums.VanityPlacements) do
		if vanityPlacement == enums.VanityPlacements.MAIN_PLOT_INNER or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_OUTER then
			continue
		end

		self:removeVanityName(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement))
	end
end

function PlotsManager.notifyRemovePlayer(self: PlotsManager, player: Player)
	local plotIndex = self:getPlotIndexByUserId(player.UserId)
	if not plotIndex then
		warn("removing player with no plot index", player)
		return
	end

	print("server: removing plot for player", player.Name)
	self:removeAllChildrenForPlotIndex(plotIndex, ClonedPlotElements)

	self:removeAllVanity(plotIndex)

	self.assignments[plotIndex] = nil
end

function PlotsManager.getPlotIndexByUserId(self: PlotsManager, userId: number): number?
	for i, plotUserId in self.assignments do
		if plotUserId == userId then
			return i
		end
	end
	return nil
end

function PlotsManager.getPlotCFrameForUserId(self: PlotsManager, userId: number): CFrame?
	local plotIndex = self:getPlotIndexByUserId(userId)

	return PlotHelpers.getPlotCFrame(plotIndex :: number)
end

function PlotsManager.getPlotItemRecoveryPositionByUserId(self: PlotsManager, userId: number): Vector3?
	local plotIndex = self:getPlotIndexByUserId(userId)
	if not plotIndex then
		return nil
	end

	local mainBounds = self.mainBounds[plotIndex]
	return utils.getGroundPosition((mainBounds.minPosition.X + mainBounds.maxPosition.X) / 2, (mainBounds.minPosition.Z + mainBounds.maxPosition.Z) / 2)
end

function PlotsManager.getPlotPositionFromWorldPositionForUserId(self: PlotsManager, position: Vector3, userId: number): Vector3
	local plotIndex = self:getPlotIndexByUserId(userId)
	return self:translatePositionWorldToPlot(position, plotIndex :: number)
end

function PlotsManager.getWorldPositionFromPlotPositionForUserId(self: PlotsManager, position: Vector3, userId: number): Vector3?
	if typeof(userId) ~= "number" then
		warn("invalid userid to get world position", userId)
		return nil
	end

	local plotIndex = self:getPlotIndexByUserId(userId)
	return self:translatePositionPlotToWorld(position, plotIndex :: number)
end

function PlotsManager.getPlotCFrameFromWorldCFrameForUserId(self: PlotsManager, cframe: CFrame, userId: number): CFrame
	local plotIndex = self:getPlotIndexByUserId(userId)
	return PlotHelpers.translateCFrameWorldToPlot(cframe, plotIndex :: number)
end

function PlotsManager.getWorldCFrameFromPlotCFrameForUserId(self: PlotsManager, cframe: CFrame, userId: number): CFrame?
	if typeof(userId) ~= "number" then
		warn("invalid userid to get world cframe", userId)
		return nil
	end

	local plotIndex = self:getPlotIndexByUserId(userId)
	return PlotHelpers.translateCFramePlotToWorld(cframe, plotIndex :: number)
end


function PlotsManager.getClosestPlotIndexByPosition(self: PlotsManager, position: Vector3): any
	local bestIndex: any = nil
	local bestDistance = math.huge
	local origins = collectionService:GetTagged("Origin")
	for _, origin in origins do
		local distance = ((origin :: any).Position - position).Magnitude
		if distance >= bestDistance then
			continue
		end

		bestIndex = origin:GetAttribute(Attributes.INDEX)
		bestDistance = distance
	end

	return bestIndex
end

function PlotsManager.isPlotIndexOccupied(self: PlotsManager, plotIndex: number): boolean
	return self.assignments[plotIndex] ~= nil
end

function PlotsManager.isPositionInMainPlotXZ(self: PlotsManager, position: Vector3, plotIndex: number): boolean
	local bounds = self.mainBounds[plotIndex]
	if position.X < bounds.minPosition.X then
		return false
	end
	if position.X > bounds.maxPosition.X then
		return false
	end
	if position.Z < bounds.minPosition.Z then
		return false
	end
	if position.Z > bounds.maxPosition.Z then
		return false
	end

	return true
end

function PlotsManager.getRandomLocationInMainPlot(self: PlotsManager, plotIndex: number): Vector3
	local random = Random.new()

	local bounds = self.mainBounds[plotIndex]
	local x = random:NextNumber(bounds.minPosition.X, bounds.maxPosition.X)
	local z = random:NextNumber(bounds.minPosition.Z, bounds.maxPosition.Z)

	return Vector3.new(x, 0, z)
end

function PlotsManager.getRandomLocationInMainPlotByUserId(self: PlotsManager, userId: number): Vector3?
	local plotIndex = self:getPlotIndexByUserId(userId)
	if not plotIndex then
		return nil
	end
	return self:getRandomLocationInMainPlot(plotIndex)
end

function PlotsManager.isPositionInMainPlotXZByUserId(self: PlotsManager, position: Vector3, userId: number): boolean
	local plotIndex = self:getPlotIndexByUserId(userId)
	if not plotIndex then
		return false
	end
	return self:isPositionInMainPlotXZ(position, plotIndex)
end

function PlotsManager.isPositionInExpansionXZ(self: PlotsManager, position: Vector3, vanityArea: number, plotIndex: number): boolean
	local bounds = self.expansionBounds[plotIndex][vanityArea]
	if position.X < bounds.minPosition.X then
		return false
	end
	if position.X > bounds.maxPosition.X then
		return false
	end
	if position.Z < bounds.minPosition.Z then
		return false
	end
	if position.Z > bounds.maxPosition.Z then
		return false
	end

	return true
end

function PlotsManager.isPositionInExpansionXZByUserId(self: PlotsManager, position: Vector3, vanityArea: number, userId: number): boolean
	local plotIndex = self:getPlotIndexByUserId(userId)
	if not plotIndex then
		return false
	end
	return self:isPositionInExpansionXZ(position, vanityArea, plotIndex)
end

function PlotsManager.initVanityData(self: PlotsManager)
	local serverScriptService = game:GetService("ServerScriptService")
	local GameData = serverScriptService:WaitForChild("GameData")
	local Vanity = GameData:WaitForChild("Vanity")

	local Inner = Vanity:WaitForChild("MainPlotInner")
	for _, inst in Inner:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		self.mainPlotInnerDatas[data.name] = data
	end

	local Outer = Vanity:WaitForChild("MainPlotOuter")
	for _, inst in Outer:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		self.mainPlotOuterDatas[data.name] = data
	end

	local Fence = Vanity:WaitForChild("Fence")
	for _, inst in Fence:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		self.fenceDatas[data.name] = data
	end

	local ExpansionInner = Vanity:WaitForChild("ExpansionInner")
	for _, inst in ExpansionInner:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		self.expansionInnerDatas[data.name] = data
	end

	local ExpansionOuter = Vanity:WaitForChild("ExpansionOuter")
	for _, inst in ExpansionOuter:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		self.expansionOuterDatas[data.name] = data
	end

end

function PlotsManager.getAllMainPlotInnerNames(self: PlotsManager): { string }
	local tbl = {}
	for name, _ in self.mainPlotInnerDatas do
		table.insert(tbl, name)
	end
	return tbl
end

function PlotsManager.getAllMainPlotOuterNames(self: PlotsManager): { string }
	local tbl = {}
	for name, _ in self.mainPlotOuterDatas do
		table.insert(tbl, name)
	end
	return tbl
end

function PlotsManager.getAllFenceNames(self: PlotsManager): { string }
	local tbl = {}
	for name, _ in self.fenceDatas do
		table.insert(tbl, name)
	end
	return tbl
end

function PlotsManager.getAllExpansionInnerNames(self: PlotsManager): { string }
	local tbl = {}
	for name, _ in self.expansionInnerDatas do
		table.insert(tbl, name)
	end
	return tbl
end

function PlotsManager.getAllExpansionOuterNames(self: PlotsManager): { string }
	local tbl = {}
	for name, _ in self.expansionOuterDatas do
		table.insert(tbl, name)
	end
	return tbl
end

function PlotsManager.validateVanityPlacement(self: PlotsManager, vanityPlacement: number): boolean
	if not enums.isValidValue(enums.VanityPlacements, vanityPlacement) then
		return false
	end

	return true
end

function PlotsManager.validateVanityComponentName(self: PlotsManager, vanityComponentName: string): boolean
	if self.mainPlotInnerDatas[vanityComponentName] then
		return true
	end

	if self.mainPlotOuterDatas[vanityComponentName] then
		return true
	end

	if self.fenceDatas[vanityComponentName] then
		return true
	end

	if self.expansionInnerDatas[vanityComponentName] then
		return true
	end

	if self.expansionOuterDatas[vanityComponentName] then
		return true
	end

	return false
end

function PlotsManager.getVanityComponentDataByName(self: PlotsManager, vanityComponentName: string): any
	local vanityComponentData: any

	vanityComponentData = self.mainPlotInnerDatas[vanityComponentName]
	if vanityComponentData then
		return vanityComponentData
	end

	vanityComponentData = self.mainPlotOuterDatas[vanityComponentName]
	if vanityComponentData then
		return vanityComponentData
	end

	vanityComponentData = self.fenceDatas[vanityComponentName]
	if vanityComponentData then
		return vanityComponentData
	end

	vanityComponentData = self.expansionInnerDatas[vanityComponentName]
	if vanityComponentData then
		return vanityComponentData
	end

	vanityComponentData = self.expansionOuterDatas[vanityComponentName]
	if vanityComponentData then
		return vanityComponentData
	end

	return nil
end

function PlotsManager.getCategoryVanityComponentNames(self: PlotsManager, vanityComponentName: string): { string }
	if self.mainPlotInnerDatas[vanityComponentName] then
		return self:getAllMainPlotInnerNames()
	end

	if self.mainPlotOuterDatas[vanityComponentName] then
		return self:getAllMainPlotOuterNames()
	end

	if self.fenceDatas[vanityComponentName] then
		return self:getAllFenceNames()
	end

	if self.expansionInnerDatas[vanityComponentName] then
		return self:getAllExpansionInnerNames()
	end

	if self.expansionOuterDatas[vanityComponentName] then
		return self:getAllExpansionOuterNames()
	end

	warn("unknown vanity component name", vanityComponentName)

	return {}
end

function PlotsManager.getAllVanityComponentNames(self: PlotsManager): { string }
	if self.allVanityComponentNames then
		return self.allVanityComponentNames
	end

	local names: { string } = {}
	utils.arrayAppend(names, self:getAllMainPlotInnerNames())
	utils.arrayAppend(names, self:getAllMainPlotOuterNames())
	utils.arrayAppend(names, self:getAllFenceNames())
	utils.arrayAppend(names, self:getAllExpansionInnerNames())
	utils.arrayAppend(names, self:getAllExpansionOuterNames())
	self.allVanityComponentNames = names

	return names
end

function PlotsManager.getVanityComponentNameForBlueprintName(self: PlotsManager, blueprintItemName: string): string?
	local allVanityComponentNames = self:getAllVanityComponentNames()
	for _, vanityComponentName in allVanityComponentNames do
		local vanityComponentData = self:getVanityComponentDataByName(vanityComponentName)
		if vanityComponentData.blueprintName == blueprintItemName then
			return vanityComponentName
		end
	end

	return nil
end

function PlotsManager.replacePlotModel(self: PlotsManager, plotIndex: number, name: any, path: string)
	--print("replace plot model", plotIndex, name, path)

	-- find existing plot model and destroy it
	local land = utils.findFirstDescendantWithNameAndAttribute(MergePlot, name :: string, Attributes.INDEX, plotIndex)
	if land then
		land:Destroy()
	end

	local cframe = PlotHelpers.translateCFramePlotToWorld(self.plotPartCFrames[name], plotIndex)

	-- create instance from path and put it in place

	-- a missing template crashed here before typing too
	local template = utils.getPathReference(GameAssets, path) :: any
	local newLand = template:Clone()
	newLand.Name = name :: string
	newLand:PivotTo(cframe)
	newLand:SetAttribute(Attributes.INDEX, plotIndex)
	newLand.Parent = MergePlot
end

function PlotsManager.restoreInnerPlot(self: PlotsManager, plotIndex: number)
	local landPlotInnerData = self:getVanityComponentDataByName(DEFAULT_LAND_PLOT_INNER_NAME)
	self:replacePlotModel(plotIndex, enums.getName(enums.VanityPlacements, enums.VanityPlacements.MAIN_PLOT_INNER), landPlotInnerData.templatePath)
end

function PlotsManager.restoreOuterPlot(self: PlotsManager, plotIndex: number)
	local landPlotOuterData = self:getVanityComponentDataByName(DEFAULT_LAND_PLOT_OUTER_NAME)
	self:replacePlotModel(plotIndex, enums.getName(enums.VanityPlacements, enums.VanityPlacements.MAIN_PLOT_OUTER), landPlotOuterData.templatePath)
end

function PlotsManager.removeVanityName(self: PlotsManager, plotIndex: number, name: any)
	-- there are no fences or expansions by default, so just remove if we have one

	-- find existing plot model and destroy it
	local vanityComponent = utils.findFirstDescendantWithNameAndAttribute(MergePlot, name :: string, Attributes.INDEX, plotIndex)
	if vanityComponent then
		vanityComponent:Destroy()
	end
end

function PlotsManager.restoreExpansionInner(self: PlotsManager, plotIndex: number, vanityPlacement: number)
	local vanityComponentName = DEFAULT_EXPANSION_INNER_NAME
	self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.expansionInnerDatas[vanityComponentName].templatePaths[vanityPlacement])
end

function PlotsManager.restoreExpansionOuter(self: PlotsManager, plotIndex: number, vanityPlacement: number)
	local vanityComponentName = DEFAULT_EXPANSION_OUTER_NAME
	self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.expansionOuterDatas[vanityComponentName].templatePaths[vanityPlacement])
end

function PlotsManager.replaceVanityInstance(self: PlotsManager, plotIndex: number, name: any, path: string)
	--print("replace vanity instance", plotIndex, name, path)

	-- find existing plot model and destroy it
	local vanityComponent = utils.findFirstDescendantWithNameAndAttribute(MergePlot, name :: string, Attributes.INDEX, plotIndex)
	if vanityComponent then
		vanityComponent:Destroy()
	end

	-- create instance from path and put it in place

	-- a missing template crashed here before typing too
	local template = utils.getPathReference(GameAssets, path) :: any
	local newVanityComponent = template:Clone()
	newVanityComponent.Name = name :: string

	local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(newVanityComponent:GetPivot(), 1)
	local cframe = PlotHelpers.translateCFramePlotToWorld(plotCFrame, plotIndex)
	newVanityComponent:PivotTo(cframe)
	newVanityComponent:SetAttribute(Attributes.INDEX, plotIndex)
	newVanityComponent.Parent = MergePlot
end

function PlotsManager.equipVanityComponentForPlayerAtPlacement(self: PlotsManager, player: Player, vanityPlacement: number, vanityComponentName: string)
	local plotIndex = self:getPlotIndexByUserId(player.UserId) :: number

	if self.mainPlotInnerDatas[vanityComponentName] then
		self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.mainPlotInnerDatas[vanityComponentName].templatePath)
		return
	end

	if self.mainPlotOuterDatas[vanityComponentName] then
		self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.mainPlotOuterDatas[vanityComponentName].templatePath)
		return
	end

	if self.fenceDatas[vanityComponentName] then
		self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.fenceDatas[vanityComponentName].templatePaths[vanityPlacement])
		return
	end

	if self.expansionInnerDatas[vanityComponentName] then
		self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.expansionInnerDatas[vanityComponentName].templatePaths[vanityPlacement])
		return
	end

	if self.expansionOuterDatas[vanityComponentName] then
		self:replaceVanityInstance(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement), self.expansionOuterDatas[vanityComponentName].templatePaths[vanityPlacement])
		return
	end

	warn("unknown vanity component to equip", player, vanityComponentName)
end

function PlotsManager.unequipVanityPlacementForPlayer(self: PlotsManager, player: Player, vanityPlacement: number)
	local plotIndex = self:getPlotIndexByUserId(player.UserId) :: number

	if vanityPlacement == enums.VanityPlacements.MAIN_PLOT_INNER then
		self:restoreInnerPlot(plotIndex)
		return
	end

	if vanityPlacement == enums.VanityPlacements.MAIN_PLOT_OUTER then
		self:restoreOuterPlot(plotIndex)
		return
	end

	if vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_1 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_2 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_3 or
		vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_4 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_5 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_6 or
		vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_7 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_8 or vanityPlacement == enums.VanityPlacements.MAIN_PLOT_FENCE_9 then
		self:removeVanityName(plotIndex, enums.getName(enums.VanityPlacements, vanityPlacement))
		return
	end

	-- expansions

	if vanityPlacement == enums.VanityPlacements.EXPANSION_1_INNER or vanityPlacement == enums.VanityPlacements.EXPANSION_2_INNER or
		vanityPlacement == enums.VanityPlacements.EXPANSION_3_INNER or vanityPlacement == enums.VanityPlacements.EXPANSION_4_INNER then
		-- restore default; it must be unlocked already
		self:restoreExpansionInner(plotIndex, vanityPlacement)
		return
	end

	if vanityPlacement == enums.VanityPlacements.EXPANSION_1_OUTER or vanityPlacement == enums.VanityPlacements.EXPANSION_2_OUTER or
		vanityPlacement == enums.VanityPlacements.EXPANSION_3_OUTER or vanityPlacement == enums.VanityPlacements.EXPANSION_4_OUTER then
		-- restore default; it must be unlocked already
		self:restoreExpansionOuter(plotIndex, vanityPlacement)
		return
	end

	warn("unknown vanity placement to unequip", player, vanityPlacement)
end

function PlotsManager.calculateTreeBounds(self: PlotsManager, root: any): any
	local minX = math.huge
	local maxX = -math.huge
	local minZ = math.huge
	local maxZ = -math.huge

	if root:IsA("BasePart") then
		minX = math.min(minX, root.Position.X - root.Size.X / 2)
		maxX = math.max(maxX, root.Position.X + root.Size.X / 2)
		minZ = math.min(minZ, root.Position.Z - root.Size.Z / 2)
		maxZ = math.max(maxZ, root.Position.Z + root.Size.Z / 2)
	end

	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		minX = math.min(minX, descendant.Position.X - descendant.Size.X / 2)
		maxX = math.max(maxX, descendant.Position.X + descendant.Size.X / 2)
		minZ = math.min(minZ, descendant.Position.Z - descendant.Size.Z / 2)
		maxZ = math.max(maxZ, descendant.Position.Z + descendant.Size.Z / 2)
	end

	local minPosition = Vector3.new(minX, 0, minZ)
	local maxPosition = Vector3.new(maxX, 0, maxZ)

	return {
		minPosition = minPosition,
		maxPosition = maxPosition,
	}
end

function PlotsManager.init(self: PlotsManager)
	self:initVanityData()

	-- calculate bounding rect of the plot area

	local InnerPart = utils.findFirstDescendant(MergePlot, "InnerPart")
	local mainBounds = self:calculateTreeBounds(InnerPart)

	--print("bounding of plot 1", minPosition, "to", maxPosition)

	local expansionBounds: { [number]: any } = {}
	local expansionVanityAreas = PlotHelpers.getExpansionVanityAreas()
	for _, vanityArea in expansionVanityAreas do
		local vanityPlacement = PlotHelpers.getInnerVanityPlacementByVanityArea(vanityArea) :: number
		local vanityComponentName = DEFAULT_EXPANSION_INNER_NAME
		local path = self.expansionInnerDatas[vanityComponentName].templatePaths[vanityPlacement]
		local template = utils.getPathReference(GameAssets, path)

		local bounds = self:calculateTreeBounds(template)
		expansionBounds[vanityArea] = bounds
	end

	-- now calculate it for all plots

	-- map from plot index to bounds structure {minPosition, maxPosition}
	self.mainBounds = {}
	-- map from plot index to vanity area to bounds structure {minPosition, maxPosition}
	self.expansionBounds = {}
	for plotIndex = 1, NUM_PLOTS do
		local mainPosition1 = self:translatePositionPlotToWorld(self:translatePositionWorldToPlot(mainBounds.minPosition, 1), plotIndex)
		local mainPosition2 = self:translatePositionPlotToWorld(self:translatePositionWorldToPlot(mainBounds.maxPosition, 1), plotIndex)

		local plotMainMinPosition = Vector3.new(math.min(mainPosition1.X, mainPosition2.X), 0, math.min(mainPosition1.Z, mainPosition2.Z))
		local plotMainMaxPosition = Vector3.new(math.max(mainPosition1.X, mainPosition2.X), 0, math.max(mainPosition1.Z, mainPosition2.Z))

		self.mainBounds[plotIndex] = {
			minPosition = plotMainMinPosition,
			maxPosition = plotMainMaxPosition,
		}
		--print("main bounds", plotIndex, self.mainBounds[plotIndex])

		self.expansionBounds[plotIndex] = {}
		for _, vanityArea in expansionVanityAreas do
			local position1 = self:translatePositionPlotToWorld(self:translatePositionWorldToPlot(expansionBounds[vanityArea].minPosition, 1), plotIndex)
			local position2 = self:translatePositionPlotToWorld(self:translatePositionWorldToPlot(expansionBounds[vanityArea].maxPosition, 1), plotIndex)

			local minPosition = Vector3.new(math.min(position1.X, position2.X), 0, math.min(position1.Z, position2.Z))
			local maxPosition = Vector3.new(math.max(position1.X, position2.X), 0, math.max(position1.Z, position2.Z))

			self.expansionBounds[plotIndex][vanityArea] = {
				minPosition = minPosition,
				maxPosition = maxPosition,
			}
			--print("expansion bounds", plotIndex, "vanity area", vanityArea, self.expansionBounds[plotIndex][vanityArea])
		end
	end

	-- take cframe of pre-existing inner and outer as the reference points
	-- probably should change this to instead use the cframes of the DEFAULT_LAND_PLOT_INNER_NAME and DEFAULT_LAND_PLOT_OUTER_NAME

	for _, plotPartName in {enums.getName(enums.VanityPlacements, enums.VanityPlacements.MAIN_PLOT_INNER), enums.getName(enums.VanityPlacements, enums.VanityPlacements.MAIN_PLOT_OUTER)} do
		local inst: any = Land:FindFirstChild(plotPartName :: string)
		self.plotPartCFrames[plotPartName :: string] = PlotHelpers.translateCFrameWorldToPlot(inst:GetPivot(), 1)
	end

	-- copy over the bridge from player 1 to all the other players
	for _, inst in (MergePlot:FindFirstChild("Bridge") :: Instance):GetChildren() do
		for plotIndex = 2, NUM_PLOTS do
			local newInst: any = inst:Clone()
			local currentCFrame = PlotHelpers.translateCFrameWorldToPlot(newInst:GetPivot(), 1)
			newInst:PivotTo(PlotHelpers.translateCFramePlotToWorld(currentCFrame, plotIndex))
			newInst:SetAttribute(Attributes.INDEX, plotIndex)
			newInst.Parent = MergePlot
		end
	end

	-- set default plot inner and outer land

	for plotIndex = 1, NUM_PLOTS do
		self:restoreInnerPlot(plotIndex)
		self:restoreOuterPlot(plotIndex)
	end

	-- move per-plot elements to be under server storage to clone out to each player when they come in
	PerPlotElements.Parent = ServerStorage

end

function PlotsManager.new(): PlotsManager
	local self: PlotsManager = setmetatable({
		mainPlotInnerDatas = {},
		mainPlotOuterDatas = {},
		fenceDatas = {},
		expansionInnerDatas = {},
		expansionOuterDatas = {},

		plotPartCFrames = {},

		assignments = {},
	} :: PlotsManagerFields, PlotsManager)

	return self
end

function PlotsManager.initClass(deps: any)
	itemManager = deps.itemManager
end

local singleton = PlotsManager.new()

return singleton
