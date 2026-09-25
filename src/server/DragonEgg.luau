--!strict


local MItem = require("./MItem")
local super = MItem

local DragonEgg = {}
DragonEgg.__index = setmetatable(DragonEgg, super)

local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local lootTableManager = require("./LootTableManager")
local objectDataStore = require("./ObjectDataStore")
local pickupMixin = require("./PickupMixin")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local carryingData = require("@game/ServerScriptService/GameData/Control/Carrying")
local hatchingData = require("@game/ServerScriptService/GameData/Control/Hatching")

local MUTATION_COUNT = enums.getCount(enums.Mutations)

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

function DragonEgg.computeLuckMultiplier(eggBaseLuck: number?, userId: number): number
	local plotLuckMultiplier = gameController:getPlotLuckMultiplierForUserId(userId)

	return (eggBaseLuck or 1) * plotLuckMultiplier
end

function DragonEgg.applyLuckBiasToLootTable(lootTable: any, luckMultiplier: number): { any }
	if luckMultiplier == 1 then
		return lootTable
	end

	local biasedLootTable = {}
	for _, lootEntry in lootTable do
		local itemName = lootEntry.result and lootEntry.result.itemName
		local resultItemData = itemName and objectDataStore:getObjectDataByName(itemName)
		local rarity = (resultItemData and resultItemData.rarity) or enums.Rarity.COMMON
		local rarityTier = rarity - enums.Rarity.COMMON

		local biasedLootEntry = table.clone(lootEntry)
		biasedLootEntry.weight = lootEntry.weight * luckMultiplier ^ rarityTier
		table.insert(biasedLootTable, biasedLootEntry)
	end

	return biasedLootTable
end

local function rollEggSize(random: Random, minSize: number?, maxSize: number?): number
	if not minSize or not maxSize then
		return 1
	end

	return minSize + random:NextNumber() * (maxSize - minSize)
end

local function computeCarryReturnSec(distanceFromHub: number): number
	return carryingData.baseCarryReturnSec + distanceFromHub * carryingData.carryReturnSecPerStud
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

	self:notifyPlacedInPlot()
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

function DragonEgg.canBePickedUp(self: DragonEgg): boolean
	return false
end

function DragonEgg.notifyPlacedInPlot(self: DragonEgg)
	self:cleanupCarrying()

	if self.hatchTimer then
		warn("egg is already incubating, ignoring second placement", self:getItemName())
		return
	end

	if self.pausedRemainingSec then
		local remainingSec = self.pausedRemainingSec
		self.pausedRemainingSec = nil
		self:beginIncubating(remainingSec)
		return
	end

	local biomeIndex = (self:getObj():GetAttribute(Attributes.SOURCE_BIOME_INDEX) :: number?) or 1
	self.incubatingBiomeIndex = biomeIndex

	self:beginIncubating(computeHatchDurationSec(biomeIndex))
end

function DragonEgg.beginIncubating(self: DragonEgg, durationSec: number)
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

function DragonEgg.beginCarrying(self: DragonEgg, dragon: Types.ShadowDragon)
	self.carryingDragonItemId = dragon:getItemId()

	local carryReturnSec: number
	if self.pausedCarryRemainingSec then
		carryReturnSec = self.pausedCarryRemainingSec
		self.pausedCarryRemainingSec = nil
	else
		local pickupPosition = self:getObj():GetPivot().Position
		local plotCenter = plotsManager:getPlotItemRecoveryPositionByUserId(dragon:getUserId())
		local distanceFromPlotCenter = plotCenter and (pickupPosition - plotCenter).Magnitude or 0
		carryReturnSec = computeCarryReturnSec(distanceFromPlotCenter)
		self:getObj():SetAttribute(Attributes.CARRY_TOTAL_SEC, carryReturnSec)
	end

	self:getObj():SetAttribute(Attributes.CARRY_EXPIRES_TIME, workspace:GetServerTimeNow() + carryReturnSec)

	self.carryTimer = Timer.new(carryReturnSec, function()
		self:notifyCarryExpired()
	end)
end

function DragonEgg.pauseCarrying(self: DragonEgg)
	if self.carryTimer then
		self.pausedCarryRemainingSec = self.carryTimer:getTimeLeft() or 0
		self.carryTimer:cancel()
		self.carryTimer = nil
	end

	self.carryingDragonItemId = nil
	self:getObj():SetAttribute(Attributes.CARRY_EXPIRES_TIME, nil)
end

function DragonEgg.cleanupCarrying(self: DragonEgg)
	if self.carryTimer then
		self.carryTimer:cancel()
		self.carryTimer = nil
	end

	self.pausedCarryRemainingSec = nil
	self.carryingDragonItemId = nil
	self:getObj():SetAttribute(Attributes.CARRY_TOTAL_SEC, nil)
	self:getObj():SetAttribute(Attributes.CARRY_EXPIRES_TIME, nil)
end

function DragonEgg.notifyCarryExpired(self: DragonEgg)
	self.carryTimer = nil
	self:getObj():SetAttribute(Attributes.CARRY_TOTAL_SEC, nil)
	self:getObj():SetAttribute(Attributes.CARRY_EXPIRES_TIME, nil)

	local dragon = self.carryingDragonItemId and itemManager:getItemById(self.carryingDragonItemId)
	self.carryingDragonItemId = nil

	if dragon then
		dragon:getObj():SetAttribute(Attributes.IS_CARRYING, false)
		dragon:getObj():SetAttribute(Attributes.CARRIED_EGG_ITEM_ID, nil)

		local player = players:GetPlayerByUserId(dragon:getUserId())
		if player then
			gameController:sendSystemMessageToPlayer(player, "The egg broke on the way back!")
		end
	end

	itemManager:destroyItem(self)
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

	local mutation = rollMutation(self.random)

	local userId = self:getUserId()

	local itemData = self:getItemData()
	local hatchLootTableName = itemData.hatchLootTableName
	local rawLootTable = hatchLootTableName and lootTableManager:getLootTable(hatchLootTableName)
	local luckMultiplier = DragonEgg.computeLuckMultiplier(itemData.eggBaseLuck, userId)
	local biasedLootTable = rawLootTable and DragonEgg.applyLuckBiasToLootTable(rawLootTable, luckMultiplier)
	local lootEntries = biasedLootTable and lootTableManager:calculateLootResultsByTableAndRandom(biasedLootTable, self.random)
	local itemCreationData = lootEntries and lootTableManager:getItemCreationDataFromItemLootResults(lootEntries)
	local dragonItemName = itemCreationData and next(itemCreationData)
	if not dragonItemName then
		warn("egg has no hatch loot table results, cannot hatch", self:getItemName())
		return
	end

	local position = self:getObj():GetPivot().Position

	local dragonItem = itemManager:createItem(dragonItemName, userId)
	if not dragonItem then
		warn("failed to create hatched dragon", dragonItemName)
		return
	end

	local hatchedDragon = dragonItem :: Types.ShadowDragon
	hatchedDragon:setMutation(mutation)
	hatchedDragon:setDragonSize(self.eggSize)

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
	retval.eggSize = self.eggSize

	if self.hatchTimer then
		retval.hatch = {
			biomeIndex = self.incubatingBiomeIndex,
			remainingSec = self.hatchTimer:getTimeLeft() or 0,
		}
	elseif self.pausedRemainingSec then
		retval.hatch = {
			biomeIndex = self.incubatingBiomeIndex,
			remainingSec = self.pausedRemainingSec,
			isPaused = true,
		}
	end

	return retval
end

function DragonEgg.loadSaveData(self: DragonEgg, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	if itemSaveData.eggSize then
		self.eggSize = itemSaveData.eggSize
	end
end

function DragonEgg.notifyLoadComplete(self: DragonEgg, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(self.eggSize)
	end

	if not itemSaveData.hatch then
		return
	end

	self.incubatingBiomeIndex = itemSaveData.hatch.biomeIndex

	if itemSaveData.hatch.isPaused then
		self.pausedRemainingSec = itemSaveData.hatch.remainingSec
		return
	end

	-- simulate offline time passing, matching Crystal's opening-timer resume pattern
	local remainingSec = math.max(0, itemSaveData.hatch.remainingSec - (offlineElapsedSec or 0))
	self:beginIncubating(remainingSec)
end

function DragonEgg.destroy(self: DragonEgg)
	self:cleanupIncubating()
	self:cleanupCarrying()

	super.destroy(self)
end

function DragonEgg.notifyNewClone(self: DragonEgg)
	--print("dragon egg notify new clone")

	super.notifyNewClone(self)

	local itemData = self:getItemData()

	self.random = Random.new()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)
	self:getObj():SetAttribute(Attributes.EGG_BASE_LUCK, itemData.eggBaseLuck or 1)
	self:getObj():SetAttribute(Attributes.NAME_PLATE_EXTRA_TEXT, string.format("Luck: %s", tostring(itemData.eggBaseLuck or 1)))

	self.eggSize = rollEggSize(self.random, itemData.minEggSize, itemData.maxEggSize)
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(self.eggSize)
	end

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)
end

function DragonEgg.new(itemId: number, itemName: string, userId: number): DragonEgg
	local self = (setmetatable(super.new(itemId, itemName, userId), DragonEgg) :: any) :: DragonEgg

	local itemData = self:getItemData()

	self.random = Random.new()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)
	self:getObj():SetAttribute(Attributes.EGG_BASE_LUCK, itemData.eggBaseLuck or 1)
	self:getObj():SetAttribute(Attributes.NAME_PLATE_EXTRA_TEXT, string.format("Luck: %s", tostring(itemData.eggBaseLuck or 1)))

	self.eggSize = rollEggSize(self.random, itemData.minEggSize, itemData.maxEggSize)
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(self.eggSize)
	end

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)

	return self
end

function DragonEgg.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return DragonEgg
