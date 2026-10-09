--!strict

local StableManager = {}
StableManager.__index = StableManager

local collectionService = game:GetService("CollectionService")
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
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local SLOT_TEMPLATE_PARENT_NAME = "Land"
local SLOT_TEMPLATE_NAME = "StableSlotTemplate"

type StableManagerFields = {
	slotTemplate: Instance?,
	slotMarkerCFrames: { [number]: CFrame }, -- in plot 1's coordinates, keyed by slot index
	spawnedSlotCounts: { [Player]: number },
}

export type StableManager = typeof(setmetatable({} :: StableManagerFields, StableManager))

function StableManager.getStableSlotCount(self: StableManager, player: Player): number
	return gameController:getDragonSlotCountForRebirthLevel(gameController:getPlayerData(player):getRebirthLevel())
end

function StableManager.getStableSlotAnchorCFrame(self: StableManager, userId: number, stableSlotIndex: number): CFrame?
	local plotIndex = plotsManager:getPlotIndexByUserId(userId)
	if not plotIndex then
		warn("cannot resolve stable slot anchor without a plot", userId)
		return nil
	end

	local slotModel =
		utils.findFirstDescendantWithNameAndAttribute(Level, "StableSlot" .. stableSlotIndex, Attributes.INDEX, plotIndex)
	if not slotModel then
		warn("missing stable slot", userId, plotIndex, stableSlotIndex)
		return nil
	end

	local anchor = slotModel:FindFirstChild("Anchor")
	if not anchor then
		warn("stable slot missing Anchor part", userId, plotIndex, stableSlotIndex)
		return nil
	end

	return (anchor :: BasePart):GetPivot()
end

function StableManager.tryEquipDragon(self: StableManager, player: Player, itemId: number, stableSlotIndex: number): boolean
	local playerData = gameController:getPlayerData(player)

	if
		stableSlotIndex ~= math.floor(stableSlotIndex)
		or stableSlotIndex < 1
		or stableSlotIndex > self:getStableSlotCount(player)
	then
		print("reject equip: stable slot out of range", player, stableSlotIndex)
		return false
	end

	local item = itemManager:getItemById(itemId)
	if not item or item:getType() ~= "shadowDragon" then
		print("reject equip: not a dragon", player, itemId)
		return false
	end

	local dragon = item :: Types.ShadowDragon

	if dragon:getUserId() ~= player.UserId then
		print("reject equip: dragon is not the player's", player, itemId)
		return false
	end

	if dragon:getStableSlotIndex() ~= nil then
		print("reject equip: dragon already equipped", player, itemId, dragon:getStableSlotIndex())
		return false
	end

	if playerData:getStableDragonInSlot(stableSlotIndex) ~= nil then
		print("reject equip: stable slot occupied", player, stableSlotIndex)
		return false
	end

	local anchorCFrame = self:getStableSlotAnchorCFrame(player.UserId, stableSlotIndex)
	if not anchorCFrame then
		return false
	end

	if dragon:getCount() > 1 then
		local split = dragon:splitOffOne()
		if not split then
			print("reject equip: failed to split dragon from stack", player, itemId)
			return false
		end
		dragon = split :: Types.ShadowDragon
	end

	dragon:setStableSlotIndex(stableSlotIndex)
	collectionService:AddTag(dragon:getObj(), Tags.EQUIPPED_DRAGON)
	dragon:getObj():SetAttribute(Attributes.DRAGON_SLOT_INDEX, stableSlotIndex)

	if dragon.isRiding then
		-- ridden to the slot: end the ride, notifyRideEnd flies it to the perch
		rideMixin:stopPlayerRiding(player)
	else
		dragon:parkInStableSlot(anchorCFrame :: CFrame)
	end

	playerData:setStableDragonInSlot(stableSlotIndex, dragon:getItemId())

	self:notifyStableSlotsChanged(player)
	return true
end

function StableManager.tryUnequipDragon(self: StableManager, player: Player, stableSlotIndex: number): boolean
	local playerData = gameController:getPlayerData(player)

	local itemId = playerData:getStableDragonInSlot(stableSlotIndex)
	if not itemId then
		print("reject unequip: stable slot empty", player, stableSlotIndex)
		return false
	end

	local item = itemManager:getItemById(itemId)
	if not item or item:getType() ~= "shadowDragon" then
		-- stale slot: drop it so the player is not stuck
		playerData:clearStableSlot(stableSlotIndex)
		self:notifyStableSlotsChanged(player)
		return false
	end

	local dragon = item :: Types.ShadowDragon

	if dragon.isRiding then
		print("reject unequip: dragon is being ridden", player, stableSlotIndex)
		return false
	end

	dragon:setStableSlotIndex(nil)
	collectionService:RemoveTag(dragon:getObj(), Tags.EQUIPPED_DRAGON)
	dragon:getObj():SetAttribute(Attributes.DRAGON_SLOT_INDEX, nil)
	dragon:returnToBackpackFromStableSlot()

	playerData:clearStableSlot(stableSlotIndex)

	self:notifyStableSlotsChanged(player)
	return true
end

-- called by ShadowDragon.notifyLoadComplete for a dragon whose save carried a stableSlotIndex
function StableManager.equipDragonOnLoad(self: StableManager, dragon: Types.ShadowDragon)
	local stableSlotIndex = dragon:getStableSlotIndex()
	if not stableSlotIndex then
		return
	end

	local player = dragon:getPlayer()
	if not player then
		return
	end

	local playerData = gameController:getPlayerData(player)

	if
		stableSlotIndex < 1
		or stableSlotIndex > self:getStableSlotCount(player)
		or playerData:getStableDragonInSlot(stableSlotIndex) ~= nil
	then
		warn("dropping equipped dragon with a bad/duplicate saved stable slot", player, stableSlotIndex)
		dragon:setStableSlotIndex(nil)
		return
	end

	local anchorCFrame = self:getStableSlotAnchorCFrame(player.UserId, stableSlotIndex)

	collectionService:AddTag(dragon:getObj(), Tags.EQUIPPED_DRAGON)
	dragon:getObj():SetAttribute(Attributes.DRAGON_SLOT_INDEX, stableSlotIndex)
	if anchorCFrame then
		dragon:parkInStableSlot(anchorCFrame :: CFrame)
	end

	playerData:setStableDragonInSlot(stableSlotIndex, dragon:getItemId())
end

function StableManager.notifyStableSlotsChanged(self: StableManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	RemoteEvents.NotifyStableSlotsChanged:FireClient(player, playerData:getStableSlots())
end

function StableManager.new(): StableManager
	local self = setmetatable({
		slotTemplate = nil,
		slotMarkerCFrames = {},
		spawnedSlotCounts = {},
	} :: StableManagerFields, StableManager)
	return self
end

function StableManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

-- the finished slots are not part of the plot template: each plot gets clones of the StableSlotTemplate model in
-- GameAssets at the hand-placed StableSlotMarker<N> positions, only up to its owner's slot count. The markers and any
-- leftover authored StableSlot<N> models are read and removed here so they are not cloned into the plots
function StableManager.collectStableSlotMarkers(self: StableManager)
	local markers: { Instance } = {}
	local authoredSlotModels: { Instance } = {}
	for _, inst in plotsManager:getPerPlotElements():GetDescendants() do
		local markerIndexText = string.match(inst.Name, "^StableSlotMarker(%d+)$")
		if markerIndexText then
			table.insert(markers, inst)
			self.slotMarkerCFrames[tonumber(markerIndexText) :: number] = (inst :: any):GetPivot()
		elseif string.match(inst.Name, "^StableSlot%d+$") then
			table.insert(authoredSlotModels, inst)
		end
	end

	local templateParent = GameAssets:FindFirstChild(SLOT_TEMPLATE_PARENT_NAME)
	local slotTemplate = templateParent and templateParent:FindFirstChild(SLOT_TEMPLATE_NAME)
	if not slotTemplate or not slotTemplate:FindFirstChild("Anchor") then
		warn(`StableManager: GameAssets.{SLOT_TEMPLATE_PARENT_NAME}.{SLOT_TEMPLATE_NAME} with an Anchor part is missing, keeping the authored stable slots`)
	else
		self.slotTemplate = slotTemplate
		for _, authoredSlotModel in authoredSlotModels do
			authoredSlotModel:Destroy()
		end

		for slotIndex = 1, gameController:getMaxDragonSlotCount() do
			local markerCFrame = self.slotMarkerCFrames[slotIndex]
			if not markerCFrame then
				warn("StableManager: no StableSlotMarker" .. slotIndex .. " in the plot template, so slot " .. slotIndex .. " will have no model")
			elseif not plotsManager:isPositionInMainPlotXZ(markerCFrame.Position, 1) then
				warn("StableManager: StableSlotMarker" .. slotIndex .. " is outside the main plot")
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
function StableManager.syncStableSlotModels(self: StableManager, player: Player, slotCount: number)
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
			local slotIndexText = string.match(inst.Name, "^StableSlot(%d+)$")
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
		slotModel.Name = "StableSlot" .. slotIndex
		slotModel:SetAttribute(Attributes.INDEX, plotIndex)
		for _, descendantInst in slotModel:GetDescendants() do
			descendantInst:SetAttribute(Attributes.INDEX, plotIndex)
		end

		local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(markerCFrame, 1)
		slotModel:PivotTo(PlotHelpers.translateCFramePlotToWorld(plotCFrame, plotIndex))
		slotModel.Parent = plotsManager:getClonedPlotElements()
	end
end

function StableManager.notifyRemovePlayer(self: StableManager, player: Player)
	self.spawnedSlotCounts[player] = nil
end

function StableManager.init(self: StableManager)
	self:collectStableSlotMarkers()
end

local singleton = StableManager.new()

return singleton
