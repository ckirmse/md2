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
local eggSlotManager = require("./EggSlotManager")
local lootTableManager = require("./LootTableManager")
local objectDataStore = require("./ObjectDataStore")
local pickupMixin = require("./PickupMixin")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local HatchSkipMath = require("@game/ReplicatedStorage/Shared/HatchSkipMath")
local RarityMath = require("@game/ReplicatedStorage/Shared/RarityMath")
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

local DEFAULT_HATCH_HOLD_SEC = 1

function DragonEgg.getHatchHoldSec(): number
	local holdSec = hatchingData.hatchHoldSec
	return if type(holdSec) == "number" and holdSec >= 0 then holdSec else DEFAULT_HATCH_HOLD_SEC
end

function DragonEgg.getSkipSecPerDiamond(): number
	local secPerDiamond = hatchingData.skipSecPerDiamond
	return if type(secPerDiamond) == "number" and secPerDiamond > 0 then secPerDiamond else HatchSkipMath.DEFAULT_SEC_PER_DIAMOND
end

local function computeHatchDurationSec(distanceFromPlot: number): number
	return hatchingData.baseHatchSec + distanceFromPlot * hatchingData.hatchSecPerStud
end

function DragonEgg.computeLuckMultiplier(eggBaseLuck: number?, userId: number): number
	local plotLuckMultiplier = gameController:getPlotLuckMultiplierForUserId(userId)
	local rebirthLuckMultiplier = gameController:getRebirthLuckMultiplierForUserId(userId)
	-- placeholder until luck faeries and boosts exist (spec: Effective luck = Egg x Plot x Temporary)
	local temporaryLuckMultiplier = 1

	return (eggBaseLuck or 1) * plotLuckMultiplier * rebirthLuckMultiplier * temporaryLuckMultiplier
end

function DragonEgg.refreshLuckDisplay(self: DragonEgg)
	local itemData = self:getItemData()
	self:getObj():SetAttribute(
		Attributes.NAME_PLATE_EXTRA_TEXT,
		string.format("Luck: %g", DragonEgg.computeLuckMultiplier(itemData.eggBaseLuck, self:getUserId()))
	)
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

local function rollSizePercentile(random: Random, minPercentile: number?, maxPercentile: number?): number
	local low = minPercentile or RarityMath.STANDARD_SIZE_PERCENTILE_MIN
	local high = maxPercentile or RarityMath.STANDARD_SIZE_PERCENTILE_MAX

	return low + random:NextNumber() * (high - low)
end

local function computeCarryReturnSec(distanceFromHub: number): number
	local rawCarryReturnSec = carryingData.baseCarryReturnSec + distanceFromHub * carryingData.carryReturnSecPerStud
	return math.floor(rawCarryReturnSec / 5) * 5
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

	self:settleOnGroundInWorkspace(function() end)
end

-- eggs are placed by putting them on an egg slot, not by dropping them anywhere in the plot
function DragonEgg.getToolActivationItem(self: DragonEgg): any
	local player = self:getPlayer()
	if player then
		gameController:sendSystemMessageToPlayer(player, "Put your egg on an egg slot to hatch it")
	end
	return nil
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

	self:refreshLuckDisplay()

	if self.hatchTimer then
		warn("egg is already incubating, ignoring second placement", self:getItemName())
		return
	end

	if self:getItemData().instantHatch then
		self:beginIncubating(0)
		return
	end

	if self.pausedRemainingSec then
		local remainingSec = self.pausedRemainingSec
		self.pausedRemainingSec = nil
		self:beginIncubating(remainingSec)
		return
	end

	local sourcePosition = self:getObj():GetAttribute(Attributes.SOURCE_POSITION) :: Vector3?
	local plotCenter = plotsManager:getPlotItemRecoveryPositionByUserId(self:getUserId())
	local distanceFromPlot = 0
	if sourcePosition and plotCenter then
		distanceFromPlot = (sourcePosition - plotCenter).Magnitude
	end

	self:beginIncubating(computeHatchDurationSec(distanceFromPlot))
end

function DragonEgg.beginIncubating(self: DragonEgg, durationSec: number)
	self:setVenueWorkspaceAvailable()

	if durationSec <= 0 then
		self:notifyHatchReady()
		return
	end

	self.hatchCompleteTime = workspace:GetServerTimeNow() + durationSec

	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, self.hatchCompleteTime)

	self.hatchTimer = Timer.new(durationSec,
		function()
			self:notifyHatchReady()
		end
	)
end

function DragonEgg.notifyHatchReady(self: DragonEgg)
	self.hatchTimer = nil
	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, nil)
	collectionService:AddTag(self:getObj(), Tags.HATCHABLE_EGG)
end

function DragonEgg.isReadyToHatch(self: DragonEgg): boolean
	return collectionService:HasTag(self:getObj(), Tags.HATCHABLE_EGG)
end

function DragonEgg.cleanupIncubating(self: DragonEgg)
	if self.hatchTimer then
		self.hatchTimer:cancel()
		self.hatchTimer = nil
	end

	self:getObj():SetAttribute(Attributes.HATCH_COMPLETE_TIME, nil)
end

function DragonEgg.getHatchRemainingSec(self: DragonEgg): number?
	if not self.hatchTimer then
		return nil
	end

	return self.hatchTimer:getTimeLeft() or 0
end

function DragonEgg.skipHatch(self: DragonEgg)
	self:cleanupIncubating()
	self:notifyHatchReady()
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
	if not self.hatchTimer and not self:isReadyToHatch() then
		warn("egg is not incubating or ready, cannot force hatch", self:getItemName())
		return
	end

	if self.hatchTimer then
		self.hatchTimer:cancel()
		self.hatchTimer = nil
	end

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
	hatchedDragon:setTraits(self.traits)
	hatchedDragon:setSizePercentile(self.sizePercentile)

	itemManager:destroyItem(self)

	local player = players:GetPlayerByUserId(userId)
	local playerData = player and gameController:getPlayerData(player)
	if playerData and playerData:isAtDragonLimit() then
		dragonItem:putInBackpack()
		gameController:sendSystemMessageToPlayer(
			player,
			"Your plot is at its dragon limit, so the hatched dragon was placed in your backpack"
		)
		return
	end

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
	retval.sizePercentile = self.sizePercentile
	retval.eggSlotIndex = self.eggSlotIndex

	if self:isReadyToHatch() then
		retval.hatch = {
			isReady = true,
		}
	elseif self.hatchTimer then
		retval.hatch = {
			remainingSec = self.hatchTimer:getTimeLeft() or 0,
		}
	elseif self.pausedRemainingSec then
		retval.hatch = {
			remainingSec = self.pausedRemainingSec,
			isPaused = true,
		}
	end

	return retval
end

function DragonEgg.loadSaveData(self: DragonEgg, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	if itemSaveData.sizePercentile then
		self.sizePercentile = itemSaveData.sizePercentile
	end

	self.eggSlotIndex = itemSaveData.eggSlotIndex
end

function DragonEgg.notifyLoadComplete(self: DragonEgg, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(RarityMath.getSizeScale(self.sizePercentile))
	end

	if self.eggSlotIndex ~= nil then
		eggSlotManager:placeEggOnLoad(self)
	end

	if not itemSaveData.hatch then
		return
	end

	if itemSaveData.hatch.isReady then
		self:notifyHatchReady()
		return
	end

	if itemSaveData.hatch.isPaused then
		self.pausedRemainingSec = itemSaveData.hatch.remainingSec
		return
	end

	-- simulate offline time passing, matching Crystal's opening-timer resume pattern
	local remainingSec = math.max(0, itemSaveData.hatch.remainingSec - (offlineElapsedSec or 0))
	self:beginIncubating(remainingSec)
end

function DragonEgg.getEggSlotIndex(self: DragonEgg): number?
	return self.eggSlotIndex
end

function DragonEgg.markInEggSlot(self: DragonEgg, eggSlotIndex: number)
	self.eggSlotIndex = eggSlotIndex
	collectionService:AddTag(self:getObj(), Tags.SLOTTED_EGG)
	self:getObj():SetAttribute(Attributes.EGG_SLOT_INDEX, eggSlotIndex)
end

function DragonEgg.clearEggSlot(self: DragonEgg)
	local eggSlotIndex = self.eggSlotIndex
	self.eggSlotIndex = nil
	collectionService:RemoveTag(self:getObj(), Tags.SLOTTED_EGG)
	self:getObj():SetAttribute(Attributes.EGG_SLOT_INDEX, nil)

	local playerData = self:getPlayerData()
	if eggSlotIndex and playerData and playerData:getEggInSlot(eggSlotIndex) == self:getItemId() then
		playerData:clearEggSlot(eggSlotIndex)
	end
end

-- moves the egg (held in the backpack, carried by a dragon, or already in the world) onto a slot's anchor and starts
-- its incubation there
function DragonEgg.placeInEggSlot(self: DragonEgg, eggSlotIndex: number, slotCFrame: CFrame)
	self:cleanupCarrying()
	self:markInEggSlot(eggSlotIndex)

	local obj = self:getObj()
	if obj.Parent ~= workspace then
		-- leave the tool the same way a normal placement does, then enter the world without settling
		self:setPreventSettling()
		local tool = self:findTool()
		if tool then
			self.part.Parent = nil
			tool:Destroy()
		end
		if obj:IsA("Model") then
			self:setupChildPartsToObj()
		end
		self:moveFromPlayerToWorkspace()
	end

	utils.setPropertyTreeBaseParts(obj, "Anchored", true)
	obj:PivotTo(slotCFrame)

	self:notifyPlacedInPlot()
end

function DragonEgg.destroy(self: DragonEgg)
	self:clearEggSlot()
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
	self:refreshLuckDisplay()

	self.sizePercentile = rollSizePercentile(self.random, itemData.sizePercentileMin, itemData.sizePercentileMax)
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(RarityMath.getSizeScale(self.sizePercentile))
	end

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)
end

function DragonEgg.new(itemId: number, itemName: string, userId: number): DragonEgg
	local self = (setmetatable(super.new(itemId, itemName, userId), DragonEgg) :: any) :: DragonEgg

	local itemData = self:getItemData()

	self.random = Random.new()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)
	self:getObj():SetAttribute(Attributes.EGG_BASE_LUCK, itemData.eggBaseLuck or 1)
	self:refreshLuckDisplay()

	self.sizePercentile = rollSizePercentile(self.random, itemData.sizePercentileMin, itemData.sizePercentileMax)
	self.eggSlotIndex = nil
	local obj = self:getObj()
	if obj:IsA("Model") then
		obj:ScaleTo(RarityMath.getSizeScale(self.sizePercentile))
	end

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)

	return self
end

function DragonEgg.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return DragonEgg
