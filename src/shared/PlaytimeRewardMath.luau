--!strict

-- Pure math for playtime rewards: percentage-of-hourly-income coin amounts (clamped and rounded to
-- 3 significant figures), time-skip coin amounts, countdown formatting and tile sort order.

local PlaytimeRewardMath = {}

export type SortableReward = {
	index: number,
	unlockSec: number,
}

-- rounds to 3 significant figures, e.g. 12345 -> 12300, 0.012345 -> 0.0123
function PlaytimeRewardMath.roundTo3SigFigs(value: number): number
	if value <= 0 then
		return 0
	end
	local magnitude = 10 ^ (math.floor(math.log10(value)) - 2)
	return math.floor(value / magnitude + 0.5) * magnitude
end

-- the coin reward is a whole number; the clamp comes before the rounding so a rounded amount never
-- ends up outside the designer's range by more than the rounding step
function PlaytimeRewardMath.computeCoinReward(hourlyIncome: number, percent: number, minCoins: number, maxCoins: number): number
	local amount = math.clamp(hourlyIncome * percent / 100, minCoins, maxCoins)
	return math.max(math.floor(PlaytimeRewardMath.roundTo3SigFigs(amount) + 0.5), 0)
end

function PlaytimeRewardMath.computeTimeSkipCoins(incomePerSec: number, skipSec: number): number
	return math.max(math.floor(incomePerSec * skipSec + 0.5), 0)
end

-- m:ss, or h:mm:ss once an hour or more remains
function PlaytimeRewardMath.formatCountdown(remainingSec: number): string
	local total = math.max(0, math.floor(remainingSec))
	local hours = total // 3600
	local minutes = (total % 3600) // 60
	local seconds = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%d:%02d", minutes, seconds)
end

-- reward indices ordered by least unlock time; ties keep data order
function PlaytimeRewardMath.getSortedOrder(rewards: { SortableReward }): { number }
	local order = table.clone(rewards)
	table.sort(order, function(a, b)
		if a.unlockSec ~= b.unlockSec then
			return a.unlockSec < b.unlockSec
		end
		return a.index < b.index
	end)

	local indices: { number } = {}
	for _, reward in order do
		table.insert(indices, reward.index)
	end
	return indices
end

return PlaytimeRewardMath
