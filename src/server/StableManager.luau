--!strict

local StableManager = {}
StableManager.__index = StableManager

local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Level = workspace:WaitForChild("Level")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local plotsManager = require("./PlotsManager")
local rideMixin = require("./RideMixin")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

-- fixed for M1; M9 plot upgrades make this a per-player value from plotUpgrades.slots
local STABLE_SLOT_COUNT = 6

type StableManagerFields = {}

export type StableManager = typeof(setmetatable({} :: StableManagerFields, StableManager))

function StableManager.getStableSlotCount(self: StableManager): number
	return STABLE_SLOT_COUNT
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
		or stableSlotIndex > STABLE_SLOT_COUNT
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
		or stableSlotIndex > STABLE_SLOT_COUNT
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
	local self = setmetatable({}, StableManager)
	return self
end

function StableManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

function StableManager.init(self: StableManager) end

local singleton = StableManager.new()

return singleton
