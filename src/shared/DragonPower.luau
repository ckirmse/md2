--!strict

-- Fuse Dragons 2 core stat: per-dragon Dragon Power (DP). Pure arithmetic only — one function per
-- factor in the spec (§2.1), composed by the caller:
--
--   rarityBase  = rarityStep ^ tierIndex                       -- 25 ^ (0-based rarity tier)
--   basePower   = rarityBase * levelMult ^ (level - 1)         -- geometric within a rarity band
--   masteryMult = 1 + masteryPerLevel * masteryLevel           -- element-mastery DP multiplier
--   DragonPower = basePower * (1 + mutationBonus) * (1 + traitBonus) * masteryMult
--
-- Callers own all policy: mapping a `Control/DragonPower` tuning table onto these args, converting a
-- rarity enum to a 0-based tier index, clamping `traitBonus` to its cap, guarding bad inputs. This
-- module never reads GameData and never warns, so it runs unchanged on client or server.

local DragonPower = {}

-- rarityStep ^ tierIndex  -- base power of a level-1 dragon at the given 0-based rarity tier
function DragonPower.rarityBase(rarityStep: number, tierIndex: number): number
	return rarityStep ^ tierIndex
end

-- rarityBase * levelMult ^ (level - 1)  -- base power for a dragon at `level` within its rarity band
function DragonPower.basePower(rarityBase: number, levelMult: number, level: number): number
	return rarityBase * levelMult ^ (level - 1)
end

-- 1 + masteryPerLevel * masteryLevel  -- the element-mastery DP multiplier
function DragonPower.masteryMult(masteryPerLevel: number, masteryLevel: number): number
	return 1 + masteryPerLevel * masteryLevel
end

-- The full per-dragon product. `mutationBonus` and `traitBonus` are fractions (0.10 = +10%); the
-- caller has already clamped `traitBonus` to the configured cap.
function DragonPower.compute(base: number, mutationBonus: number, traitBonus: number, masteryMult: number): number
	return base * (1 + mutationBonus) * (1 + traitBonus) * masteryMult
end

return DragonPower
