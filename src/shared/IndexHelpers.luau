--!strict

local IndexHelpers = {}

IndexHelpers.RewardType = {
	MUTATION_PULL = "mutationPull",
	VANITY_PULL = "vanityPull",
	STAT_BUFF = "statBuff",
	MUTATION_CHANCE_BUFF = "mutationChanceBuff",
}

IndexHelpers.RewardCrateSize = {
	SMALL = "small",
	MEDIUM = "medium",
	LARGE = "large",
}

local indexRewardCrateItemNamesBySize = {
	[IndexHelpers.RewardCrateSize.SMALL] = "Index Reward Crate Small",
	[IndexHelpers.RewardCrateSize.MEDIUM] = "Index Reward Crate Medium",
	[IndexHelpers.RewardCrateSize.LARGE] = "Index Reward Crate Large",
}

function IndexHelpers.getIndexRewardCrateItemName(size: any): string
	local itemName = indexRewardCrateItemNamesBySize[size]
	if not itemName then
		if size ~= nil then
			warn("unknown index reward crate size, defaulting to medium", size)
		end
		itemName = indexRewardCrateItemNamesBySize[IndexHelpers.RewardCrateSize.MEDIUM]
	end

	return itemName
end

IndexHelpers.Scope = {
	CHAIN = "chain",
	CATEGORY = "category",
}

function IndexHelpers.computeTierId(scope: string, categoryKey: string, chainKey: string?, tierIndex: number): string
	if scope == IndexHelpers.Scope.CATEGORY then
		return categoryKey .. "_overall_t" .. tierIndex
	end

	return categoryKey .. "_" .. tostring(chainKey) .. "_t" .. tierIndex
end

function IndexHelpers.computeDisplayPercent(tierIndex: number, totalTiers: number): number
	if totalTiers <= 0 then
		return 0
	end

	return math.round(100 * tierIndex / totalTiers)
end

function IndexHelpers.computeThreshold(totalItems: number, tierIndex: number, totalTiers: number): number
	if totalTiers <= 0 then
		return 0
	end

	return math.ceil(totalItems * tierIndex / totalTiers)
end

function IndexHelpers.isTierClaimable(discoveredCount: number, totalItems: number, tierIndex: number, totalTiers: number, isAlreadyClaimed: boolean): boolean
	if isAlreadyClaimed then
		return false
	end

	return discoveredCount >= IndexHelpers.computeThreshold(totalItems, tierIndex, totalTiers)
end

return IndexHelpers
