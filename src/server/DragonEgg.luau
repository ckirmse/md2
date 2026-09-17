--!strict


local MItem = require("./MItem")
local super = MItem

local DragonEgg = {}
DragonEgg.__index = setmetatable(DragonEgg, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local pickupMixin = require("./PickupMixin")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local hatchingData = require("@game/ServerScriptService/GameData/Control/Hatching")

local RARITY_COUNT = enums.getCount(enums.Rarity)
local MUTATION_COUNT = enums.getCount(enums.Mutations)

local function rollRarity(random: Random, biomeIndex: number): number
	local odds = hatchingData.rarityOddsByBiome[biomeIndex] or hatchingData.rarityOddsByBiome[1]
	local roll = random:NextNumber()
	local cumulative = 0
	for rarity = 1, RARITY_COUNT do
		local chance = odds[rarity]
		if not chance then
			continue
		end
		cumulative += chance
		if roll < cumulative then
			return rarity
		end
	end
	return enums.Rarity.COMMON
end

local function rollMutation(random: Random): number
	local roll = random:NextNumber()
	local cumulative = 0
	for mutation = 1, MUTATION_COUNT do
		local chance = hatchingData.mutationOdds[mutation]
		if not chance then
			continue
		end
		cumulative += chance
		if roll < cumulative then
			return mutation
		end
	end
	return enums.Mutations.NORMAL
end

local function computeHatchDurationSec(biomeIndex: number): number
	return hatchingData.hatchSecByBiome[biomeIndex] or hatchingData.hatchSecByBiome[1]
end


export type DragonEggFields = Types.DragonEggFields
export type DragonEgg = Types.DragonEgg

function DragonEgg.getDataDumpString(self: DragonEgg): string
	local text = super.getDataDumpString(self)

	return text
end

-- doing this automatically (based on parent change) is not great, because there are different situations--
-- initial spawn, player placing later, etc., and they have different properties.
-- there are times we want to spawn an egg and have it NOT settle, because the spawning code has specific
-- other ways it wants the egg to move (this applies to other item types too)
function DragonEgg.notifyParentWorkspace(self: DragonEgg)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	-- parts have been made children of the model again before it gets here, so we do the normal thing (looking for descendants of obj)

	--print("egg put in workspace")

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		--print("letting egg get placed directly on ground, skipping settle")
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			self:tryBeginIncubatingFromPlacement()
		end
	)
end

function DragonEgg.tryBeginIncubatingFromPlacement(self: DragonEgg)
	if self.hatchTimer then
		return
	end

	local position = self:getObj():GetPivot().Position
	if not plotsManager:isPositionInMainPlotXZByUserId(position, self:getUserId()) then
		return
	end

	self:notifyPlacedInPlot(nil)
end

function DragonEgg.notifyParentPlayer(self: DragonEgg)
	super.notifyParentPlayer(self)

	self:pauseIncubating()
end

function DragonEgg.notifyMergingWithTriggerItem(self: DragonEgg, triggerItem: any)
	if self:getItemData().mixins.pickup then
		pickupMixin:notifyItemCannotBePickedUp(self)
	end

end

-- only pickable on foot once incubating in a plot; not while unclaimed at a nest or being carried
-- (those are dragon-only, via the nest pickup/carry flow)
function DragonEgg.canBePickedUp(self: DragonEgg): boolean
	return self.hatchTimer ~= nil
end

-- placing the egg in a plot is the incubation trigger; rarity/mutation are rolled now (from the
-- egg's source biome) but stay hidden until the dragon actually appears at hatch. carryingDragon
-- gets ride xp for the rolled rarity, matching document 3's per-egg-banked xp award
function DragonEgg.notifyPlacedInPlot(self: DragonEgg, carryingDragon: Types.ShadowDragon?)
	if self.hatchTimer then
		warn("egg is already incubating, ignoring second placement", self:getItemName())
		return
	end

	if self.pausedRemainingSec then
		local remainingSec = self.pausedRemainingSec
		self.pausedRemainingSec = nil
		self:beginIncubating(remainingSec, self.rolledRarity :: number, self.rolledMutation :: number)
		return
	end

	local biomeIndex = (self:getObj():GetAttribute(Attributes.SOURCE_BIOME_INDEX) :: number?) or 1

	local rarity = rollRarity(self.random, biomeIndex)
	local mutation = rollMutation(self.random)

	if carryingDragon then
		carryingDragon:addRideXp(hatchingData.rideXpByEggRarity[rarity] or 0)
	end

	self:beginIncubating(computeHatchDurationSec(biomeIndex), rarity, mutation)
end

function DragonEgg.beginIncubating(self: DragonEgg, durationSec: number, rolledRarity: number, rolledMutation: number)
	self.rolledRarity = rolledRarity
	self.rolledMutation = rolledMutation
	self.hatchCompleteTime = workspace:GetServerTimeNow() + durationSec

	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, self.hatchCompleteTime)

	self:setVenueWorkspaceAvailable()

	self.hatchTimer = Timer.new(durationSec,
		function()
			self:finishHatching()
		end
	)
end

function DragonEgg.cleanupIncubating(self: DragonEgg)
	if self.hatchTimer then
		self.hatchTimer:cancel()
		self.hatchTimer = nil
	end

	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, nil)
end

function DragonEgg.pauseIncubating(self: DragonEgg)
	if not self.hatchTimer then
		return
	end

	self.pausedRemainingSec = self.hatchTimer:getTimeLeft() or 0

	self:cleanupIncubating()
end

function DragonEgg.forceHatchNow(self: DragonEgg)
	if not self.hatchTimer then
		warn("egg is not incubating, cannot force hatch", self:getItemName())
		return
	end

	self.hatchTimer:cancel()
	self.hatchTimer = nil

	self:finishHatching()
end

function DragonEgg.finishHatching(self: DragonEgg)
	self.hatchTimer = nil
	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, nil)

	local hatchDragonNames = self:getItemData().hatchDragonNames
	local dragonItemName = hatchDragonNames and hatchDragonNames[self.rolledRarity :: number]
	if not dragonItemName then
		warn("egg has no hatchDragonNames entry for rolled rarity, cannot hatch", self:getItemName(), self.rolledRarity)
		return
	end

	local position = self:getObj():GetPivot().Position
	local userId = self:getUserId()

	local dragonItem = itemManager:createItem(dragonItemName, userId)
	if not dragonItem then
		warn("failed to create hatched dragon", dragonItemName)
		return
	end

	(dragonItem :: Types.MItem):setMutation(self.rolledMutation :: number)

	itemManager:destroyItem(self)

	gameController:spawnItemsAtPosition({ dragonItem }, position)
end

function DragonEgg.setPreventSettling(self: DragonEgg)
	self.doPreventSettling = true
end

function DragonEgg.getToolName(self: DragonEgg): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function DragonEgg.getSaveData(self: DragonEgg, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.type = "dragonEgg"

	if self.hatchTimer then
		retval.hatch = {
			rolledRarity = self.rolledRarity,
			rolledMutation = self.rolledMutation,
			remainingSec = self.hatchTimer:getTimeLeft() or 0,
		}
	elseif self.pausedRemainingSec then
		retval.hatch = {
			rolledRarity = self.rolledRarity,
			rolledMutation = self.rolledMutation,
			remainingSec = self.pausedRemainingSec,
			isPaused = true,
		}
	end

	return retval
end

function DragonEgg.loadSaveData(self: DragonEgg, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function DragonEgg.notifyLoadComplete(self: DragonEgg, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	if not itemSaveData.hatch then
		return
	end

	if itemSaveData.hatch.isPaused then
		self.rolledRarity = itemSaveData.hatch.rolledRarity
		self.rolledMutation = itemSaveData.hatch.rolledMutation
		self.pausedRemainingSec = itemSaveData.hatch.remainingSec
		return
	end

	-- simulate offline time passing, matching Crystal's opening-timer resume pattern
	local remainingSec = math.max(0, itemSaveData.hatch.remainingSec - (offlineElapsedSec or 0))
	self:beginIncubating(remainingSec, itemSaveData.hatch.rolledRarity, itemSaveData.hatch.rolledMutation)
end

function DragonEgg.destroy(self: DragonEgg)
	self:cleanupIncubating()

	super.destroy(self)
end

function DragonEgg.notifyNewClone(self: DragonEgg)
	--print("dragon egg notify new clone")

	super.notifyNewClone(self)

	local itemData = self:getItemData()

	self.random = Random.new()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)
end

function DragonEgg.new(itemId: number, itemName: string, userId: number): DragonEgg
	local self = (setmetatable(super.new(itemId, itemName, userId), DragonEgg) :: any) :: DragonEgg

	local itemData = self:getItemData()

	self.random = Random.new()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)

	return self
end

function DragonEgg.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return DragonEgg
