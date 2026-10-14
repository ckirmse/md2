--!strict

-- Pure math for daily login rewards. Progress is claim-driven and never resets: day N stays claimable until it is
-- claimed, and claiming starts a DAY_SEC timer before day N+1 opens. Missing days costs nothing. Days 1 to
-- TILE_COUNT - 1 each have a tile; the last tile is shown for that day and every day after it.

local Constants = require("./Constants")

local DailyLoginMath = {}

DailyLoginMath.DAY_SEC = Constants.DAY_SEC
DailyLoginMath.TILE_COUNT = 8

export type DailyLoginState = {
	lastClaimedDay: number,
	nextClaimTime: number,
}

-- nil when nothing is claimable right now
function DailyLoginMath.getClaimableDay(state: DailyLoginState, now: number): number?
	if now < state.nextClaimTime then
		return nil
	end

	return state.lastClaimedDay + 1
end

-- applies a claim of the currently claimable day at `now` to a copy of `state`
function DailyLoginMath.applyClaim(state: DailyLoginState, now: number): DailyLoginState
	local newState = table.clone(state)
	newState.lastClaimedDay += 1
	newState.nextClaimTime = math.floor(now) + DailyLoginMath.DAY_SEC

	return newState
end

function DailyLoginMath.getTileForDay(dayIndex: number): number
	return math.min(dayIndex, DailyLoginMath.TILE_COUNT)
end

-- seconds until the next reward becomes claimable, or nil if one is claimable right now ("READY TO CLAIM")
function DailyLoginMath.getNextRewardRemainingSec(state: DailyLoginState, now: number): number?
	if DailyLoginMath.getClaimableDay(state, now) then
		return nil
	end

	return state.nextClaimTime - now
end

return DailyLoginMath
