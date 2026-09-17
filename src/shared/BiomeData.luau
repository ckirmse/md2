--!strict

local BiomeData = {}

export type BiomeGate = {
	biomeIndex: number,
	gateDistance: number,
	speedGate: number?,
}

local HALLWAY_ORIGIN = Vector3.new(-1.044, 0.795, 234.622)
local HALLWAY_DIRECTION = Vector3.new(1, 0, 0)

local GATES: { BiomeGate } = {
	{ biomeIndex = 2, gateDistance = 230, speedGate = nil },
	{ biomeIndex = 3, gateDistance = 430, speedGate = nil },
}
BiomeData.GATES = GATES
BiomeData.HALLWAY_DIRECTION = HALLWAY_DIRECTION

function BiomeData.setSpeedGateForBiome(biomeIndex: number, speedGate: number)
	for _, gate in GATES do
		if gate.biomeIndex == biomeIndex then
			gate.speedGate = speedGate
			return
		end
	end
	warn("no gate found for biome index", biomeIndex, "cannot set speed gate")
end

-- fixed at pickup biome rather than recomputed live as the carrier travels back
local CARRY_SPEED_MULT_BY_BIOME: { [number]: number } = {
	[1] = 0.9,
	[2] = 0.85,
	[3] = 0.8,
}
BiomeData.CARRY_SPEED_MULT_BY_BIOME = CARRY_SPEED_MULT_BY_BIOME

function BiomeData.getCarrySpeedMultForBiome(biomeIndex: number): number
	return CARRY_SPEED_MULT_BY_BIOME[biomeIndex] or 1
end

function BiomeData.getProgress(position: Vector3): number
	return (position - HALLWAY_ORIGIN):Dot(HALLWAY_DIRECTION)
end

function BiomeData.isInBiomeLevels(position: Vector3): boolean
	return BiomeData.getProgress(position) >= 0
end

function BiomeData.getGoverningGate(position: Vector3): BiomeGate?
	local progress = BiomeData.getProgress(position)
	local governing: BiomeGate? = nil
	for _, gate in GATES do
		if
			progress >= gate.gateDistance
			and (governing == nil or gate.gateDistance > (governing :: BiomeGate).gateDistance)
		then
			governing = gate
		end
	end
	return governing
end

return BiomeData
