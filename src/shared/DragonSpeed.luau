--!strict

-- Multiplier on BASE_RIDE_SPEED: BaseSpeed x LevelSpeed x Mutation x (1 + b x TypeShare) x TraitMult
local DragonSpeed = {}

function DragonSpeed.compute(
	baseSpeed: number,
	levelSpeed: number,
	mutationMult: number,
	biomeTypeMult: number,
	traitMult: number
): number
	return baseSpeed * levelSpeed * mutationMult * biomeTypeMult * traitMult
end

return DragonSpeed
