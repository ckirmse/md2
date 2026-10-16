--!strict

-- Dragon Riders 2 core stat: a dragon's per-second income contribution, from the v1.0 design spec:
--
--   income = BaseIncome(r) x LevelMod x Size x Mutation
--
-- BaseIncome and LevelMod come from RarityMath / GameData/Control/Rarities. Traits never affect income (they multiply
-- speed only). Callers own all policy: resolving the rarity row, guarding bad inputs. This module never reads GameData
-- and never warns, so it runs unchanged on client or server.

local DragonIncome = {}

-- 1 + sizeIncomeCoeff * (size - 1)  -- the dragon's size income multiplier
function DragonIncome.sizeMult(sizeIncomeCoeff: number, size: number): number
	return 1 + sizeIncomeCoeff * (size - 1)
end

-- 1 + multPerLevel * (dragonLevel - 1). No longer used for income (RarityMath.getLevelMod is); kept for the sell value
-- until the sell module is reworked to 20 minutes of income
function DragonIncome.levelMult(multPerLevel: number, dragonLevel: number): number
	return 1 + multPerLevel * (dragonLevel - 1)
end

-- The full per-dragon product. `baseIncome` and `levelMod` are resolved by the caller (RarityMath); `mutationBonus` is
-- a fraction (0.10 = +10%).
function DragonIncome.compute(baseIncome: number, levelMod: number, sizeMult: number, mutationBonus: number): number
	return baseIncome * levelMod * sizeMult * (1 + mutationBonus)
end

return DragonIncome
