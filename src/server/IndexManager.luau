--!strict

local IndexManager = {}
IndexManager.__index = IndexManager

local abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local indexCatalog = require("@game/ReplicatedStorage/Shared/IndexCatalog")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")

local indexRewards = require("./IndexRewards")
local objectDataStore = require("./ObjectDataStore")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local plotsManager = require("./PlotsManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

type IndexManagerFields = {
	categoryChainsCache: { [string]: { any } }?,
}

export type IndexManager = typeof(setmetatable({} :: IndexManagerFields, IndexManager))

local CategoryItemTypes: { [string]: { string } } = {
	[indexCatalog.Category.DRAGONS] = { "dragonEgg", "shadowDragon" },
	[indexCatalog.Category.PLANTS] = { "crop" },
	[indexCatalog.Category.CRYSTALS] = { "crystal" },
	[indexCatalog.Category.BLUEPRINTS] = { "blueprint" },
}

local ItemTypeToCategory: { [string]: string } = {}
for category, itemTypes in CategoryItemTypes do
	for _, itemType in itemTypes do
		ItemTypeToCategory[itemType] = category
	end
end

local BLUEPRINT_SECTION_ORDER: { number } = {
	enums.VanitySection.MAIN_INNER,
	enums.VanitySection.MAIN_OUTER,
	enums.VanitySection.MAIN_FENCE,
	enums.VanitySection.EXPANSION_INNER,
	enums.VanitySection.EXPANSION_OUTER,
}

function IndexManager.buildElementRarityChains(self: IndexManager, itemTypes: { string }): { any }
	local chainsByKey: { [string]: any } = {}
	local itemLevelByName: { [string]: number } = {}

	for _, itemType in itemTypes do
		local itemNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", itemType)

		for _, itemName in itemNames do
			local itemData = objectDataStore:getObjectDataByName(itemName)
			local chainKey = tostring(enums.getPublicName(enums.PrimaryElements, itemData.primaryElement))
				.. "_"
				.. tostring(enums.getPublicName(enums.Rarity, itemData.rarity))

			if not chainsByKey[chainKey] then
				chainsByKey[chainKey] = {
					chainKey = chainKey,
					primaryElement = itemData.primaryElement,
					rarity = itemData.rarity,
					itemNames = {},
					itemDisplayNames = {},
					itemTemplatePaths = {},
					itemCameraPositions = {},
				}
			end

			itemLevelByName[itemName] = itemData.level or 0
			table.insert(chainsByKey[chainKey].itemNames, itemName)
			chainsByKey[chainKey].itemDisplayNames[itemName] = itemData.displayName or itemName
			chainsByKey[chainKey].itemTemplatePaths[itemName] = itemData.casterPath or itemData.templatePath
			chainsByKey[chainKey].itemCameraPositions[itemName] = itemData.indexCameraPosition
				or (itemData.buy and itemData.buy.cameraPosition)
		end
	end

	local chains: { any } = {}

	for _, chain in chainsByKey do
		table.sort(chain.itemNames, function(a: string, b: string)
			return itemLevelByName[a] < itemLevelByName[b]
		end)

		table.insert(chains, chain)
	end

	table.sort(chains, function(a: { primaryElement: number, rarity: number }, b: { primaryElement: number, rarity: number })
		local sortIndexA = elements.getSortIndexForPrimaryElement(a.primaryElement)
		local sortIndexB = elements.getSortIndexForPrimaryElement(b.primaryElement)

		if sortIndexA ~= sortIndexB then
			return sortIndexA < sortIndexB
		end

		return a.rarity < b.rarity
	end)

	return chains
end

function IndexManager.buildAbilityChains(self: IndexManager): { any }
	local chains: { any } = {}

	for _, primaryElement in elements.getPrimaryElementsSorted() do
		local elementAbilities = abilities.getAbilitiesSortedByPrimaryElement(primaryElement)

		local firstTierAbilities: { number } = {}
		for _, ability in elementAbilities do
			local abilityData = abilities.getDataForAbility(ability)
			if abilityData and not abilityData.replaceAbility then
				table.insert(firstTierAbilities, ability)
			end
		end

		if #firstTierAbilities == 0 then
			continue
		end

		table.insert(chains, {
			chainKey = enums.getPublicName(enums.PrimaryElements, primaryElement),
			primaryElement = primaryElement,
			abilities = firstTierAbilities,
		})
	end

	return chains
end

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

function IndexManager.getAllMutationTiers(self: IndexManager): { number }
	return MUTATION_DISPLAY_ORDER
end

function IndexManager.buildMutationChains(self: IndexManager): { any }
	return {
		{
			chainKey = "Mutations",
			mutationTiers = self:getAllMutationTiers(),
		},
	}
end

function IndexManager.getVanityComponentNamesForBlueprintSection(self: IndexManager, sectionKey: number): { string }
	if sectionKey == enums.VanitySection.MAIN_INNER then
		return plotsManager:getAllMainPlotInnerNames()
	elseif sectionKey == enums.VanitySection.MAIN_OUTER then
		return plotsManager:getAllMainPlotOuterNames()
	elseif sectionKey == enums.VanitySection.MAIN_FENCE then
		return plotsManager:getAllFenceNames()
	elseif sectionKey == enums.VanitySection.EXPANSION_INNER then
		return plotsManager:getAllExpansionInnerNames()
	elseif sectionKey == enums.VanitySection.EXPANSION_OUTER then
		return plotsManager:getAllExpansionOuterNames()
	end
	return {}
end

function IndexManager.buildBlueprintChains(self: IndexManager): { any }
	local chainsByKey: { [string]: any } = {}

	for sectionOrder, sectionKey in BLUEPRINT_SECTION_ORDER do
		for _, vanityComponentName in self:getVanityComponentNamesForBlueprintSection(sectionKey) do
			local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
			local blueprintName = vanityComponentData.blueprintName
			if not blueprintName then
				continue
			end

			local itemData = objectDataStore:getObjectDataByName(blueprintName)
			if not itemData then
				warn("index blueprint chain: unknown blueprint item", blueprintName)
				continue
			end

			local chainKey = tostring(enums.getPublicName(enums.VanitySection, sectionKey)) .. "_" .. tostring(enums.getPublicName(enums.Rarity, itemData.rarity))

			if not chainsByKey[chainKey] then
				chainsByKey[chainKey] = {
					chainKey = chainKey,
					section = sectionKey,
					sectionOrder = sectionOrder,
					rarity = itemData.rarity,
					itemNames = {},
					itemDisplayNames = {},
					itemTemplatePaths = {},
					itemCameraPositions = {},
				}
			end

			table.insert(chainsByKey[chainKey].itemNames, blueprintName)
			chainsByKey[chainKey].itemDisplayNames[blueprintName] = itemData.displayName or blueprintName
			chainsByKey[chainKey].itemTemplatePaths[blueprintName] = itemData.templatePath
			chainsByKey[chainKey].itemCameraPositions[blueprintName] = itemData.indexCameraPosition
		end
	end

	local chains: { any } = {}
	for _, chain in chainsByKey do
		table.sort(chain.itemNames)
		table.insert(chains, chain)
	end

	table.sort(chains, function(a: { sectionOrder: number, rarity: number }, b: { sectionOrder: number, rarity: number })
		if a.sectionOrder ~= b.sectionOrder then
			return a.sectionOrder < b.sectionOrder
		end
		return a.rarity < b.rarity
	end)

	return chains
end

function IndexManager.getCategoryChains(self: IndexManager, category: string): { any }
	local cache = self.categoryChainsCache or {}
	self.categoryChainsCache = cache

	if cache[category] then
		return cache[category]
	end

	local chains: { any }

	if category == indexCatalog.Category.DRAGONS then
		chains = self:buildElementRarityChains(CategoryItemTypes[indexCatalog.Category.DRAGONS])
	elseif category == indexCatalog.Category.PLANTS then
		chains = self:buildElementRarityChains(CategoryItemTypes[indexCatalog.Category.PLANTS])
	elseif category == indexCatalog.Category.CRYSTALS then
		chains = self:buildElementRarityChains(CategoryItemTypes[indexCatalog.Category.CRYSTALS])
	elseif category == indexCatalog.Category.ABILITIES then
		chains = self:buildAbilityChains()
	elseif category == indexCatalog.Category.BLUEPRINTS then
		chains = self:buildBlueprintChains()
	elseif category == indexCatalog.Category.MUTATIONS then
		chains = self:buildMutationChains()
	else
		warn("unknown index category", category)
		chains = {}
	end

	cache[category] = chains

	return chains
end

function IndexManager.getChainByKey(self: IndexManager, category: string, chainKey: string?): any
	for _, chain in self:getCategoryChains(category) do
		if chain.chainKey == chainKey then
			return chain
		end
	end

	return nil
end

function IndexManager.getChainProgressForPlayer(self: IndexManager, playerData: any, category: string, chain: any): (number, number)
	if category == indexCatalog.Category.ABILITIES then
		local discoveredCount = 0
		local abilityStatuses = playerData:getAbilityStatuses()

		for _, ability in chain.abilities do
			if abilityStatuses[ability] ~= nil and abilityStatuses[ability] ~= enums.AbilityStatus.LOCKED then
				discoveredCount += 1
			end
		end

		return discoveredCount, #chain.abilities
	end

	if category == indexCatalog.Category.MUTATIONS then
		local discoveredCount = 0
		local discoveredMutations = playerData:getIndexDiscoveredMutations()

		for _, mutation in chain.mutationTiers do
			if discoveredMutations[mutation] then
				discoveredCount += 1
			end
		end

		return discoveredCount, #chain.mutationTiers
	end

	local discoveredCount = 0

	for _, itemName in chain.itemNames do
		if playerData:hasDiscoveredIndexItem(itemName) then
			discoveredCount += 1
		end
	end

	return discoveredCount, #chain.itemNames
end

function IndexManager.computeCategoryProgressForPlayer(self: IndexManager, playerData: any, category: string): (number, number)
	local totalDiscovered = 0
	local totalItems = 0

	for _, chain in self:getCategoryChains(category) do
		local discoveredCount, itemCount = self:getChainProgressForPlayer(playerData, category, chain)
		totalDiscovered += discoveredCount
		totalItems += itemCount
	end

	return totalDiscovered, totalItems
end

function IndexManager.getMilestones(self: IndexManager, playerData: any, category: string, scope: string, chainKey: string?): { any }
	local template = indexRewards.getMilestoneTemplate(scope, category, chainKey)
	local totalTiers = #template

	local discoveredCount, totalItems
	if scope == indexHelpers.Scope.CATEGORY then
		discoveredCount, totalItems = self:computeCategoryProgressForPlayer(playerData, category)
	else
		local chain = self:getChainByKey(category, chainKey)
		if not chain then
			warn("unknown index chain requested", category, chainKey)
			return {}
		end
		discoveredCount, totalItems = self:getChainProgressForPlayer(playerData, category, chain)
	end

	local viewModels: { any } = {}
	local allPreviousTiersClaimed = true
	for tierIndex, tierData in template do
		local tierId = indexHelpers.computeTierId(scope, category, chainKey, tierIndex)
		local isClaimed = playerData:hasClaimedIndexReward(tierId)

		local isClaimable = indexHelpers.isTierClaimable(discoveredCount, totalItems, tierIndex, totalTiers, isClaimed)
		if scope == indexHelpers.Scope.CATEGORY then
			isClaimable = isClaimable and allPreviousTiersClaimed
		end

		viewModels[tierIndex] = {
			tierIndex = tierIndex,
			displayPercent = indexHelpers.computeDisplayPercent(tierIndex, totalTiers),
			threshold = indexHelpers.computeThreshold(totalItems, tierIndex, totalTiers),
			displayText = tierData.displayText,
			isClaimed = isClaimed,
			isClaimable = isClaimable,
			tierId = tierId,
		}

		allPreviousTiersClaimed = allPreviousTiersClaimed and isClaimed
	end

	return viewModels
end

-- the discovery/notification methods live below the chain builders they call so the new
-- solver resolves them backward instead of through long forward references
function IndexManager.getCategoryAndChainKeyForItemName(self: IndexManager, itemName: string): (string?, string?)
	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		return nil, nil
	end

	local category = ItemTypeToCategory[itemData.type]
	if not category then
		return nil, nil
	end

	if category == indexCatalog.Category.BLUEPRINTS then
		for _, chain in self:getCategoryChains(category) do
			if table.find(chain.itemNames, itemName) then
				return category, chain.chainKey
			end
		end
		return category, nil
	end

	local chainKey = tostring(enums.getPublicName(enums.PrimaryElements, itemData.primaryElement))
		.. "_"
		.. tostring(enums.getPublicName(enums.Rarity, itemData.rarity))

	return category, chainKey
end

function IndexManager.hasAnyClaimableReward(self: IndexManager, playerData: any): boolean
	for _, category in indexCatalog.getCategoriesSorted() do
		for _, milestone in self:getMilestones(playerData, category, indexHelpers.Scope.CATEGORY, nil) do
			if milestone.isClaimable then
				return true
			end
		end

		for _, chain in self:getCategoryChains(category) do
			for _, milestone in self:getMilestones(playerData, category, indexHelpers.Scope.CHAIN, chain.chainKey) do
				if milestone.isClaimable then
					return true
				end
			end
		end
	end

	return false
end

function IndexManager.notifyIfHasClaimableReward(self: IndexManager, player: Player, playerData: any)
	if not gameController:isIndexEnabled() then
		return
	end

	if self:hasAnyClaimableReward(playerData) then
		RemoteEvents.NotifyIndexHasClaimableReward:FireClient(player)
	end
end

function IndexManager.notifyMutationDiscoveredIfNew(self: IndexManager, player: Player, playerData: any, mutationTier: number)
	if not gameController:isIndexEnabled() then
		return
	end

	if playerData:hasDiscoveredIndexMutation(mutationTier) then
		return
	end

	playerData:markIndexMutationDiscovered(mutationTier)

	RemoteEvents.NotifyIndexMutationDiscovered:FireClient(player, mutationTier)
	self:notifyIfHasClaimableReward(player, playerData)
end

function IndexManager.notifyItemDiscoveredIfNew(self: IndexManager, player: Player, playerData: any, itemName: string)
	if not gameController:isIndexEnabled() then
		return
	end

	if playerData:hasDiscoveredIndexItem(itemName) then
		return
	end

	playerData:markIndexItemDiscovered(itemName)
	self:notifyIfHasClaimableReward(player, playerData)

	local category, chainKey = self:getCategoryAndChainKeyForItemName(itemName)
	if not category then
		return
	end

	RemoteEvents.NotifyIndexItemDiscovered:FireClient(player, category, chainKey, itemName)
end

function IndexManager.getOwnedCountsForPlayer(self: IndexManager, player: Player, playerData: any): { [string]: number }
	local itemOwnedCounts: { [string]: number } = {}
	for itemName in playerData:getIndexDiscoveredItems() do
		itemOwnedCounts[itemName] = itemManager:getItemCountByUserIdAndName(player.UserId, itemName)
	end
	return itemOwnedCounts
end

function IndexManager.getMilestonesForCategoryForPlayer(self: IndexManager, playerData: any, category: string): any
	local chains: { any } = {}
	local mutationTiers: any = nil

	if category == indexCatalog.Category.MUTATIONS then
		mutationTiers = {}
		local discoveredMutations = playerData:getIndexDiscoveredMutations()

		for _, mutation in self:getAllMutationTiers() do
			table.insert(mutationTiers, {
				mutationTier = mutation,
				publicName = enums.getPublicName(enums.Mutations, mutation),
				isDiscovered = discoveredMutations[mutation] == true,
			})
		end
	elseif category == indexCatalog.Category.ABILITIES then
		local abilityStatuses = playerData:getAbilityStatuses()

		for _, chain in self:getCategoryChains(category) do
			local chainAbilities: { any } = {}
			for _, ability in chain.abilities do
				local abilityData = abilities.getDataForAbility(ability)
				table.insert(chainAbilities, {
					ability = ability,
					displayName = abilityData and abilityData.displayName or nil,
					isDiscovered = abilityStatuses[ability] ~= nil and abilityStatuses[ability] ~= enums.AbilityStatus.LOCKED,
				})
			end

			table.insert(chains, {
				chainKey = chain.chainKey,
				primaryElement = chain.primaryElement,
				abilities = chainAbilities,
				milestones = self:getMilestones(playerData, category, indexHelpers.Scope.CHAIN, chain.chainKey),
			})
		end
	elseif category == indexCatalog.Category.BLUEPRINTS then
		for _, chain in self:getCategoryChains(category) do
			table.insert(chains, {
				chainKey = chain.chainKey,
				rarity = chain.rarity,
				itemNames = chain.itemNames,
				itemDisplayNames = chain.itemDisplayNames,
				itemTemplatePaths = chain.itemTemplatePaths,
				itemCameraPositions = chain.itemCameraPositions,
				section = chain.section,
				milestones = self:getMilestones(playerData, category, indexHelpers.Scope.CHAIN, chain.chainKey),
			})
		end
	else
		for _, chain in self:getCategoryChains(category) do
			table.insert(chains, {
				chainKey = chain.chainKey,
				primaryElement = chain.primaryElement,
				rarity = chain.rarity,
				itemNames = chain.itemNames,
				itemDisplayNames = chain.itemDisplayNames,
				itemTemplatePaths = chain.itemTemplatePaths,
				itemCameraPositions = chain.itemCameraPositions,
				milestones = self:getMilestones(playerData, category, indexHelpers.Scope.CHAIN, chain.chainKey),
			})
		end
	end

	return {
		categoryMilestones = self:getMilestones(playerData, category, indexHelpers.Scope.CATEGORY, nil),
		chains = chains,
		mutationTiers = mutationTiers,
	}
end

function IndexManager.refreshIndexData(self: IndexManager, player: Player, playerData: any): any
	if not playerData:tryConsumeIndexRefreshCooldown() then
		return nil
	end

	local milestonesByCategory: { [string]: any } = {}
	for _, category in indexCatalog.getCategoriesSorted() do
		milestonesByCategory[category] = self:getMilestonesForCategoryForPlayer(playerData, category)
	end

	return {
		ownedCounts = self:getOwnedCountsForPlayer(player, playerData),
		milestonesByCategory = milestonesByCategory,
	}
end

function IndexManager.getFullIndexDataForPlayer(self: IndexManager, player: Player): any
	local playerData = gameController:getPlayerData(player)

	local milestonesByCategory: { [string]: any } = {}

	for _, category in indexCatalog.getCategoriesSorted() do
		milestonesByCategory[category] = self:getMilestonesForCategoryForPlayer(playerData, category)
	end

	local itemOwnedCounts: { [string]: number } = {}
	for itemName in playerData:getIndexDiscoveredItems() do
		itemOwnedCounts[itemName] = itemManager:getItemCountByUserIdAndName(player.UserId, itemName)
	end

	return {
		indexDiscoveredItems = playerData:getIndexDiscoveredItems(),
		itemOwnedCounts = itemOwnedCounts,
		milestonesByCategory = milestonesByCategory,
	}
end

function IndexManager.grantIndexReward(self: IndexManager, player: Player, playerData: any, tierData: any)
	local rewardEntry = tierData.reward
	local rewardType = indexRewards.RewardTypeNames[rewardEntry.rewardType]

	if rewardType == indexHelpers.RewardType.MUTATION_PULL or rewardType == indexHelpers.RewardType.VANITY_PULL then
		local crateItemName = indexHelpers.getIndexRewardCrateItemName(rewardEntry.size)
		local crateItems: { any } = {}
		for i = 1, rewardEntry.count do
			local crateItem = itemManager:createItem(crateItemName, player.UserId) :: Types.Crate?
			if not crateItem then
				warn("failed to create index reward crate")
				continue
			end
			crateItem:setRewardSource(rewardType, rewardEntry.lootTableName, tierData.displayText)
			table.insert(crateItems, crateItem)
		end
		gameController:spawnItemsInBackpack(crateItems)
		for _, item in crateItems do
			playerData:notifyItemReceived(item)
		end
	elseif rewardType == indexHelpers.RewardType.STAT_BUFF then
		playerData:grantIndexStatBuff(rewardEntry.attribute, rewardEntry.amount)
	elseif rewardType == indexHelpers.RewardType.MUTATION_CHANCE_BUFF then
		playerData:grantIndexMutationChanceBuff(rewardEntry.amount)
	else
		warn("unknown index reward type", player, rewardEntry.rewardType)
	end
end

function IndexManager.tryClaimReward(self: IndexManager, player: Player, playerData: any, category: string, scope: string, chainKey: string?, tierIndex: any): boolean
	if not indexCatalog.validateCategory(category) then
		warn("invalid index category claim attempt", player, category)
		return false
	end

	if scope ~= indexHelpers.Scope.CHAIN and scope ~= indexHelpers.Scope.CATEGORY then
		warn("invalid index scope claim attempt", player, scope)
		return false
	end

	if typeof(tierIndex) ~= "number" then
		warn("invalid index tierIndex claim attempt", player, tierIndex)
		return false
	end

	local template = indexRewards.getMilestoneTemplate(scope, category, chainKey)
	if tierIndex < 1 or tierIndex > #template then
		warn("index tierIndex out of range", player, tierIndex, #template)
		return false
	end

	local discoveredCount, totalItems
	if scope == indexHelpers.Scope.CATEGORY then
		discoveredCount, totalItems = self:computeCategoryProgressForPlayer(playerData, category)
	else
		local chain = self:getChainByKey(category, chainKey)
		if not chain then
			warn("unknown index chain claim attempt", player, category, chainKey)
			return false
		end
		discoveredCount, totalItems = self:getChainProgressForPlayer(playerData, category, chain)
	end

	if totalItems <= 0 then
		warn("index chain/category has no items", player, category, chainKey)
		return false
	end

	if scope == indexHelpers.Scope.CATEGORY and tierIndex > 1 then
		local previousTierId = indexHelpers.computeTierId(scope, category, chainKey, tierIndex - 1)
		if not playerData:hasClaimedIndexReward(previousTierId) then
			warn("index tier claimed out of order", player, category, scope, chainKey, tierIndex)
			return false
		end
	end

	local totalTiers = #template
	local tierId = indexHelpers.computeTierId(scope, category, chainKey, tierIndex)
	local isAlreadyClaimed = playerData:hasClaimedIndexReward(tierId)

	if not indexHelpers.isTierClaimable(discoveredCount, totalItems, tierIndex, totalTiers, isAlreadyClaimed) then
		if isAlreadyClaimed then
			warn("index tier already claimed", player, category, scope, chainKey, tierIndex)
		else
			local threshold = indexHelpers.computeThreshold(totalItems, tierIndex, totalTiers)
			warn("index tier not yet claimable", player, category, scope, chainKey, tierIndex, "discovered", discoveredCount, "needs", threshold, "of", totalItems)
		end
		return false
	end

	playerData:markIndexRewardClaimed(tierId)

	self:grantIndexReward(player, playerData, template[tierIndex])

	gameController:sendSystemMessageToPlayer(player, "Claimed reward: " .. template[tierIndex].displayText)

	return true
end

function IndexManager.new(): IndexManager
	local self: IndexManager = setmetatable({} :: IndexManagerFields, IndexManager)

	return self
end

function IndexManager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

local singleton = IndexManager.new()

return singleton
