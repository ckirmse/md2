--!strict

local IslandManager = {}
IslandManager.__index = IslandManager

local tweenService = game:GetService("TweenService")

local Chest = require("./Chest")
local Critter = require("./Critter")
local EraManager = require("./EraManager")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local objectDataStore = require("./ObjectDataStore")
local plotsManager = require("./PlotsManager")
local Node = require("./Node")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Level = workspace:WaitForChild("Level")
local IslandsParent = Level:WaitForChild("Islands")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Islands = GameAssets:WaitForChild("Islands")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local lootTableManager = require("./LootTableManager")
local Timer = require("./Timer")

local nodeData = require("@game/ServerScriptService/GameData/Control/Nodes")

-- 20 minutes per refresh
local ERA_DURATION_SEC = 20 * 60

-- island records hold instances, bounds and object-id lists and are built dynamically, so they stay untyped
type IslandManagerFields = {
	currentEra: number,
	eraManager: EraManager.EraManager,
	islandDatas: { any },
	nodeMap: { [number]: any },
	chestMap: { [number]: any },
	critterMap: { [number]: any },
	pendingDestroyIslandDatas: { any },
	pendingCreateIslandParameters: { any },
	attemptCreate: number,
	failedCreate: number,
	successfulCreate: number,
	pollTimer: Timer.Timer?,
}

export type IslandManager = typeof(setmetatable({} :: IslandManagerFields, IslandManager))

function IslandManager.createNodesOnIsland(self: IslandManager, islandData: any, nodeTypeLootName: string?, random: Random)
	-- add a node to each NodeSpawn attachment point on the island

	local island = islandData.island

	for _, attachment in utils.getAllDescendantsByName(island, "NodeSpawn") do
		if not nodeTypeLootName then
			warn("island", island, "has a NodeSpawn but no configured nodeTypeLootName")
			return
		end


		local nodeLootEntries = lootTableManager:calculateLootResultsWithRandom(nodeTypeLootName, random)
		for _, nodeLootEntry in nodeLootEntries do
			local objectName = nodeLootEntry.result
			local objectData = objectDataStore:getObjectDataByName(objectName)
			if not objectData then
				warn("should make node", objectName, "but have no object data")
				continue
			end
			local objectDataType = objectDataStore:getObjectDataTypeByName(objectName) :: any
			local template = objectDataType:getTemplate()
			if not template then
				warn("should make node", objectName, "but it has no template")
				continue
			end

			local nodeGroundPosition = (attachment :: any).WorldPosition
			local nodePosition = nodeGroundPosition + Vector3.new(0, objectData.modelDepth, 0)
			local nodeCFrame = CFrame.new(nodePosition)

			local objectId = gameController:getNextObjectId()
			local node = Node.new(objectData, nodeCFrame, objectId)
			self.nodeMap[objectId] = node

			table.insert(islandData.nodeObjectIds, objectId)

			local obj = node:getObj()
			obj.Parent = workspace
		end
	end
end

function IslandManager.createChestsOnIsland(self: IslandManager, islandData: any, chestTypeLootName: string?, random: Random)
	-- add a chest to each ChestSpawn attachment point on the island

	local island = islandData.island

	for _, attachment in utils.getAllDescendantsByName(island, "ChestSpawn") do
		local chestLootEntries = lootTableManager:calculateLootResultsWithRandom(chestTypeLootName :: string, random)

		for _, chestLootEntry in chestLootEntries do
			local objectName = chestLootEntry.result
			local objectData = objectDataStore:getObjectDataByName(objectName)
			if not objectData then
				warn("should make chest", objectName, "but have no object data")
				continue
			end
			local objectDataType = objectDataStore:getObjectDataTypeByName(objectName) :: any
			local template = objectDataType:getTemplate()
			if not template then
				warn("should make chest", objectName, "but it has no template")
				continue
			end

			local chestGroundPosition = (attachment :: any).WorldPosition
			local chestPosition = chestGroundPosition + Vector3.new(0, objectData.modelDepth, 0)
			local chestCFrame = (attachment :: any).WorldCFrame.Rotation + chestPosition

			local objectId = gameController:getNextObjectId()
			local chest = Chest.new(objectData, chestCFrame, objectId)
			self.chestMap[objectId] = chest

			table.insert(islandData.chestObjectIds, objectId)

			local obj = chest:getObj()
			obj.Parent = workspace
		end
	end
end

function IslandManager.configureIslandAsCritter(self: IslandManager, islandData: any, objectName: string, position: Vector3)
	local objectData = objectDataStore:getObjectDataByName(objectName)
	if not objectData then
		warn("should make critter", objectName, "but have no object data")
		return
	end
	local objectDataType = objectDataStore:getObjectDataTypeByName(objectName) :: any
	local template = objectDataType:getTemplate()
	if not template then
		warn("should make critter", objectName, "but it has no template")
		return
	end

	local objectId = gameController:getNextObjectId()
	local critter = Critter.new(objectData, CFrame.new(position), objectId)
	self.critterMap[objectId] = critter

	table.insert(islandData.critterObjectIds, objectId)

	local obj = critter:getObj()
	obj.Parent = workspace
end

local function doIslandDatasIntersect(a: any, b: any): boolean
	local extraSpace = Vector3.new(5, 5, 5)

	local minA = a.minPosition - extraSpace
	local maxA = a.maxPosition + extraSpace
	local minB = b.minPosition - extraSpace
	local maxB = b.maxPosition + extraSpace

	return (minA.X <= maxB.X and maxA.X >= minB.X) and
	       (minA.Y <= maxB.Y and maxA.Y >= minB.Y) and
	       (minA.Z <= maxB.Z and maxA.Z >= minB.Z)
end

function IslandManager.createIslandDataFromIsland(self: IslandManager, island: any): any
	local islandPosition = island:GetPivot().Position
	local islandSize = island:GetExtentsSize()
	local minPosition = islandPosition - islandSize / 2
	local maxPosition = islandPosition + islandSize / 2

	local islandData = {
		island = island,
		minPosition = minPosition,
		maxPosition = maxPosition,
		nodeObjectIds = {},
		chestObjectIds = {},
		critterObjectIds = {},
	}

	return islandData
end

function IslandManager.tryCreateIsland(self: IslandManager, lootTableName: string, random: Random, locationMap: any, mapPositionFunc: any): Model?
	--print("tryCreateIsland", lootTableName)
	local islandLootEntries = lootTableManager:calculateLootResultsWithRandom(lootTableName, random)
	-- this should just give us back one island to create
	local island: Model?
	for _, lootEntry in islandLootEntries do
		local locationName = lootEntry.result.locationName
		local positionData = locationMap[locationName]
		local x = random:NextNumber(positionData.minPosition[1], positionData.maxPosition[1])
		local y = random:NextNumber(positionData.minPosition[2], positionData.maxPosition[2])
		local z = random:NextNumber(positionData.minPosition[3], positionData.maxPosition[3])
		local plotPosition = Vector3.new(x, y, z)

		--print("creating an island", lootEntry.result.locationName, lootEntry.result.islandName, "at plot position", plotPosition)

		local position = mapPositionFunc(plotPosition)

		local angle = random:NextInteger(0, 3) * 90
		local rotation = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(angle))
		local cframe = rotation + position

		local islandData: any

		if lootEntry.result.critterTypeLootName then
			island = nil

			local critterLootEntries = lootTableManager:calculateLootResultsWithRandom(lootEntry.result.critterTypeLootName, random)
			if #critterLootEntries ~= 1 then
				warn("critter loot entries has more than 1; needs to be exactly 1", lootEntry.result.critterLootName)
				continue
			end

			local critterLootEntry = critterLootEntries[1]
			local objectName = critterLootEntry.result
			local objectData = objectDataStore:getObjectDataByName(objectName)

			-- roughly contain the whole path of the critter
			local minPosition = position + Vector3.new(-objectData.maxRadius, -20, -objectData.maxRadius)
			local maxPosition = position + Vector3.new(objectData.maxRadius, 10, objectData.maxRadius)

			islandData = {
				island = island,
				minPosition = minPosition,
				maxPosition = maxPosition,
				nodeObjectIds = {},
				chestObjectIds = {},
				critterObjectIds = {},
			}

			self:configureIslandAsCritter(islandData, objectName, position)

		else
			local IslandTemplate = Islands:FindFirstChild(lootEntry.result.islandName)
			if not IslandTemplate then
				warn("unknown island instance named", lootEntry.result.islandName)
				continue
			end

			-- island templates are all Models
			local newIsland = IslandTemplate:Clone() :: Model

			newIsland:PivotTo(cframe)

			island = newIsland
			islandData = self:createIslandDataFromIsland(newIsland)
		end

		local isOverlapping = false
		for _, existingIslandData in self.islandDatas do
			if doIslandDatasIntersect(islandData, existingIslandData) then
				isOverlapping = true
				break
			end
		end

		if isOverlapping then
			if island then
				--print("skipping a regular or chest island", locationName, islandData, collisionIslandData)
				island:Destroy()
			end
			for _, objectId in islandData.critterObjectIds do
				local critter = self:getCritterByObjectId(objectId)
				if not critter then
					continue
				end
				--print("skipping a critter", islandData, collisionIslandData)
				critter:destroy()
				self.critterMap[objectId] = nil
			end

			return nil
		end

		if island then
			island.Parent = IslandsParent
		end

		if not lootEntry.result.critterTypeLootName then
			self:createNodesOnIsland(islandData, lootEntry.result.nodeTypeLootName, random)
			self:createChestsOnIsland(islandData, lootEntry.result.chestTypeLootName, random)
		end

		table.insert(self.islandDatas, islandData)
	end

	return island
end

function IslandManager.queueCreateIslandsParameters(self: IslandManager)
	local random = Random.new(self.currentEra)

	-- we create some islands in the rectangular area behind each plot
	local numPlots = plotsManager:getNumPlots()
	for plotIndex = 1, numPlots do
		local countLootEntries = lootTableManager:calculateLootResultsWithRandom("IslandCreationPlotCount", random)
		local count = countLootEntries[1].result
		--print("loot entries", countLootEntries, "and result count of this many islands in this plot", count)
		for i = 1, count do
			--[[
			self:tryCreateIsland("IslandCreationPlot", random, nodeData.islandLocationsPlot,
				function(position)
					return plotsManager:translatePositionPlotToWorld(position, plotIndex)
				end
			)
			]]
			table.insert(self.pendingCreateIslandParameters,
				{
					lootTableName = "IslandCreationPlot",
					random = random,
					locationMap = nodeData.islandLocationsPlot,
					mapPositionFunc =
						function(position)
							return plotsManager:translatePositionPlotToWorld(position, plotIndex)
						end,
				}
			)

		end
	end

	-- and then also at the end caps
	local numEndCaps = plotsManager:getNumEndCaps()
	for endCapIndex = 1, numEndCaps do
		local countLootEntries = lootTableManager:calculateLootResultsWithRandom("IslandCreationEndCapCount", random)
		local count = countLootEntries[1].result
		--print("loot entries", countLootEntries, "and result count of this many islands in this end cap", count)
		for i = 1, count do
			--[[
			self:tryCreateIsland("IslandCreationEndCap", random, nodeData.islandLocationsEndCap,
				function(position)
					return plotsManager:translatePositionEndCapToWorld(position, endCapIndex)
				end
				)
			]]
			table.insert(self.pendingCreateIslandParameters,
				{
					lootTableName = "IslandCreationEndCap",
					random = random,
					locationMap = nodeData.islandLocationsEndCap,
					mapPositionFunc =
						function(position)
							return plotsManager:translatePositionEndCapToWorld(position, endCapIndex)
						end,
				}
			)
		end

	end
end

function IslandManager.createFixedIslands(self: IslandManager, islandName: string)
	local random = Random.new(0)

	local numPlots = plotsManager:getNumPlots()
	for plotIndex = 1, numPlots do
		local lootEntry = lootTableManager:findLootTableEntryWithResultField("IslandCreationPlot", "islandName", islandName)

		local locationName = lootEntry.result.locationName
		local nodeTypeLootName = lootEntry.result.nodeTypeLootName
		-- nodeData has islandLocationsPlot/islandLocationsEndCap but no islandLocations key, so this
	-- indexes nil and crashes when called; preserved as-is and flagged for a real fix
	local positionData = (nodeData :: any).islandLocations[locationName]
		local x = (positionData.minPosition[1] + positionData.maxPosition[1]) / 2
		local y = (positionData.minPosition[2] + positionData.maxPosition[2]) / 2
		local z = (positionData.minPosition[3] + positionData.maxPosition[3]) / 2
		local plotPosition = Vector3.new(x, y, z)

		local position = plotsManager:translatePositionPlotToWorld(plotPosition, plotIndex)
		local cframe = CFrame.new(position)

		local islandTemplate = Islands:FindFirstChild(islandName)
		if not islandTemplate then
			warn("unknown island instance named", islandName)
			return
		end

		-- island templates are all Models
		local island = islandTemplate:Clone() :: Model

		island:PivotTo(cframe)

		island.Parent = IslandsParent

		local islandData = self:createIslandDataFromIsland(island)

		table.insert(self.islandDatas, islandData)

		self:createNodesOnIsland(islandData, nodeTypeLootName, random)
	end
end

function IslandManager.markToDestroyIslands(self: IslandManager)
	-- move current island datas to end of pending destroy island datas

	-- note that table move actually performs a copy
	table.move(self.islandDatas, 1, #self.islandDatas, #self.pendingDestroyIslandDatas + 1, self.pendingDestroyIslandDatas)
	self.islandDatas = {}
end

function IslandManager.getCurrentEra(self: IslandManager): number
	return self.currentEra
end

function IslandManager.getClosestNode(self: IslandManager, position: Vector3): any

	local bestNode = nil
	local bestDistance = math.huge

	for objectId, node in self.nodeMap do
		local distance = (node:getObj():GetPivot().Position - position).Magnitude
		if distance < bestDistance then
			bestNode = node
			bestDistance = distance
		end
	end

	return bestNode
end

function IslandManager.refillNodes(self: IslandManager)
	for objectId, node in self.nodeMap do
		node:notifyRefill()
	end

	gameController:sendSystemMessageToAllPlayers("Surprise! Crystal Islands are refreshing")
end

function IslandManager.isNodeObjectId(self: IslandManager, objectId: number): boolean
	return self.nodeMap[objectId] ~= nil
end

function IslandManager.isChestObjectId(self: IslandManager, objectId: number): boolean
	return self.chestMap[objectId] ~= nil
end

function IslandManager.isCritterObjectId(self: IslandManager, objectId: number): boolean
	return self.critterMap[objectId] ~= nil
end

function IslandManager.getNodeByObjectId(self: IslandManager, objectId: number): any
	return self.nodeMap[objectId]
end

function IslandManager.getChestByObjectId(self: IslandManager, objectId: number): any
	return self.chestMap[objectId]
end

function IslandManager.getCritterByObjectId(self: IslandManager, objectId: number): any
	return self.critterMap[objectId]
end

function IslandManager.tryMineNode(self: IslandManager, player: Player, objectId: number)

	if not self.nodeMap[objectId] then
		-- this could happen reasonably at changeover time
		print("Player", player, "cannot mine node object id", objectId, "that does not exist")
		return
	end

	local node = self.nodeMap[objectId]

	node:notifyTryMine(player)
end

function IslandManager.restockIslands(self: IslandManager)
	self.eraManager:clearTimer()

	local random = Random.new()
	self.currentEra = random:NextInteger(1, 1000000)

	self:markToDestroyIslands()

	self:queueCreateIslandsParameters()

	gameController:sendSystemMessageToAllPlayers("Surprise! Crystal Islands have been refreshed")

	self:setTimerForNextEra()
end

function IslandManager.restockFixedIslands(self: IslandManager, islandName: string)
	self.eraManager:clearTimer()

	local random = Random.new()
	self.currentEra = random:NextInteger(1, 1000000)

	self:markToDestroyIslands()

	self:createFixedIslands(islandName)

	gameController:sendSystemMessageToAllPlayers("Islands are all " .. islandName)

	self:setTimerForNextEra()
end

function IslandManager.updateIslands(self: IslandManager)
	self.eraManager:clearTimer()

	self.currentEra = self.eraManager:calculateCurrentEra()

	-- now we update for this era

	self:markToDestroyIslands()

	self:queueCreateIslandsParameters()

	gameController:sendSystemMessageToAllPlayers("Crystal Islands are being refreshed")

	self:setTimerForNextEra()
end

function IslandManager.setTimerForNextEra(self: IslandManager)
	self.eraManager:setTimerForNextEra(
		function()
			self:updateIslands()
		end
	)
end

function IslandManager.destroyPendingIslandsBatch(self: IslandManager, batchSize: number)
	--print("have pending destroy islands", #self.pendingDestroyIslandDatas, "destroying", batchSize)

	local index = 1
	while #self.pendingDestroyIslandDatas >= 1 and index <= batchSize do
		local islandData = self.pendingDestroyIslandDatas[#self.pendingDestroyIslandDatas]

		local island = islandData.island
		if island then
			island:Destroy()
		end

		for _, objectId in islandData.nodeObjectIds do
			local node = self:getNodeByObjectId(objectId)
			if not node then
				continue
			end
			node:destroy()
			self.nodeMap[objectId] = nil
		end

		for _, objectId in islandData.chestObjectIds do
			local chest = self:getChestByObjectId(objectId)
			if not chest then
				continue
			end
			chest:destroy()
			self.chestMap[objectId] = nil
		end

		for _, objectId in islandData.critterObjectIds do
			local critter = self:getCritterByObjectId(objectId)
			if not critter then
				continue
			end
			critter:destroy()
			self.critterMap[objectId] = nil
		end

		self.pendingDestroyIslandDatas[#self.pendingDestroyIslandDatas] = nil

		index += 1
	end
end

function IslandManager.beginFadeOutPendingIslandsBatch(self: IslandManager, batchSize: number, fadeDurationSec: number)
	local i = math.max(1, #self.pendingDestroyIslandDatas - batchSize + 1)
	while i <= #self.pendingDestroyIslandDatas do
		local islandData = self.pendingDestroyIslandDatas[i]

		local island = islandData.island
		if island then
			for _, descendant in island:GetDescendants() do
				if not descendant:IsA("BasePart") then
					continue
				end

				local tween = tweenService:Create(descendant, TweenInfo.new(fadeDurationSec), {Transparency=1})
				tween:Play()
			end
		end

		i += 1
	end
end

function IslandManager.createPendingIslandsBatch(self: IslandManager, batchSize: number, fadeDurationSec: number)
	--print("have pending create islands", #self.pendingCreateIslandParameters, "creating", batchSize)

	local index = 1
	while #self.pendingCreateIslandParameters >= 1 and index <= batchSize do
		self.attemptCreate += 1
		local createParameters = self.pendingCreateIslandParameters[#self.pendingCreateIslandParameters]

		local island = self:tryCreateIsland(createParameters.lootTableName, createParameters.random, createParameters.locationMap, createParameters.mapPositionFunc)
		if not island then
			self.failedCreate += 1
			continue
		end

		self.successfulCreate += 1

		for _, descendant in island:GetDescendants() do
			if not descendant:IsA("BasePart") then
				continue
			end

			if descendant.Name ~= "Islet" and string.sub(descendant.Name, 5) ~= "Cloud" then
				continue
			end

			descendant.Transparency = 1

			tweenService:Create(descendant, TweenInfo.new(fadeDurationSec), {Transparency=0}):Play()
		end

		self.pendingCreateIslandParameters[#self.pendingCreateIslandParameters] = nil
		index += 1
	end

end

function IslandManager.createPollTimer(self: IslandManager)

	local destroyBatchSize = 50
	local createBatchSize = 50

	local stepTime = 0.5
	local fadeDurationSec = stepTime

	self.pollTimer = Timer.new(stepTime,
		function()
			--print("island manager poll timer", #self.pendingDestroyIslandDatas, #self.pendingCreateIslandParameters)
			if #self.pendingDestroyIslandDatas > 0 then
				self:destroyPendingIslandsBatch(destroyBatchSize)
			end
			if #self.pendingDestroyIslandDatas > 0 then
				self:beginFadeOutPendingIslandsBatch(destroyBatchSize, fadeDurationSec)
			end

			if #self.pendingCreateIslandParameters > 0 then
				self:createPendingIslandsBatch(createBatchSize, fadeDurationSec)
				if #self.pendingCreateIslandParameters == 0 then
					--print("attempted to create", self.attemptCreate, "successful", self.successfulCreate, "failed", self.failedCreate)
				end
			end

			self:createPollTimer()
		end
	)
end

function IslandManager.init(self: IslandManager)
	self:updateIslands()

	self:createPollTimer()
end

function IslandManager.new(): IslandManager
	local self: IslandManager = setmetatable({
		currentEra = 0,
		eraManager = EraManager.new(ERA_DURATION_SEC),

		islandDatas = {},

		-- map from objectId to node object
		nodeMap = {},

		-- map from objectId to chest object
		chestMap = {},

		-- map from objectId to critter object
		critterMap = {},

		pendingDestroyIslandDatas = {},
		pendingCreateIslandParameters = {},

		attemptCreate = 0,
		failedCreate = 0,
		successfulCreate = 0,
	} :: IslandManagerFields, IslandManager)

	return self
end

function IslandManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = IslandManager.new()

return singleton
