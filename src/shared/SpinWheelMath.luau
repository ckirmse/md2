--!strict

-- Pure math for M38 daily spin wheel: free-spin accrual against a global
-- epoch-day anchor, entry ranking (rarer = better) for the paid 2x-luck
-- best-of-N roll, and display odds for both luck levels.

local Constants = require("./Constants")

local SpinWheelMath = {}

-- loot tables come from Studio GameData; only the weight and the result identity matter here
export type LootEntry = { weight: number, result: any }
export type LootTable = { LootEntry }

SpinWheelMath.DAY_SEC = Constants.DAY_SEC

function SpinWheelMath.computeEpochDay(now: number): number
	return math.floor(now / SpinWheelMath.DAY_SEC)
end

function SpinWheelMath.getNextDayBoundaryTime(now: number): number
	return (SpinWheelMath.computeEpochDay(now) + 1) * SpinWheelMath.DAY_SEC
end

-- lastGrantDay == 0 is the never-granted sentinel: a brand-new player gets
-- exactly one spin rather than every day since the epoch
function SpinWheelMath.computeGrantedFreeSpins(lastGrantDay: number, today: number, cap: number): number
	if lastGrantDay == 0 then
		return 1
	end
	return math.clamp(today - lastGrantDay, 0, cap)
end

-- rank by index: 1 = best. Rarer (lower weight) is better; ties broken by
-- earlier table position. Segment order on the wheel is the table order.
function SpinWheelMath.rankEntries(lootTable: LootTable): { number }
	local order = {}
	for index in lootTable do
		table.insert(order, index)
	end
	table.sort(
		order,
		function(a, b)
			if lootTable[a].weight ~= lootTable[b].weight then
				return lootTable[a].weight < lootTable[b].weight
			end
			return a < b
		end
	)

	local ranks = table.create(#lootTable, 0)
	for rank, index in order do
		ranks[index] = rank
	end
	return ranks
end

-- comparator for LootTableMath.calculateBestLootResultsByTableAndRandom
function SpinWheelMath.makeIsBetterResult(
	lootTable: LootTable
): (any, any) -> boolean
	local ranks = SpinWheelMath.rankEntries(lootTable)
	local rankByResult = {}
	for index, entry in lootTable do
		rankByResult[entry.result] = ranks[index]
	end
	return function(a, b)
		return rankByResult[a] < rankByResult[b]
	end
end

-- fraction per entry index at 1x luck (single roll)
function SpinWheelMath.computeFractions(lootTable: LootTable): { number }
	local totalWeight = 0
	for _, entry in lootTable do
		totalWeight += entry.weight
	end

	local fractions = {}
	for index, entry in lootTable do
		fractions[index] = if totalWeight > 0 then entry.weight / totalWeight else 0
	end
	return fractions
end

-- fraction per entry index for a best-of-rollCount draw: entry r lands iff
-- every roll is r-or-worse and at least one roll is r, so
-- P(r) = (worse + p_r)^n - worse^n, where worse = total fraction of entries
-- strictly worse-ranked than r
function SpinWheelMath.computeBestOfNFractions(lootTable: LootTable, rollCount: number): { number }
	local fractions = SpinWheelMath.computeFractions(lootTable)
	local ranks = SpinWheelMath.rankEntries(lootTable)

	local bestFractions = {}
	for index, fraction in fractions do
		local worse = 0
		for otherIndex, otherFraction in fractions do
			if ranks[otherIndex] > ranks[index] then
				worse += otherFraction
			end
		end
		bestFractions[index] = (worse + fraction) ^ rollCount - worse ^ rollCount
	end
	return bestFractions
end

return SpinWheelMath
