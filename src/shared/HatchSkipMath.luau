--!strict

local HatchSkipMath = {}

HatchSkipMath.DEFAULT_SEC_PER_DIAMOND = 600

function HatchSkipMath.getCost(remainingSec: number, secPerDiamond: number): number
	return math.max(1, math.ceil(remainingSec / secPerDiamond))
end

return HatchSkipMath
