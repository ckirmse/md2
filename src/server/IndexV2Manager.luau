--!strict

local IndexV2Manager = {}
IndexV2Manager.__index = IndexV2Manager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")
local IndexRewardMath = require("@game/ReplicatedStorage/Shared/IndexRewardMath")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
-- GameData tables are authored in Studio and stay untyped; the accessors below cast to the entry types
local indexRewardsData: any = require("@game/ServerScriptService/GameData/Control/IndexRewards")

local analyticsManager = require("./AnalyticsManager")
local objectDataStore = require("./ObjectDataStore")
local playerAttributesManager = require("./PlayerAttributesManager")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local indexManager: Types.IndexManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

export type Reward = {
	rewardType: string,
	bonusPercent: number?,
	lootTableName: string?,
	count: number?,
	size: string?,
	attribute: string?,
	amount: number?,
	icon: string?,
}

export type RewardEntry = {
	displayText: string,
	reward: Reward,
}

export type TierEntry = {
	requiredPercent: number,
	displayText: string,
	reward: Reward,
}

type IndexEntry = {
	key: string | number,
	displayName: string,
	group: number,
}

type IndexV2ManagerFields = {
	entriesByCategory: { [number]: { IndexEntry } },
}

export type IndexV2Manager = typeof(setmetatable({} :: IndexV2ManagerFields, IndexV2Manager))

local RewardTypeNames = {
	["Income Bonus"] = indexHelpers.RewardType.INCOME_BONUS,
	["Chamber Pull"] = indexHelpers.RewardType.MUTATION_PULL,
	["Chest Pull"] = indexHelpers.RewardType.VANITY_PULL,
	["Stat Buff"] = indexHelpers.RewardType.STAT_BUFF,
	["Mutation Chance"] = indexHelpers.RewardType.MUTATION_CHANCE_BUFF,
} :: { [string]: string }

local CategoryItemTypes: { [number]: string } = {
	[enums.IndexCategory.DRAGON] = "shadowDragon",
	[enums.IndexCategory.EGG] = "dragonEgg",
}

local ItemTypeToCategory: { [string]: number } = {}
for category, itemType in CategoryItemTypes do
	ItemTypeToCategory[itemType] = category
end

-- only categories grouped by rarity have row rewards
local ROW_CATEGORIES: { [number]: boolean } = {
	[enums.IndexCategory.DRAGON] = true,
	[enums.IndexCategory.EGG] = true,
}

local MUTATION_DISPLAY_ORDER: { number } = {
	enums.Mutations.BRONZE,
	enums.Mutations.SILVER,
	enums.Mutations.GOLD,
	enums.Mutations.VERDANT,
	enums.Mutations.AZURE,
	enums.Mutations.CRIMSON,
	enums.Mutations.RAINBOW,
	enums.Mutations.CELESTIAL,
}

local TRAIT_DISPLAY_ORDER: { number } = {
	enums.Trait.SCORCHED,
	enums.Trait.BLOSSOMED,
	enums.Trait.SOAKED,
	enums.Trait.WINDSWEPT,
	enums.Trait.CHARGED,
	enums.Trait.STARLIT,
}

local function getRowRewardEntry(category: number, rarity: number): RewardEntry?
	local categoryRows = indexRewardsData.rowRewards and indexRewardsData.rowRewards[category]
	return categoryRows and categoryRows[rarity]
end

local function getRowRarities(category: number): { number }
	local rarities: { number } = {}
	if not ROW_CATEGORIES[category] then
		return rarities
	end

	for _, rarity in enums.getAllValues(enums.Rarity) do
		if getRowRewardEntry(category, rarity) then
			table.insert(rarities, rarity)
		end
	end

	return rarities
end

local function getCategoryTiers(category: number): { TierEntry }
	local categoryTiers = indexRewardsData.categoryTiers and indexRewardsData.categoryTiers[category]
	return (categoryTiers or {}) :: { TierEntry }
end

local function getEntryCoins(category: number, key: string | number): (number, string?)
	local entryRewards = indexRewardsData.entryRewards
	if not entryRewards or entryRewards.isEnabled ~= true then
		return 0, nil
	end

	local categoryCoins = entryRewards.coins and entryRewards.coins[category]
	if type(categoryCoins) == "number" then
		return categoryCoins, nil
	end
	if type(categoryCoins) ~= "table" or not ROW_CATEGORIES[category] then
		return 0, "no coins authored for the category"
	end

	local itemData = objectDataStore:getObjectDataByName(key :: string)
	local rarity = if itemData then itemData.rarity else nil
	local coins = categoryCoins[rarity]
	if not coins then
		return 0, `no coins authored for rarity {enums.getPublicName(enums.Rarity, rarity) or tostring(rarity)}`
	end

	return coins, nil
end

function IndexV2Manager.getCategoryForItemName(self: IndexV2Manager, itemName: string): number?
	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		return nil
	end

	return ItemTypeToCategory[itemData.type]
end

-- entries are built on first use, so items added at runtime appear only after a server restart
function IndexV2Manager.getEntries(self: IndexV2Manager, category: number): { IndexEntry }
	local cached = self.entriesByCategory[category]
	if cached then
		return cached
	end

	local entries: { IndexEntry } = {}
	local elementSortIndexByName: { [string]: number } = {}

	local itemType = CategoryItemTypes[category]
	if itemType then
		for _, itemName in objectDataStore:getAllObjectNamesByDataKeyValue("type", itemType) do
			local itemData = objectDataStore:getObjectDataByName(itemName)
			table.insert(entries, {
				key = itemName,
				displayName = itemData.displayName or itemName,
				group = itemData.rarity or enums.Rarity.COMMON,
			})
			elementSortIndexByName[itemName] = elements.getSortIndexForPrimaryElement(itemData.primaryElement)
		end

		table.sort(entries, function(a: IndexEntry, b: IndexEntry)
			if a.group ~= b.group then
				return a.group < b.group
			end

			local sortIndexA = elementSortIndexByName[a.key :: string]
			local sortIndexB = elementSortIndexByName[b.key :: string]
			if sortIndexA ~= sortIndexB then
				return sortIndexA < sortIndexB
			end

			return a.displayName < b.displayName
		end)
	elseif category == enums.IndexCategory.TRAIT then
		for _, trait in TRAIT_DISPLAY_ORDER do
			table.insert(entries, {
				key = trait,
				displayName = enums.getPublicName(enums.Trait, trait) :: string,
				group = IndexRewardMath.SINGLE_GROUP,
			})
		end
	elseif category == enums.IndexCategory.MUTATION then
		for _, mutation in MUTATION_DISPLAY_ORDER do
			table.insert(entries, {
				key = mutation,
				displayName = enums.getPublicName(enums.Mutations, mutation) :: string,
				group = IndexRewardMath.SINGLE_GROUP,
			})
		end
	end

	self.entriesByCategory[category] = entries
	return entries
end

function IndexV2Manager.isDiscovered(self: IndexV2Manager, playerData: Types.PlayerData, category: number, key: string | number): boolean
	if category == enums.IndexCategory.MUTATION then
		return playerData:hasDiscoveredIndexMutation(key)
	end

	if category == enums.IndexCategory.TRAIT then
		return playerData:hasDiscoveredIndexTrait(key)
	end

	return playerData:hasDiscoveredIndexItem(key)
end

function IndexV2Manager.buildMilestones(self: IndexV2Manager, playerData: Types.PlayerData, category: number): { IndexRewardMath.Milestone }
	local collectedByGroup: { [number]: number } = {}
	local totalByGroup: { [number]: number } = {}
	for _, entry in self:getEntries(category) do
		totalByGroup[entry.group] = (totalByGroup[entry.group] or 0) + 1
		if self:isDiscovered(playerData, category, entry.key) then
			collectedByGroup[entry.group] = (collectedByGroup[entry.group] or 0) + 1
		end
	end

	local tierPercents: { number } = {}
	for _, tier in getCategoryTiers(category) do
		table.insert(tierPercents, tier.requiredPercent)
	end

	return IndexRewardMath.buildMilestones(
		category,
		getRowRarities(category),
		tierPercents,
		collectedByGroup,
		totalByGroup,
		playerData:getIndexClaimedRewards()
	)
end

function IndexV2Manager.findMilestone(self: IndexV2Manager, playerData: Types.PlayerData, tierId: string): (IndexRewardMath.Milestone?, number?)
	for _, category in enums.getAllValues(enums.IndexCategory) do
		local milestone = IndexRewardMath.findMilestone(self:buildMilestones(playerData, category), tierId)
		if milestone then
			return milestone, category
		end
	end

	return nil, nil
end

function IndexV2Manager.getRewardEntry(self: IndexV2Manager, category: number, milestone: IndexRewardMath.Milestone): RewardEntry?
	if milestone.kind == IndexRewardMath.Kind.ROW then
		return getRowRewardEntry(category, milestone.rarity :: number)
	end

	return getCategoryTiers(category)[milestone.tierIndex :: number]
end

function IndexV2Manager.grantReward(self: IndexV2Manager, player: Player, playerData: Types.PlayerData, rewardEntry: RewardEntry)
	local reward = rewardEntry.reward
	local rewardType = RewardTypeNames[reward.rewardType]

	if rewardType == indexHelpers.RewardType.INCOME_BONUS then
		playerData:addIndexIncomeBonusPercent(reward.bonusPercent or 0)
	elseif rewardType == indexHelpers.RewardType.MUTATION_PULL or rewardType == indexHelpers.RewardType.VANITY_PULL then
		local crateItemName = indexHelpers.getIndexRewardCrateItemName(reward.size)
		local crateItems: { Types.Crate } = {}
		for _ = 1, reward.count or 1 do
			local crateItem = itemManager:createItem(crateItemName, player.UserId) :: Types.Crate?
			if not crateItem then
				warn("failed to create index reward crate")
				continue
			end
			crateItem:setRewardSource(rewardType, reward.lootTableName, rewardEntry.displayText)
			table.insert(crateItems, crateItem)
		end
		gameController:spawnItemsInBackpack(crateItems)
		for _, item in crateItems do
			playerData:notifyItemReceived(item)
		end
	elseif rewardType == indexHelpers.RewardType.STAT_BUFF then
		playerData:grantIndexStatBuff(reward.attribute, reward.amount)
	elseif rewardType == indexHelpers.RewardType.MUTATION_CHANCE_BUFF then
		playerData:grantIndexMutationChanceBuff(reward.amount)
	else
		warn("unknown index reward type", player, reward.rewardType)
	end
end

function IndexV2Manager.tryClaimTier(self: IndexV2Manager, player: Player, tierId: any): ()
	if not gameController:isIndexEnabled() then
		return
	end

	if typeof(tierId) ~= "string" or #tierId > 64 then
		print("invalid index tier id from player", player, tierId)
		return
	end

	local playerData = gameController:getPlayerData(player)
	local milestone, category = self:findMilestone(playerData, tierId)
	if not milestone or not category then
		warn("unknown index tier claim attempt", player, tierId)
		return
	end

	local rewardEntry = self:getRewardEntry(category, milestone)
	if not milestone.isClaimable or not rewardEntry then
		RemoteEvents.NotifyIndexV2TierResult:FireClient(player, tierId, false, playerData:getIndexIncomeBonusPercent())
		return
	end

	playerData:markIndexRewardClaimed(tierId)
	self:grantReward(player, playerData, rewardEntry)

	gameController:sendSystemMessageToPlayer(player, "Claimed reward: " .. rewardEntry.displayText)

	RemoteEvents.NotifyIndexV2TierResult:FireClient(player, tierId, true, playerData:getIndexIncomeBonusPercent())
end

function IndexV2Manager.notifyDiscovered(self: IndexV2Manager, player: Player, category: number, key: string | number): ()
	RemoteEvents.NotifyIndexV2Discovery:FireClient(player, category, key)

	local coins, reason = getEntryCoins(category, key)
	if reason then
		warn("IndexV2Manager: entry prize pays nothing,", reason, enums.getPublicName(enums.IndexCategory, category), key)
	end
	if coins > 0 then
		playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, coins)
		analyticsManager:logGainCurrency(player, coins, playerAttributesManager:get(player, PlayerAttributeKeys.COINS), "indexEntry")
		gameController:sendSystemMessageToPlayer(player, `Index: +{coins} coins`)
	end
end

-- the entry points for every discovery: they record it once and tell the V2 client, then the old Index if it is on
function IndexV2Manager.notifyMutationDiscoveredIfNew(self: IndexV2Manager, player: Player, playerData: any, mutationTier: number)
	if not gameController:isIndexEnabled() then
		return
	end

	if playerData:hasDiscoveredIndexMutation(mutationTier) then
		return
	end

	playerData:markIndexMutationDiscovered(mutationTier)
	self:notifyDiscovered(player, enums.IndexCategory.MUTATION, mutationTier)
	indexManager:notifyMutationDiscovered(player, playerData, mutationTier)
end

function IndexV2Manager.notifyTraitDiscoveredIfNew(self: IndexV2Manager, player: Player, playerData: any, trait: number)
	if not gameController:isIndexEnabled() then
		return
	end

	if playerData:hasDiscoveredIndexTrait(trait) then
		return
	end

	playerData:markIndexTraitDiscovered(trait)
	self:notifyDiscovered(player, enums.IndexCategory.TRAIT, trait)
end

function IndexV2Manager.notifyItemDiscoveredIfNew(self: IndexV2Manager, player: Player, playerData: any, itemName: string)
	if not gameController:isIndexEnabled() then
		return
	end

	if playerData:hasDiscoveredIndexItem(itemName) then
		return
	end

	playerData:markIndexItemDiscovered(itemName)

	local indexCategory = self:getCategoryForItemName(itemName)
	if indexCategory then
		self:notifyDiscovered(player, indexCategory, itemName)
	end

	indexManager:notifyItemDiscovered(player, playerData, itemName)
end

-- everything the client needs to draw the index: the static entry lists and reward texts, plus the player's state.
-- Remote tables are arrays of records so no numeric keys have to survive the trip.
function IndexV2Manager.getData(self: IndexV2Manager, playerData: Types.PlayerData): any
	local categories: { any } = {}
	local discovered: { any } = {}

	for _, category in enums.getAllValues(enums.IndexCategory) do
		local entries: { any } = {}
		local discoveredKeys: { any } = {}
		for _, entry in self:getEntries(category) do
			table.insert(entries, { key = entry.key, displayName = entry.displayName, group = entry.group })
			if self:isDiscovered(playerData, category, entry.key) then
				table.insert(discoveredKeys, entry.key)
			end
		end

		local rowRewards: { any } = {}
		for _, rarity in getRowRarities(category) do
			local rowEntry = getRowRewardEntry(category, rarity) :: RewardEntry
			table.insert(rowRewards, { rarity = rarity, displayText = rowEntry.displayText, icon = rowEntry.reward.icon })
		end

		local tiers: { any } = {}
		for _, tier in getCategoryTiers(category) do
			table.insert(tiers, { requiredPercent = tier.requiredPercent, displayText = tier.displayText, icon = tier.reward.icon })
		end

		table.insert(categories, {
			category = category,
			name = enums.getPublicName(enums.IndexCategory, category),
			entries = entries,
			rowRewards = rowRewards,
			tiers = tiers,
		})
		table.insert(discovered, { category = category, keys = discoveredKeys })
	end

	local claimed: { string } = {}
	for tierId in playerData:getIndexClaimedRewards() do
		table.insert(claimed, tierId)
	end

	return {
		categories = categories,
		discovered = discovered,
		claimed = claimed,
		incomeBonusPercent = playerData:getIndexIncomeBonusPercent(),
		isSingleTierBar = indexRewardsData.singleTierBar == true,
	}
end

function IndexV2Manager.sendData(self: IndexV2Manager, player: Player): ()
	if not gameController:isIndexEnabled() then
		return
	end

	RemoteEvents.NotifyIndexV2Data:FireClient(player, self:getData(gameController:getPlayerData(player)))
end

function IndexV2Manager.new(): IndexV2Manager
	local self: IndexV2Manager = setmetatable({} :: IndexV2ManagerFields, IndexV2Manager)

	self.entriesByCategory = {}

	return self
end

function IndexV2Manager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
	indexManager = deps.indexManager
end

local singleton = IndexV2Manager.new()

return singleton
