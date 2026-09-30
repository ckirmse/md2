--!strict

-- Fuse Dragons 2 core stat: a dragon's per-second income contribution, built to match the v0.5
-- design spec's income factor list directly (Rarity, Size, Level, Mutation, Traits):
--
--   sizeMult    = 1 + sizeIncomeCoeff * (size - 1)
--   levelMult   = 1 + levelIncomeMultPerLevel * (dragonLevel - 1)
--   income      = staticBase * rarityMult * sizeMult * levelMult * (1 + mutationBonus) * (1 + traitBonus)
--
-- Callers own all policy: resolving `staticBase` (per static item-tier) and `rarityMult` (per
-- rarity) from GameData lookup tables, clamping `traitBonus` to its cap, guarding bad inputs. This
-- module never reads GameData and never warns, so it runs unchanged on client or server.

local DragonIncome = {}

-- 1 + sizeIncomeCoeff * (size - 1)  -- the dragon's size income multiplier
function DragonIncome.sizeMult(sizeIncomeCoeff: number, size: number): number
	return 1 + sizeIncomeCoeff * (size - 1)
end

-- 1 + levelIncomeMultPerLevel * (dragonLevel - 1)  -- the per-instance XP-level income multiplier
function DragonIncome.levelMult(levelIncomeMultPerLevel: number, dragonLevel: number): number
	return 1 + levelIncomeMultPerLevel * (dragonLevel - 1)
end

-- The full per-dragon product. `staticBase` and `rarityMult` are GameData lookups the caller
-- resolves; `mutationBonus` and `traitBonus` are fractions (0.10 = +10%); the caller has already
-- clamped `traitBonus` to the configured cap.
function DragonIncome.compute(
	staticBase: number,
	rarityMult: number,
	sizeMult: number,
	levelMult: number,
	mutationBonus: number,
	traitBonus: number
): number
	return staticBase * rarityMult * sizeMult * levelMult * (1 + mutationBonus) * (1 + traitBonus)
end

return DragonIncome
