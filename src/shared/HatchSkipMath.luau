--!strict

local HatchSkipMath = {}

HatchSkipMath.SEC_PER_DIAMOND = 600

function HatchSkipMath.getCost(remainingSec: number): number
	return math.max(1, math.ceil(remainingSec / HatchSkipMath.SEC_PER_DIAMOND))
end

return HatchSkipMath
