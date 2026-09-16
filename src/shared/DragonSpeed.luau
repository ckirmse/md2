--!strict

-- Speed(r,L) = base(r) * (1 + perLevelFrac * (level - 1)), document 3 Part 1. Pure arithmetic
-- only; callers own policy (looking up base(r) by rarity, reading the dragon's current level).

local DragonSpeed = {}

function DragonSpeed.speedForLevel(baseSpeed: number, perLevelFrac: number, level: number): number
	return baseSpeed * (1 + perLevelFrac * (level - 1))
end

return DragonSpeed
