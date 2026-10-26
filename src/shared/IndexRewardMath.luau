--!strict

local enums = require("@game/ReplicatedStorage/Shared/Enums")

local IndexRewardMath = {}

IndexRewardMath.Kind = {
	ROW = "row",
	TIER = "tier",
}

-- categories without rarities (mutations, traits) put every entry in this one group
IndexRewardMath.SINGLE_GROUP = enums.Rarity.COMMON

export type Milestone = {
	tierId: string,
	kind: string,
	rarity: number?,
	tierIndex: number?,
	collected: number,
	total: number,
	threshold: number,
	isClaimed: boolean,
	isClaimable: boolean,
}

type CountByGroup = { [number]: number }

-- tier ids are saved with the player's claims, so these formats and the public names of the index categories and
-- rarities must stay stable
function IndexRewardMath.makeRowTierId(category: number, rarity: number): string
	return tostring(enums.getPublicName(enums.IndexCategory, category))
		.. "Row"
		.. tostring(enums.getPublicName(enums.Rarity, rarity))
end

function IndexRewardMath.makeTierId(category: number, tierIndex: number): string
	return tostring(enums.getPublicName(enums.IndexCategory, category)) .. "Tier" .. tierIndex
end

function IndexRewardMath.getThreshold(total: number, percent: number): number
	return math.ceil(total * percent / 100)
end

function IndexRewardMath.getDisplayPercent(collected: number, total: number): number
	if total <= 0 then
		return 0
	end

	return math.floor(100 * collected / total)
end

-- rowRarities lists the rarities that have a row reward; tierPercents is the ordered list of category tier
-- percentages. The client and the server build the list from the same inputs, so a milestone the client shows as
-- claimable is the one the server accepts.
function IndexRewardMath.buildMilestones(
	category: number,
	rowRarities: { number },
	tierPercents: { number },
	collectedByGroup: CountByGroup,
	totalByGroup: CountByGroup,
	claimedSet: { [string]: boolean }
): { Milestone }
	local milestones: { Milestone } = {}

	local categoryCollected = 0
	local categoryTotal = 0
	for _, rarity in enums.getAllValues(enums.Rarity) do
		local total = totalByGroup[rarity] or 0
		categoryCollected += math.min(collectedByGroup[rarity] or 0, total)
		categoryTotal += total
	end

	for _, rarity in rowRarities do
		local total = totalByGroup[rarity] or 0
		if total == 0 then
			continue
		end

		local collected = math.min(collectedByGroup[rarity] or 0, total)
		local tierId = IndexRewardMath.makeRowTierId(category, rarity)
		local isClaimed = claimedSet[tierId] == true
		table.insert(milestones, {
			tierId = tierId,
			kind = IndexRewardMath.Kind.ROW,
			rarity = rarity,
			tierIndex = nil,
			collected = collected,
			total = total,
			threshold = total,
			isClaimed = isClaimed,
			isClaimable = not isClaimed and collected >= total,
		})
	end

	-- category tiers are claimed in order so the bottom bar always reads left to right
	local allPreviousClaimed = true
	for tierIndex, percent in tierPercents do
		local tierId = IndexRewardMath.makeTierId(category, tierIndex)
		local isClaimed = claimedSet[tierId] == true
		local threshold = IndexRewardMath.getThreshold(categoryTotal, percent)
		local isReached = categoryTotal > 0 and categoryCollected >= threshold
		table.insert(milestones, {
			tierId = tierId,
			kind = IndexRewardMath.Kind.TIER,
			rarity = nil,
			tierIndex = tierIndex,
			collected = categoryCollected,
			total = categoryTotal,
			threshold = threshold,
			isClaimed = isClaimed,
			isClaimable = not isClaimed and isReached and allPreviousClaimed,
		})
		allPreviousClaimed = allPreviousClaimed and isClaimed
	end

	return milestones
end

function IndexRewardMath.findMilestone(milestones: { Milestone }, tierId: string): Milestone?
	for _, milestone in milestones do
		if milestone.tierId == tierId then
			return milestone
		end
	end

	return nil
end

function IndexRewardMath.hasClaimable(milestones: { Milestone }): boolean
	for _, milestone in milestones do
		if milestone.isClaimable then
			return true
		end
	end

	return false
end

return IndexRewardMath
