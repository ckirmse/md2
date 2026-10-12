--!strict

local EggSlotManager = {}
EggSlotManager.__index = EggSlotManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Level = workspace:WaitForChild("Level")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local plotsManager = require("./PlotsManager")
local rideMixin = require("./RideMixin")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local SLOT_TEMPLATE_PARENT_NAME = "Land"
local SLOT_TEMPLATE_NAME = "EggSlotTemplate"

type EggSlotManagerFields = {
	slotTemplate: Instance?,
	slotMarkerCFrames: { [number]: CFrame }, -- in plot 1's coordinates, keyed by slot index
	spawnedSlotCounts: { [Player]: number },
}

export type EggSlotManager = typeof(setmetatable({} :: EggSlotManagerFields, EggSlotManager))

function EggSlotManager.getEggSlotCount(self: EggSlotManager, player: Player): number
	return gameController:getEggSlotCountForRebirthLevel(gameController:getPlayerData(player):getRebirthLevel())
end

function EggSlotManager.getEggSlotAnchorCFrame(self: EggSlotManager, userId: number, eggSlotIndex: number): CFrame?
	local plotIndex = plotsManager:getPlotIndexByUserId(userId)
	if not plotIndex then
		warn("cannot resolve egg slot anchor without a plot", userId)
		return nil
	end

	local slotModel =
		utils.findFirstDescendantWithNameAndAttribute(Level, "EggSlot" .. eggSlotIndex, Attributes.INDEX, plotIndex)
	if not slotModel then
		warn("missing egg slot", userId, plotIndex, eggSlotIndex)
		return nil
	end

	local anchor = slotModel:FindFirstChild("Anchor")
	if not anchor then
		warn("egg slot missing Anchor part", userId, plotIndex, eggSlotIndex)
		return nil
	end

	return (anchor :: BasePart):GetPivot()
end

function EggSlotManager.tryPlaceEgg(self: EggSlotManager, player: Player, itemId: number, eggSlotIndex: number): boolean
	local playerData = gameController:getPlayerData(player)

	if
		eggSlotIndex ~= math.floor(eggSlotIndex)
		or eggSlotIndex < 1
		or eggSlotIndex > self:getEggSlotCount(player)
	then
		print("reject place egg: egg slot out of range", player, eggSlotIndex)
		return false
	end

	local item = itemManager:getItemById(itemId)
	if not item or item:getType() ~= "dragonEgg" then
		print("reject place egg: not an egg", player, itemId)
		return false
	end

	local egg = item :: Types.DragonEgg

	-- an egg in a dragon's basket is unowned until delivered, and is owned but still in the basket once the dragon is
	-- over the plot, so the basket is found from the ridden dragon rather than from the egg
	local carryingDragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if carryingDragon and carryingDragon:getObj():GetAttribute(Attributes.CARRIED_EGG_ITEM_ID) ~= itemId then
		carryingDragon = nil
	end
	local isCarriedByPlayer = carryingDragon ~= nil
	if egg:getUserId() ~= player.UserId and not isCarriedByPlayer then
		print("reject place egg: egg is not the player's", player, itemId)
		return false
	end

	if egg:getEggSlotIndex() ~= nil then
		print("reject place egg: egg already in a slot", player, itemId, egg:getEggSlotIndex())
		return false
	end

	if playerData:getEggInSlot(eggSlotIndex) ~= nil then
		print("reject place egg: egg slot occupied", player, eggSlotIndex)
		return false
	end

	local anchorCFrame = self:getEggSlotAnchorCFrame(player.UserId, eggSlotIndex)
	if not anchorCFrame then
		return false
	end

	if egg:getCount() > 1 then
		local split = egg:splitOffOne()
		if not split then
			print("reject place egg: failed to split egg from stack", player, itemId)
			return false
		end
		egg = split :: Types.DragonEgg
	end

	if carryingDragon then
		carryingDragon:getObj():SetAttribute(Attributes.IS_CARRYING, false)
		carryingDragon:getObj():SetAttribute(Attributes.CARRIED_EGG_ITEM_ID, nil)
	end
	egg:setUserId(player.UserId)

	playerData:setEggInSlot(eggSlotIndex, egg:getItemId())
	egg:placeInEggSlot(eggSlotIndex, anchorCFrame :: CFrame)

	self:notifyEggSlotsChanged(player)
	return true
end

function EggSlotManager.tryRemoveEgg(self: EggSlotManager, player: Player, eggSlotIndex: number): boolean
	local playerData = gameController:getPlayerData(player)

	local itemId = playerData:getEggInSlot(eggSlotIndex)
	if not itemId then
		print("reject remove egg: egg slot empty", player, eggSlotIndex)
		return false
	end

	local item = itemManager:getItemById(itemId)
	if not item or item:getType() ~= "dragonEgg" then
		-- stale slot: drop it so the player is not stuck
		playerData:clearEggSlot(eggSlotIndex)
		self:notifyEggSlotsChanged(player)
		return false
	end

	local egg = item :: Types.DragonEgg

	if egg:isReadyToHatch() then
		print("reject remove egg: egg is ready to hatch", player, eggSlotIndex)
		return false
	end

	egg:clearEggSlot()
	egg:putInBackpack()

	self:notifyEggSlotsChanged(player)
	return true
end

-- called by DragonEgg.notifyLoadComplete for an egg whose save carried an eggSlotIndex
function EggSlotManager.placeEggOnLoad(self: EggSlotManager, egg: Types.DragonEgg)
	local eggSlotIndex = egg:getEggSlotIndex()
	if not eggSlotIndex then
		return
	end

	local player = egg:getPlayer()
	if not player then
		return
	end

	local playerData = gameController:getPlayerData(player)

	if
		eggSlotIndex < 1
		or eggSlotIndex > self:getEggSlotCount(player)
		or playerData:getEggInSlot(eggSlotIndex) ~= nil
	then
		warn(
			"dropping slotted egg with a bad/duplicate saved egg slot",
			player,
			eggSlotIndex,
			"slot count",
			self:getEggSlotCount(player),
			"occupant",
			playerData:getEggInSlot(eggSlotIndex)
		)
		egg:clearEggSlot()
		return
	end

	playerData:setEggInSlot(eggSlotIndex, egg:getItemId())
	egg:markInEggSlot(eggSlotIndex)

	local anchorCFrame = self:getEggSlotAnchorCFrame(player.UserId, eggSlotIndex)
	if anchorCFrame then
		egg:getObj():PivotTo(anchorCFrame :: CFrame)
	end
end

function EggSlotManager.notifyEggSlotsChanged(self: EggSlotManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	RemoteEvents.NotifyEggSlotsChanged:FireClient(player, playerData:getEggSlots())
end

function EggSlotManager.new(): EggSlotManager
	local self = setmetatable({
		slotTemplate = nil,
		slotMarkerCFrames = {},
		spawnedSlotCounts = {},
	} :: EggSlotManagerFields, EggSlotManager)
	return self
end

function EggSlotManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

-- the finished slots are not part of the plot template: each plot gets clones of the EggSlotTemplate model in
-- GameAssets at the hand-placed EggSlotMarker<N> positions, only up to its owner's slot count. The markers and any
-- leftover authored EggSlot<N> models are read and removed here so they are not cloned into the plots
function EggSlotManager.collectEggSlotMarkers(self: EggSlotManager)
	local markers: { Instance } = {}
	local authoredSlotModels: { Instance } = {}
	for _, inst in plotsManager:getPerPlotElements():GetDescendants() do
		local markerIndexText = string.match(inst.Name, "^EggSlotMarker(%d+)$")
		if markerIndexText then
			table.insert(markers, inst)
			self.slotMarkerCFrames[tonumber(markerIndexText) :: number] = (inst :: any):GetPivot()
		elseif string.match(inst.Name, "^EggSlot%d+$") then
			table.insert(authoredSlotModels, inst)
		end
	end

	local templateParent = GameAssets:FindFirstChild(SLOT_TEMPLATE_PARENT_NAME)
	local slotTemplate = templateParent and templateParent:FindFirstChild(SLOT_TEMPLATE_NAME)
	if not slotTemplate or not slotTemplate:FindFirstChild("Anchor") then
		warn(`EggSlotManager: GameAssets.{SLOT_TEMPLATE_PARENT_NAME}.{SLOT_TEMPLATE_NAME} with an Anchor part is missing, keeping the authored egg slots`)
	else
		self.slotTemplate = slotTemplate
		for _, authoredSlotModel in authoredSlotModels do
			authoredSlotModel:Destroy()
		end

		for slotIndex = 1, gameController:getMaxEggSlotCount() do
			local markerCFrame = self.slotMarkerCFrames[slotIndex]
			if not markerCFrame then
				warn("EggSlotManager: no EggSlotMarker" .. slotIndex .. " in the plot template, so slot " .. slotIndex .. " will have no model")
			elseif not plotsManager:isPositionInMainPlotXZ(markerCFrame.Position, 1) then
				warn("EggSlotManager: EggSlotMarker" .. slotIndex .. " is outside the main plot")
			end
		end
	end

	for _, marker in markers do
		marker:Destroy()
	end
end

-- makes the plot have exactly the slots the player owns: spawns the missing ones and removes the ones above a lowered
-- count (a data reset). Called whenever the slot count is published, so it covers joining, every rebirth and resets,
-- and does nothing when the plot is already up to date
function EggSlotManager.syncEggSlotModels(self: EggSlotManager, player: Player, slotCount: number)
	local slotTemplate = self.slotTemplate
	if not slotTemplate then
		return
	end

	local plotIndex = plotsManager:getPlotIndexByUserId(player.UserId)
	if not plotIndex then
		return
	end

	local spawnedCount = self.spawnedSlotCounts[player] or 0
	if spawnedCount == slotCount then
		return
	end
	self.spawnedSlotCounts[player] = slotCount

	if spawnedCount > slotCount then
		for _, inst in plotsManager:getClonedPlotElements():GetChildren() do
			local slotIndexText = string.match(inst.Name, "^EggSlot(%d+)$")
			local slotIndex = if slotIndexText then tonumber(slotIndexText) else nil
			if slotIndex and slotIndex > slotCount and inst:GetAttribute(Attributes.INDEX) == plotIndex then
				inst:Destroy()
			end
		end
		return
	end

	for slotIndex = spawnedCount + 1, slotCount do
		local markerCFrame = self.slotMarkerCFrames[slotIndex]
		if not markerCFrame then
			continue
		end

		local slotModel: any = slotTemplate:Clone()
		slotModel.Name = "EggSlot" .. slotIndex
		slotModel:SetAttribute(Attributes.INDEX, plotIndex)
		for _, descendantInst in slotModel:GetDescendants() do
			descendantInst:SetAttribute(Attributes.INDEX, plotIndex)
		end

		local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(markerCFrame, 1)
		slotModel:PivotTo(PlotHelpers.translateCFramePlotToWorld(plotCFrame, plotIndex))
		slotModel.Parent = plotsManager:getClonedPlotElements()
	end
end

function EggSlotManager.notifyRemovePlayer(self: EggSlotManager, player: Player)
	self.spawnedSlotCounts[player] = nil
end

function EggSlotManager.init(self: EggSlotManager)
	self:collectEggSlotMarkers()
end

local singleton = EggSlotManager.new()

return singleton
