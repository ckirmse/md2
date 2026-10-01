--!strict

-- sellValue = rarityBaseValue * elementMultiplier * levelMult
-- `levelMult` comes from DragonIncome.levelMult, not duplicated here.

local DragonSellValue = {}

function DragonSellValue.compute(rarityBaseValue: number, elementMultiplier: number, levelMult: number): number
	return math.floor(rarityBaseValue * elementMultiplier * levelMult)
end

return DragonSellValue
