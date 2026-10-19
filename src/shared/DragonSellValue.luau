--!strict

-- A dragon sells for 20 minutes of its income: BaseIncome x LevelMod x Size x Mutation x 1,200
local DragonSellValue = {}

local SELL_INCOME_SEC = 20 * 60

function DragonSellValue.compute(income: number): number
	return math.floor(income * SELL_INCOME_SEC)
end

return DragonSellValue
