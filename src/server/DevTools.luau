--!strict

local DevTools = {}
DevTools.__index = DevTools

local analyticsManager = require("./AnalyticsManager")
local buyStoreManager = require("./BuyStoreManager")
local contextualFtueManager = require("./ContextualFtueManager")
local CurrencyGranter = require("./CurrencyGranter")
local dailyLoginManager = require("./DailyLoginManager")
local dealShopManager = require("./DealShopManager")
local vanityStoreManager = require("./VanityStoreManager")
local Types = require("./Types")
local gameController: Types.GameController
local DragonEgg = require("./DragonEgg")
local indexManager = require("./IndexManager")
local indexV2Manager = require("./IndexV2Manager")
local itemManager = require("./ItemManager")
local lootTableManager = require("./LootTableManager")
local mergeMixin = require("./MergeMixin")
local objectDataStore = require("./ObjectDataStore")
local playerAttributesManager = require("./PlayerAttributesManager")
local playtimeRewardManager = require("./PlaytimeRewardManager")
local plotsManager = require("./PlotsManager")
local rideMixin = require("./RideMixin")
local scatterZoneManager = require("./ScatterZoneManager")
local spinWheelManager = require("./SpinWheelManager")
local dayNightManager = require("./DayNightManager")
local eggSlotManager = require("./EggSlotManager")
local starterOfferManager = require("./StarterOfferManager")
local storageManager = require("./StorageManager")
local tradeManager = require("./TradeManager")
local Validate = require("./Validate")
local weatherEventManager = require("./WeatherEventManager")
local weatherManager = require("./WeatherManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local RarityMath = require("@game/ReplicatedStorage/Shared/RarityMath")

local progressionData = require("@game/ServerScriptService/GameData/Control/Progression")
local rarityData = require("@game/ServerScriptService/GameData/Control/Rarities")
local startData = require("@game/ServerScriptService/GameData/Control/Start")

type DevToolsFields = {}

export type DevTools = typeof(setmetatable({} :: DevToolsFields, DevTools))

function DevTools.dumpServerTradingState(self: DevTools, player: Player)
	tradeManager:dumpState()
end

function DevTools.dumpIndexState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index unlocked items for", player)
	for itemName in playerData:getIndexDiscoveredItems() do
		print(itemName)
	end

	print("Index unlocked mutations for", player)
	for mutation in playerData:getIndexDiscoveredMutations() do
		print(enums.getPublicName(enums.Mutations, mutation))
	end
end

function DevTools.grantIndexStatBuff(self: DevTools, player: Player, attributeName: any, amount: any)
	local playerData = gameController:getPlayerData(player)
	playerData:grantIndexStatBuff(attributeName, amount)
end

function DevTools.dumpIndexStatBuffs(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index stat buffs for", player)
	for attributeName, buffAmount in playerData.indexStatBuffs do
		print(attributeName, "buff", buffAmount, "live value", playerData:getPlayerVariable(attributeName))
	end
end

function DevTools.grantIndexMutationChanceBuff(self: DevTools, player: Player, amount: any)
	local playerData = gameController:getPlayerData(player)
	playerData:grantIndexMutationChanceBuff(amount)
end

function DevTools.dumpIndexMutationChanceBuff(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index mutation chance buff for", player, playerData:getIndexMutationChancePercent())
	print("  time luck", playerData:getTimeLuckPercent())
	print("  friend luck", playerData:getFriendLuckPercent())
	print("  group luck", playerData:getGroupLuckPercent())
	print("  total luck / mutation chance", playerData:getLuckPercent())
end

function DevTools.tryClaimIndexReward(self: DevTools, player: Player, category: any, scope: any, chainKey: any, tierIndex: any)
	gameController:tryClaimIndexReward(player, category, scope, chainKey, tierIndex)
end

function DevTools.notifyIndexDataReset(self: DevTools, player: Player)
	if indexManager:isLegacyEnabled() then
		RemoteEvents.NotifyIndexData:FireClient(player, indexManager:getFullIndexDataForPlayer(player))
	end
	indexV2Manager:sendData(player)
end

function DevTools.resetIndexData(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexData()
	self:notifyIndexDataReset(player)
end

function DevTools.resetIndexRewards(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexRewards()
	self:notifyIndexDataReset(player)
end

function DevTools.resetIndexMutationData(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexMutationData()
	self:notifyIndexDataReset(player)
end

function DevTools.discoverSpecificMutation(self: DevTools, player: Player, mutationTier: any)
	local playerData = gameController:getPlayerData(player)
	indexV2Manager:notifyMutationDiscoveredIfNew(player, playerData, mutationTier)
	print("index discovered specific mutation", player, enums.getPublicName(enums.Mutations, mutationTier))
end

function DevTools.dumpDragonMutations(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	local counts = playerData:getAllDragonMutationCounts()
	local dragonNames = {}
	for dragonName in counts do
		table.insert(dragonNames, dragonName)
	end
	table.sort(dragonNames)

	print("Per-dragon mutations discovered:", #dragonNames, "dragons")
	for _, dragonName in dragonNames do
		local names = {}
		for _, mutation in playerData:getDragonMutations(dragonName) do
			table.insert(names, enums.getPublicName(enums.Mutations, mutation) :: string)
		end
		print(dragonName, counts[dragonName], table.concat(names, ", "))
	end
end

function DevTools.dumpIndexChains(self: DevTools, player: Player, category: any)
	print("Index chains for category", category)
	for chainIndex, chain in indexManager:getCategoryChains(category) do
		print(chainIndex, chain.chainKey, chain.itemNames or chain.abilities or chain.mutationTiers)
	end
end

function DevTools.dumpIndexMilestones(self: DevTools, player: Player, category: any, scope: any, chainKey: any)
	local playerData = gameController:getPlayerData(player)

	print("Index milestones for", category, scope, chainKey)
	for _, milestone in indexManager:getMilestones(playerData, category, scope, chainKey) do
		print(
			"tier", milestone.tierIndex,
			"percent", milestone.displayPercent,
			"threshold", milestone.threshold,
			"claimed", milestone.isClaimed,
			"claimable", milestone.isClaimable,
			"tierId", milestone.tierId
		)
	end
end

function DevTools.sendIndexV2Data(self: DevTools, player: Player)
	indexV2Manager:sendData(player)
end

function DevTools.dumpIndexV2(self: DevTools, player: Player, category: any)
	if not enums.isValidValue(enums.IndexCategory, category) then
		warn("invalid index category", category)
		return
	end

	local playerData = gameController:getPlayerData(player)

	print("Index V2 milestones for", enums.getPublicName(enums.IndexCategory, category))
	for _, milestone in indexV2Manager:buildMilestones(playerData, category) do
		print(
			milestone.tierId,
			"collected", milestone.collected,
			"threshold", milestone.threshold,
			"of", milestone.total,
			"claimed", milestone.isClaimed,
			"claimable", milestone.isClaimable
		)
	end
end

function DevTools.discoverIndexV2Items(self: DevTools, player: Player, category: any, percent: any)
	if not enums.isValidValue(enums.IndexCategory, category) or typeof(percent) ~= "number" then
		warn("invalid index V2 discover arguments", category, percent)
		return
	end

	local playerData = gameController:getPlayerData(player)

	local entries = indexV2Manager:getEntries(category)
	local count = math.ceil(#entries * math.clamp(percent, 0, 100) / 100)
	for i = 1, count do
		local key = entries[i].key
		if category == enums.IndexCategory.MUTATION then
			indexV2Manager:notifyMutationDiscoveredIfNew(player, playerData, key :: number)
		elseif category == enums.IndexCategory.TRAIT then
			indexV2Manager:notifyTraitDiscoveredIfNew(player, playerData, key :: number)
		else
			indexV2Manager:notifyItemDiscoveredIfNew(player, playerData, key :: string)
		end
	end

	print("index V2 discover complete", enums.getPublicName(enums.IndexCategory, category), count, "of", #entries)
end

function DevTools.claimNextIndexV2Tier(self: DevTools, player: Player, category: any)
	if not enums.isValidValue(enums.IndexCategory, category) then
		warn("invalid index category", category)
		return
	end

	local playerData = gameController:getPlayerData(player)
	for _, milestone in indexV2Manager:buildMilestones(playerData, category) do
		if milestone.isClaimable then
			gameController:tryClaimIndexV2Tier(player, milestone.tierId)
			return
		end
	end

	print("no claimable index tier for", enums.getPublicName(enums.IndexCategory, category))
end

function DevTools.discoverIndexItemsForCategory(self: DevTools, player: Player, category: any, percent: any)
	local playerData = gameController:getPlayerData(player)

	local chains = indexManager:getCategoryChains(category)
	if #chains == 0 then
		warn("no discoverable items for index category", category)
		return
	end

	percent = math.clamp(percent, 0, 100)

	local newlyDiscoveredCount = 0
	local discoveredThisRun = 0
	for _, chain in chains do
		if chain.itemNames then
			local chainCount = math.ceil(#chain.itemNames * percent / 100)
			for i = 1, chainCount do
				local itemName = chain.itemNames[i]
				if not playerData:hasDiscoveredIndexItem(itemName) then
					newlyDiscoveredCount += 1
				end
				indexV2Manager:notifyItemDiscoveredIfNew(player, playerData, itemName)
				discoveredThisRun += 1
			end
		elseif chain.mutationTiers then
			local chainCount = math.ceil(#chain.mutationTiers * percent / 100)
			for i = 1, chainCount do
				local mutation = chain.mutationTiers[i]
				if not playerData:hasDiscoveredIndexMutation(mutation) then
					newlyDiscoveredCount += 1
				end
				indexV2Manager:notifyMutationDiscoveredIfNew(player, playerData, mutation)
				discoveredThisRun += 1
			end
		end
	end

	local totalDiscovered = 0
	for _ in playerData:getIndexDiscoveredItems() do
		totalDiscovered += 1
	end

	local totalDiscoveredMutations = 0
	for _ in playerData:getIndexDiscoveredMutations() do
		totalDiscoveredMutations += 1
	end

	print("index discover complete", player, category, percent .. "% per chain", "newly discovered", newlyDiscoveredCount, "of", discoveredThisRun, "total discovered", totalDiscovered, "total discovered mutations", totalDiscoveredMutations)
end

function DevTools.advanceDailyLoginDay(self: DevTools, player: Player)
	dailyLoginManager:advanceDay(player)
end

function DevTools.resetDailyLogin(self: DevTools, player: Player)
	dailyLoginManager:resetPlayer(player)
end

function DevTools.giveFreeSpin(self: DevTools, player: Player)
	spinWheelManager:debugAddSpins(player, 1, 0)
end

function DevTools.givePaidSpin(self: DevTools, player: Player)
	spinWheelManager:debugAddSpins(player, 0, 1)
end

function DevTools.advanceSpinWheelDay(self: DevTools, player: Player)
	spinWheelManager:debugAdvanceDay(player)
end

function DevTools.resetSpinWheel(self: DevTools, player: Player)
	spinWheelManager:resetPlayer(player)
end

function DevTools.resetPlaytimeRewards(self: DevTools, player: Player)
	playtimeRewardManager:resetPlayer(player)
end

function DevTools.fastForwardPlaytime(self: DevTools, player: Player, seconds: any)
	if type(seconds) ~= "number" or seconds < 1 then
		print("invalid playtime seconds to fast forward", seconds)
		return
	end

	playtimeRewardManager:advanceSession(player, math.floor(seconds))
end

function DevTools.resetCoins(self: DevTools, player: Player)
	playerAttributesManager:set(player, PlayerAttributeKeys.COINS, startData.coins)
end

function DevTools.resetDiamonds(self: DevTools, player: Player)
	playerAttributesManager:set(player, PlayerAttributeKeys.DIAMONDS, 0)
end

function DevTools.getCoins(self: DevTools, player: Player, amount: any)
	if not amount or amount < 1 then
		print("invalid coin amount to get", amount)
		return
	end
	amount = math.floor(amount)

	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, amount)
end

function DevTools.getDiamonds(self: DevTools, player: Player, amount: any)
	if type(amount) ~= "number" or amount < 1 then
		print("invalid diamond amount to get", amount)
		return
	end

	CurrencyGranter.grantDiamonds(player, math.floor(amount), "devTool")
end

function DevTools.spendDiamonds(self: DevTools, player: Player, amount: any)
	if type(amount) ~= "number" or amount < 1 then
		print("invalid diamond amount to spend", amount)
		return
	end

	if not CurrencyGranter.trySpendDiamonds(player, math.floor(amount), "devTool") then
		print("not enough diamonds to spend", amount, "have", CurrencyGranter.getDiamonds(player))
	end
end

function DevTools.getGems(self: DevTools, player: Player, amount: any)
	if not amount or amount < 1 then
		print("invalid gem amount to get", amount)
		return
	end
	amount = math.floor(amount)

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end

		local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)

		playerAttributesManager:addWholeNumber(player, gemsKey, amount)
	end

end

function DevTools.dumpCoins(self: DevTools, player: Player)
	print("Coins for", player, playerAttributesManager:get(player, PlayerAttributeKeys.COINS))
end

function DevTools.dumpDiamonds(self: DevTools, player: Player)
	print("Diamonds for", player, CurrencyGranter.getDiamonds(player))
end

function DevTools.dumpGems(self: DevTools, player: Player)
	print("Gems in wallet for", player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)
		print(" ", enums.getPublicName(enums.PrimaryElements, primaryElement), playerAttributesManager:get(player, gemsKey))
	end

	print("Gems on the ground for", player)
	for _, item in itemManager:getItemsOnGroundByUserId(player.UserId) do
		if item:getType() ~= "gem" then
			continue
		end

		local gem = item :: Types.NumberItem
		print(" ", item:getItemName(), "count", gem:getCount())
	end
end

-- prints the featured deals the server will send to clients, and whether each product id is registered for receipts
-- prints each rarity's row and the derived leveling numbers, to compare with the spec's Master Table
function DevTools.dumpRarityTable(self: DevTools, player: Player)
	print("Rarity table (GameData/Control/Rarities)")
	for _, rarity in enums.getAllValues(enums.Rarity) do
		local row = rarityData.rarities[rarity]
		if not row then
			print(" ", enums.getName(enums.Rarity, rarity), "MISSING")
			continue
		end

		local totalXp = 0
		for level = 1, row.levelCap - 1 do
			totalXp += RarityMath.getNextLevelXp(row, level) :: number
		end
		print(
			" ",
			enums.getName(enums.Rarity, rarity),
			"cap", row.levelCap,
			"xp L2", RarityMath.getNextLevelXp(row, 1),
			"xp final", RarityMath.getNextLevelXp(row, row.levelCap - 1),
			"xp total", totalXp, "of", row.xpToCap,
			"baseIncome", row.baseIncome,
			"levelMod@cap", RarityMath.getLevelMod(row, row.levelCap),
			"levelSpeed@cap", RarityMath.getLevelSpeed(row, row.levelCap),
			"scale L1", RarityMath.getModelScale(row, 1, 1),
			"scale cap", RarityMath.getModelScale(row, 1, row.levelCap)
		)
	end
end

function DevTools.setDayNightPhase(self: DevTools, player: Player, phaseName: any)
	if phaseName ~= "day" and phaseName ~= "night" then
		warn("setDayNightPhase needs \"day\" or \"night\"", phaseName)
		return
	end

	dayNightManager:devSetPhase(phaseName == "night")
end

function DevTools.resetDayNight(self: DevTools, player: Player)
	dayNightManager:devReset()
end

function DevTools.restockDealShop(self: DevTools, player: Player)
	dealShopManager:devRestock()
end

function DevTools.dumpFeaturedDeals(self: DevTools, player: Player)
	local config = dealShopManager:getFeaturedConfig()
	if not config then
		print("no featured deals config")
		return
	end

	print("Featured deals: rotationSec", config.rotationSec, "count", #config.deals)
	for _, deal in config.deals do
		local productId = deal.tiers[1].productId
		print(" ", deal.dealKey, "productId", productId, "registered", dealShopManager:isProductId(productId), "startTime", deal.startTime, "endTime", deal.endTime)
	end
end

function DevTools.dumpDragonIncome(self: DevTools, player: Player)
	print("Dragon Income for", player)

	local total = 0

	local allItems = itemManager:getItemsOnGroundByUserId(player.UserId)
	for _, item in itemManager:getItemsNotOnGroundByUserId(player.UserId) do
		table.insert(allItems, item)
	end

	for _, item in allItems do
		if item:getType() ~= "shadowDragon" then
			continue
		end

		local dragon = item :: Types.ShadowDragon
		local itemData = dragon:getItemData()
		local income = dragon:getIncome()
		total += income

		print(
			" ",
			"itemId",
			dragon:getItemId(),
			dragon:getItemName(),
			"rarity",
			enums.getName(enums.Rarity, itemData.rarity),
			"level",
			itemData.level,
			"mutation",
			enums.getName(enums.Mutations, dragon:getMutation()),
			"income",
			income
		)
	end

	print("  total (all owned dragons):", total)
end

function DevTools.forceHatchEgg(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot force-hatch item not owned by this player", itemId, player)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.DragonEgg
	item:forceHatchNow()
end

function DevTools.forceMakeEggReadyToHatch(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot force-ready item not owned by this player", itemId, player)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.DragonEgg
	item:notifyHatchReady()
end

function DevTools.dumpEggLootWeights(self: DevTools, player: Player)
	for _, eggItemName in objectDataStore:getAllObjectNamesByDataKeyValue("type", "dragonEgg") do
		local itemData = objectDataStore:getObjectDataByName(eggItemName)
		local hatchLootTableName = itemData.hatchLootTableName
		if not hatchLootTableName then
			continue
		end

		local rawLootTable = lootTableManager:getLootTable(hatchLootTableName)
		if not rawLootTable or #rawLootTable == 0 then
			continue
		end

		local luckMultiplier = DragonEgg.computeLuckMultiplier(itemData.eggBaseLuck, player.UserId)
		local biasedLootTable = DragonEgg.applyLuckBiasToLootTable(rawLootTable, luckMultiplier)

		local baseTotal = 0
		for _, entry in rawLootTable do
			baseTotal += entry.weight
		end

		local biasedTotal = 0
		for _, entry in biasedLootTable do
			biasedTotal += entry.weight
		end

		print(string.format(
			"egg %s: eggBaseLuck=%s luckMultiplier=%.2f loot table=%s",
			eggItemName,
			tostring(itemData.eggBaseLuck or 1),
			luckMultiplier,
			hatchLootTableName
		))

		for i, entry in rawLootTable do
			local biasedEntry = biasedLootTable[i]
			print(string.format(
				"  %s: base %.2f%% -> biased %.2f%%",
				entry.result.itemName,
				entry.weight / baseTotal * 100,
				biasedEntry.weight / biasedTotal * 100
			))
		end
	end
end

function DevTools.dumpPlotLuck(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	local level = playerData:getPlotLuckLevel()
	local nextCost = gameController:getPlotLuckUpgradeCost(level)

	print(string.format(
		"plot luck for %s: level %d (x%d multiplier), cost to next level: %s",
		player.Name,
		level,
		playerData:getPlotLuckMultiplier(),
		tostring(nextCost)
	))
end

function DevTools.setPlotLuckLevel(self: DevTools, player: Player, level: any)
	gameController:getPlayerData(player):setPlotLuckLevel(level)
end

function DevTools.dumpRebirth(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	local level = playerData:getRebirthLevel()
	local nextLevelData = gameController:getRebirthLevelData(level + 1)
	local coins = playerAttributesManager:get(player, PlayerAttributeKeys.COINS)

	if not nextLevelData then
		print(string.format(
			"rebirth for %s: level %d, coins %d, no more rebirth levels available, egg slots %d",
			player.Name,
			level,
			coins,
			eggSlotManager:getEggSlotCount(player)
		))
		return
	end

	local requiredRarity = nextLevelData.requiredRarity
	local hasRarity = requiredRarity ~= nil and itemManager:hasDragonWithRarity(player, requiredRarity)

	print(string.format(
		"rebirth for %s: level %d, coins %d, cost to rebirth: %d, required rarity: %s, found: %s, bypass coin cost: %s, egg slots %d",
		player.Name,
		level,
		coins,
		nextLevelData.cost,
		tostring(requiredRarity and enums.getPublicName(enums.Rarity, requiredRarity)),
		tostring(hasRarity),
		tostring(nextLevelData.bypassCoinCost),
		eggSlotManager:getEggSlotCount(player)
	))
end

function DevTools.rebirth(self: DevTools, player: Player)
	gameController:tryRebirth(player)
end

function DevTools.tryUpgradePlotLuck(self: DevTools, player: Player, toMax: any)
	gameController:tryUpgradePlotLuck(player, toMax)
end

function DevTools.feedDragon(self: DevTools, player: Player, itemId: any, amount: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot feed item not owned by this player", itemId, player)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.Item
	if item:getType() ~= "shadowDragon" then
		warn("dev tool cannot feed a non-dragon item", itemId, player)
		return
	end

	(item :: Types.ShadowDragon):addDragonXp(amount)
end

function DevTools.dumpDragonLevel(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot dump item not owned by this player", itemId, player)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.Item
	if item:getType() ~= "shadowDragon" then
		warn("dev tool cannot dump a non-dragon item", itemId, player)
		return
	end

	local dragon = item :: Types.ShadowDragon
	local level = dragon:getDragonLevel()
	local nextLevelXp = dragon:getNextLevelXp(level)

	print(string.format(
		"dragon %s level %d xp %.1f/%s income %.2f speed %.3f size percentile %.1f (SizeScale %.3f)",
		tostring(itemId),
		level,
		dragon:getDragonXp(),
		nextLevelXp and string.format("%.1f", nextLevelXp) or "MAX",
		dragon:getIncome(),
		dragon:getSpeed(),
		dragon:getSizePercentile(),
		dragon:getSizeScale()
	))
end

function DevTools.forceExpireCarry(self: DevTools, player: Player, itemId: any)
	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		warn("dev tool cannot force-expire carry timer, player is not riding a dragon", player)
		return
	end

	if dragon:getObj():GetAttribute(Attributes.CARRIED_EGG_ITEM_ID) ~= itemId then
		warn("dev tool cannot force-expire carry timer, item is not being carried by this player's dragon", itemId, player)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.DragonEgg
	item:notifyCarryExpired()
end

function DevTools.forceActivateRadar(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		print("invalid item id by", player, "item id", itemId)
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.Item
	if item:getType() ~= "radar" then
		print("invalid item, non-radar by", player, "item id", itemId)
		return
	end

	local radar = item :: Types.Radar
	radar:notifyToolActivated()
end


function DevTools.dumpScatterZones(self: DevTools, player: Player)
	for _, zone in scatterZoneManager:getAllZones() do
		local rarityNames = {}
		for _, itemId in zone:getSpawnedEggItemIds() do
			local item = itemManager:getItemById(itemId)
			local rarity = item and (item:getObj():GetAttribute(Attributes.RARITY) :: number?)
			table.insert(rarityNames, if rarity then enums.getName(enums.Rarity, rarity) else "unknown")
		end

		print(
			"scatter zone",
			zone:getObjectId(),
			zone:getObjectName(),
			"eggs",
			zone:getCurrentEggCount(),
			"/",
			zone:getMaxEggsInZone(),
			"rarities",
			table.concat(rarityNames, ", ")
		)
	end
end

function DevTools.forceRefillScatterZone(self: DevTools, player: Player, objectId: any)
	local zone = scatterZoneManager:getZoneByObjectId(objectId)
	if not zone then
		print("no scatter zone with object id", objectId)
		return
	end

	zone:topUp()
end

function DevTools.forceTakeOneScatterEgg(self: DevTools, player: Player, objectId: any)
	local zone = scatterZoneManager:getZoneByObjectId(objectId)
	if not zone then
		print("no scatter zone with object id", objectId)
		return
	end

	local itemId = next(zone.spawnedEggItemIds)
	if not itemId then
		print("scatter zone has no eggs to take", objectId)
		return
	end

	local item = itemManager:getItemById(itemId)
	if item then
		itemManager:destroyItem(item)
	end
	zone:notifyEggTaken(itemId)
end

function DevTools.placeAllEggs(self: DevTools, player: Player)
	local allItems = itemManager:getItemsOnGroundByUserId(player.UserId)
	for _, item in itemManager:getItemsNotOnGroundByUserId(player.UserId) do
		table.insert(allItems, item)
	end

	local playerData = gameController:getPlayerData(player)
	local eggSlotIndex = 0
	for _, item in allItems do
		if item:getType() ~= "dragonEgg" or (item :: Types.DragonEgg):getEggSlotIndex() ~= nil then
			continue
		end

		repeat
			eggSlotIndex += 1
		until playerData:getEggInSlot(eggSlotIndex) == nil or eggSlotIndex > eggSlotManager:getEggSlotCount(player)
		if eggSlotIndex > eggSlotManager:getEggSlotCount(player) then
			break
		end

		if eggSlotManager:tryPlaceEgg(player, item:getItemId(), eggSlotIndex) then
			print("  placed", item:getItemName(), "in egg slot", eggSlotIndex)
		else
			print("  failed to place", item:getItemName(), "in egg slot", eggSlotIndex)
		end
	end
end

function DevTools.removeAllEggs(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	local eggSlotIndices = {}
	for eggSlotIndex in playerData:getEggSlots() do
		table.insert(eggSlotIndices, eggSlotIndex)
	end

	for _, eggSlotIndex in eggSlotIndices do
		eggSlotManager:tryRemoveEgg(player, eggSlotIndex)
	end
end

function DevTools.resetPrimaryElementProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local xp = 0
		local playerAttributeKeyXp = Elements.getXpKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerAttributeKeyXp, xp)

		local level = 1
		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerAttributeKeyLevel, level)

		local playerDataKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerDataKeyIsUnlocked, primaryElement == enums.PrimaryElements.NATURE)

		local playerDataKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerDataKeyGems, 0)
	end

	playerData:updateLevelsVisuals()

	playerData:trySetOption(PlayerOptionKeys.MERGE_ALL_ENABLED, false)
	RemoteEvents.NotifySetOptions:FireClient(player,
		{
			[PlayerOptionKeys.MERGE_ALL_ENABLED] = playerData:getOption(PlayerOptionKeys.MERGE_ALL_ENABLED),
		}
	)
	playerData:updatePlayerFeaturesInGuiData()

	playerData:resetAbilityStatuses()
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())

	playerData:updatePlayerVariables()
end

function DevTools.resetPurchasedSlotUnlocks(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetPurchasedSlotUnlocks()
end

function DevTools.addXp(self: DevTools, player: Player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end
		local xpDiff = 500
		gameController:addPrimaryElementXpToPlayer(player, primaryElement, xpDiff, (player.Character :: any).HumanoidRootPart)
	end
end

function DevTools.addLevel(self: DevTools, player: Player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end

		local playerAttributeKeyXp = Elements.getXpKeyForPrimaryElement(primaryElement)
		local xp = playerAttributesManager:get(player, playerAttributeKeyXp)

		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		local level = playerAttributesManager:get(player, playerAttributeKeyLevel)

		local isMaxLevel = (progressionData.nextLevelXp[level] == nil)
		if isMaxLevel then
			continue
		end

		local nextLevelXp = progressionData.nextLevelXp[level]
		local xpDiff = math.max(0, nextLevelXp - xp)

		gameController:addPrimaryElementXpToPlayer(player, primaryElement, xpDiff, (player.Character :: any).HumanoidRootPart)
	end
end

function DevTools.resetAllItems(self: DevTools, player: Player)
	itemManager:removeAllItemsForPlayer(player)
end

function DevTools.eraseSaveData(self: DevTools, player: Player)
	local slot = 0
	storageManager:erasePlayerGame(player, slot)
end

function DevTools.setIfSaveOnExit(self: DevTools, player: Player, doSaveOnExit: any)
	local playerData = gameController:getPlayerData(player)
	playerData:setIfSaveOnExit(doSaveOnExit)
end

function DevTools.loadSaveData(self: DevTools, player: Player, slot: any)
	self:resetCoins(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	local playerData = gameController:getPlayerData(player)


	local success, saveData = storageManager:loadPlayerGame(player, slot)
	if not success then
		playerData:setIfSaveOnExit(false)
		gameController:sendSystemMessageToPlayer(player, "Unsuccessful loading save state")
		return
	end

	print("loaded save data:", saveData)

	playerData:loadSaveData(saveData)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())
end

function DevTools.saveData(self: DevTools, player: Player, slot: any)
	local playerData = gameController:getPlayerData(player)

	local saveData = playerData:getSaveData()

	print("saving player to slot", slot)
	storageManager:savePlayerGame(player, saveData, slot)
end

function DevTools.loadSaveDataGlobal(self: DevTools, player: Player, globalName: any)
	self:resetCoins(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	local playerData = gameController:getPlayerData(player)

	local success, saveData = storageManager:loadPlayerGameGlobal(player, globalName)
	if not success then
		gameController:sendSystemMessageToPlayer(player, "Unsuccessful loading save state")
		playerData:setIfSaveOnExit(false)
		return
	end

	print("loaded save data:", saveData)

	playerData:loadSaveData(saveData)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())

end

function DevTools.saveDataGlobal(self: DevTools, player: Player, globalName: any)
	local playerData = gameController:getPlayerData(player)

	local saveData = playerData:getSaveData()

	print("saving player to global name", globalName)
	storageManager:savePlayerGameGlobal(player, saveData, globalName)
end

function DevTools.addGemPile(self: DevTools, player: Player)
	local plotIndex = plotsManager:getPlotIndexByUserId(player.UserId) :: number

	local random = Random.new()
	for i = 1, 10 do
		local rawPlotPosition = Vector3.new(-10 + random:NextNumber(-3, 3), 0, -50 + random:NextNumber(-3, 3))
		local groundPosition = plotsManager:getGroundPositionFromPlotPosition(rawPlotPosition, plotIndex)
		local position = groundPosition + Vector3.new(0, i, 0)
		local item = itemManager:createItem("Green Gem", player.UserId)
		if not item then
			continue
		end
		local obj = item:getObj()
		obj.Position = position
		obj.Parent = workspace
	end
end

function DevTools.createItem(self: DevTools, player: Player, itemName: any)
	local playerData = gameController:getPlayerData(player)

	local item = itemManager:createItem(itemName, player.UserId)
	if not item then
		warn("unable to create item", itemName)
		return
	end

	local itemData = item:getItemData()
	if itemData.mixins.pickup then
		item:equip()
	else
		local position = (player.Character :: any).HumanoidRootPart.Position
		position += Vector3.new(0, 10, 0)

		item:getObj():PivotTo(CFrame.new(position))
		item:getObj().Parent = workspace

		if item.type == "shadowDragon" then
			-- have it pick a good height and go there
			local dragon = item :: Types.ShadowDragon
			dragon:notifyShouldMoveToIdleAtCurrentLocation()
		end
	end


	playerData:notifyItemReceived(item)

	analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
		{
			objectName = item:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
			rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
			itemType = item:getType(),
			acquisitionSource = "devTool",
		}
	)
end

function DevTools.createItemCount(self: DevTools, player: Player, itemName: any, count: any)
	count = math.clamp(count, 1, 1000)
	for i = 1, count do
		self:createItem(player, itemName)
	end
end

function DevTools.setVanityComponentNameAtPlacement(self: DevTools, player: Player, vanityPlacement: any, vanityComponentName: any)
	local playerData = gameController:getPlayerData(player)
	playerData:equipVanityComponentAtPlacement(vanityPlacement, vanityComponentName)
end

function DevTools.resetAllVanity(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetAllVanity()
end

function DevTools.restockBuyStoreRandom(self: DevTools, player: Player)
	buyStoreManager:restockRandom()
end

function DevTools.resetVanityDiscount(self: DevTools, player: Player)
	vanityStoreManager:resetDiscountForPlayer(player)
end

function DevTools.resetStarterOfferProgress(self: DevTools, player: Player)
	starterOfferManager:resetStarterOfferProgressForPlayer(player)
end

function DevTools.refillNodes(self: DevTools, player: Player)
	gameController:refillNodes()
end

function DevTools.restockIslands(self: DevTools, player: Player)
	gameController:restockIslands()
end

function DevTools.restockFixedIslands(self: DevTools, player: Player, islandName: any)
	gameController:restockFixedIslands(islandName)
end

function DevTools.setMutation(self: DevTools, player: Player, itemId: any, mutation: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot mutate item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item

	if not enums.isValidValue(enums.Mutations, mutation) then
		warn("invalid mutation, ignoring", mutation)
		return
	end

	if not itemManager:isMutationCapableType(item:getType()) then
		print("cannot set mutation of a non-mutatemod item", item)
		return
	end

	local mitem = item :: Types.MItem
	mitem:setMutation(mutation)
end

function DevTools.toggleModification(self: DevTools, player: Player, itemId: any, modification: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot modify item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item
	if not enums.isValidValue(enums.Modifications, modification) then
		warn("invalid modification, ignoring", modification)
		return
	end

	if not itemManager:isMutationCapableType(item:getType()) then
		print("cannot set modification of a non-mutatemod item", item)
		return
	end

	local mitem = item :: Types.MItem
	mitem:toggleModification(modification)
end

function DevTools.activateCrystal(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	local itemId = playerData:tryGetBestInstantOpenCrystalItemId(math.huge)
	if not itemId then
		print("no crystals to instant open")
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.Crystal?
	if item then
		item:finishOpeningSuccessfully()
	end
end

function DevTools.resetFullPlayerState(self: DevTools, player: Player)
	self:resetCoins(player)
	self:resetDiamonds(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetStarterOfferProgress(player)
	-- intro FTUE is bypassed for now (old egg flow); restore restartFtueProgress here once it's rewritten
	-- self:restartFtueProgress(player)
	self:resetFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	self:resetCodesRedeemed(player)
	self:resetContextualFtueState(player)
	self:resetIndexData(player)
	self:resetDailyLogin(player)
	self:resetSpinWheel(player)

	local playerData = gameController:getPlayerData(player)
	playerData:resetStats()
	playerData:resetLuckBillboard()
	playerData:setRebirthLevel(0)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
end

function DevTools.resetCodesRedeemed(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetCodesRedeemed()
end

function DevTools.destroyItem(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot destroy item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item

	local itemName = item:getItemName()
	local itemType = item:getType()
	local primaryElement = item:getItemData().primaryElement
	local rarity = item:getItemData().rarity

	itemManager:destroyItem(item)

	analyticsManager:logEvent(player, analyticsManager.Events.LoseItem,
		{
			objectName = itemName,
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
			rarity = enums.getPublicName(enums.Rarity, rarity),
			itemType = itemType,
			lossSource = "devTool",
		}
	)
end

function DevTools.addStamina(self: DevTools, player: Player)
	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if dragon then
		dragon:setOverrideMaxStamina(5000)
	end
end

function DevTools.setupStandardMerge(self: DevTools, player: Player, itemId: any)
	local item = itemManager:getItemById(itemId)

	local isEnhanced = false
	mergeMixin:createItemsToMergeWithItem(player, item, isEnhanced)
end

function DevTools.setupEnhancedMerge(self: DevTools, player: Player, itemId: any)
	local item = itemManager:getItemById(itemId)

	local isEnhanced = true
	mergeMixin:createItemsToMergeWithItem(player, item, isEnhanced)
end

function DevTools.fullyGrowCrops(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:growAllCrops()
end

function DevTools.goToIsland(self: DevTools, player: Player)
	local socialNode = gameController:getClosestNodeToPlayer(player)
	if not socialNode then
		return
	end

	local socialNodePosition = socialNode:getObj():GetPivot().Position
	local position = socialNodePosition + Vector3.new(0, 5, 0)

	local ridingDragon = if rideMixin:isPlayerRiding(player) then rideMixin:tryGetRidingDragonForPlayer(player) else nil
	if ridingDragon then
		ridingDragon:getObj():PivotTo(CFrame.new(position))
	else
		(player.Character :: any).HumanoidRootPart:PivotTo(CFrame.new(position))
	end
end

function DevTools.setEatFast(self: DevTools, player: Player, doEatFast: any)
	local playerData = gameController:getPlayerData(player)

	playerData:setDevToolSetting("eatFast", doEatFast)
end

function DevTools.dumpIslandEggs(self: DevTools, player: Player)
	local zones = scatterZoneManager:getAllZones()
	local islandZones, islandCap, islandEggs, otherZones, otherEggs = 0, 0, 0, 0, 0
	for _, zone in zones do
		if zone.isIslandZone then
			islandZones += 1
			islandCap += zone:getMaxEggsInZone()
			islandEggs += zone:getCurrentEggCount()
		else
			otherZones += 1
			otherEggs += zone:getCurrentEggCount()
		end
	end

	print(
		"Island egg zones: target", scatterZoneManager:getTargetTotalEggs(),
		"| island zones", islandZones, "with cap", islandCap, "and eggs on the ground", islandEggs,
		"| other zones", otherZones, "with eggs", otherEggs
	)
end

function DevTools.dumpPlotBounds(self: DevTools, player: Player)
	local bounds = plotsManager:getMainPlotBounds()
	print("Main plot bounds in plot space: x", bounds.minX, bounds.maxX, "z", bounds.minZ, bounds.maxZ)
	for plotIndex = 1, plotsManager:getNumPlots() do
		local originCFrame = PlotHelpers.getPlotCFrame(plotIndex)
		if not originCFrame then
			continue
		end

		local _, yaw = originCFrame:ToOrientation()
		local corners = {}
		for _, plotCorner in {
			Vector3.new(bounds.minX, 0, bounds.minZ),
			Vector3.new(bounds.maxX, 0, bounds.minZ),
			Vector3.new(bounds.maxX, 0, bounds.maxZ),
			Vector3.new(bounds.minX, 0, bounds.maxZ),
		} do
			local world = plotsManager:translatePositionPlotToWorld(plotCorner, plotIndex)
			table.insert(corners, string.format("(%.1f, %.1f)", world.X, world.Z))
		end

		local center = plotsManager:translatePositionPlotToWorld(
			Vector3.new((bounds.minX + bounds.maxX) / 2, 0, (bounds.minZ + bounds.maxZ) / 2),
			plotIndex
		)
		print(
			"plot", plotIndex,
			"origin", originCFrame.Position, "yaw", math.round(math.deg(yaw)),
			"corners", table.concat(corners, " "),
			"center inside", plotsManager:isPositionInMainPlotXZ(center, plotIndex),
			"origin inside", plotsManager:isPositionInMainPlotXZ(originCFrame.Position, plotIndex)
		)
	end
end

function DevTools.goToPlot(self: DevTools, player: Player, plotIndex: any)
	-- a missing character or unknown plot crashed here before typing too
	(player.Character :: Model):PivotTo((PlotHelpers.getPlotCFrame(plotIndex) :: CFrame) + Vector3.new(0, 5, 0))
end

function DevTools.setUseBillboards(self: DevTools, player: Player, doUseBillboards: any)
	itemManager:setUseBillboards(doUseBillboards)
end

function DevTools.startWeatherEvent(self: DevTools, player: Player, weather: any)
	if not enums.validateValue(enums.Weather, weather) then
		warn("startWeatherEvent needs an Enums.Weather value", weather)
		return
	end

	weatherEventManager:devStart(weather)
end

function DevTools.endWeatherEvent(self: DevTools, player: Player)
	weatherEventManager:devEnd()
end

function DevTools.strikeMyDragon(self: DevTools, player: Player)
	weatherEventManager:devStrikeOwn(player)
end

function DevTools.dropCosmicEgg(self: DevTools, player: Player)
	weatherEventManager:devDropCosmicEgg()
end

function DevTools.activateWeather(self: DevTools, player: Player, weatherName: any)
	if not weatherManager:isLegacyActive() then
		warn("legacy weather is switched off (Control/Weather.useLegacyWeather); use startWeatherEvent")
		return
	end

	weatherManager:beginWeatherName(weatherName, 60)
	weatherManager:sendWeatherAllPlayers()
end

function DevTools.deactivateWeather(self: DevTools, player: Player, weatherName: any)
	if not weatherManager:isLegacyActive() then
		warn("legacy weather is switched off (Control/Weather.useLegacyWeather); use endWeatherEvent")
		return
	end

	weatherManager:endWeatherName(weatherName)
	weatherManager:sendWeatherAllPlayers()
end

function DevTools.unlockPrimaryElement(self: DevTools, player: Player, primaryElement: any)
	local playerData = gameController:getPlayerData(player)

	playerData:unlockPrimaryElementIfNeeded(primaryElement)
end

function DevTools.lockPrimaryElement(self: DevTools, player: Player, primaryElement: any)
	local playerData = gameController:getPlayerData(player)

	local playerDataKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
	playerAttributesManager:set(player, playerDataKeyIsUnlocked, false)

	playerData:updateLevelsVisuals()
end

function DevTools.resetFtueProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetFtueProgress()

	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
end

function DevTools.restartFtueProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:restartFtueProgress()

	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
end

function DevTools.triggerContextualFtue(self: DevTools, player: Player, hintId: any)
	contextualFtueManager:tryTrigger(player, hintId)
end

function DevTools.resetContextualFtueState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetContextualFtueState()
end

function DevTools.resetFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetFirstSessionOfferState()

	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())
end

function DevTools.restartFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:restartFirstSessionOfferState()
end

function DevTools.setRedeemableFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:setRedeemableFirstSessionOfferState()
end


function DevTools.getRemoteEventMetrics(self: DevTools, player: Player)
	local remoteEventMetrics = gameController:getRemoteEventMetrics()

	RemoteEvents.NotifyRemoteEventMetrics:FireClient(player, remoteEventMetrics)
end

function DevTools.setShowVanityGnome(self: DevTools, player: Player, doShow: any)
	local playerData = gameController:getPlayerData(player)

	playerData:setDevToolSetting("showVanityGnome", doShow == true)
	playerData:updateVanityStateVisuals()
end

function DevTools.setPlayerVanityState(self: DevTools, player: Player, playerVanityState: any)
	if not enums.validateValue(enums.PlayerVanityState, playerVanityState) then
		print("invalid player vanity state", player, playerVanityState)
		return
	end

	local playerData = gameController:getPlayerData(player)

	playerData:setVanityState(playerVanityState)

end

function DevTools.resetPromptGroupTime(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetPromptGroupTime()
end

function DevTools.new(): DevTools
	local self: DevTools = setmetatable({} :: DevToolsFields, DevTools)

	return self
end

function DevTools.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = DevTools.new()

return singleton
