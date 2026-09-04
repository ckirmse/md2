--!strict

-- GameData tables are authored in Studio and stay untyped; the return sites cast to { MilestoneTemplate }
local indexChainReward: any = require("@game/ServerScriptService/GameData/Control/IndexChainRewards")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")

local IndexRewards = {}

-- one milestone template entry: { displayText: string, reward: { rewardType, lootTableName?, count?, ... } }
export type MilestoneTemplate = {
	displayText: string,
	reward: {
		rewardType: string,
		lootTableName: string?,
		count: number?,
		statType: string?,
		amount: number?,
		size: string?,
	},
}

IndexRewards.RewardTypeNames = {
	["Chamber Pull"] = indexHelpers.RewardType.MUTATION_PULL,
	["Chest Pull"] = indexHelpers.RewardType.VANITY_PULL,
	["Stat Buff"] = indexHelpers.RewardType.STAT_BUFF,
	["Mutation Chance"] = indexHelpers.RewardType.MUTATION_CHANCE_BUFF,
} :: { [string]: string }

function IndexRewards.getMilestoneTemplate(scope: string, category: string, chainKey: string?): { MilestoneTemplate }
	if scope == indexHelpers.Scope.CATEGORY then
		return ((indexChainReward.category and indexChainReward.category[category]) or {}) :: { MilestoneTemplate }
	end

	local chainTemplates = indexChainReward.chain and indexChainReward.chain[category]
	return ((chainTemplates and chainKey and chainTemplates[chainKey]) or {}) :: { MilestoneTemplate }
end

return IndexRewards
