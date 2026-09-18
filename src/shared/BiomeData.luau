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

BiomeData.SPEED_GATE_PASS_COLOR = Color3.fromRGB(85, 255, 127)
BiomeData.SPEED_GATE_FAIL_COLOR = Color3.fromRGB(255, 85, 85)
BiomeData.SPEED_GATE_NEUTRAL_COLOR = Color3.fromRGB(255, 255, 255)

function BiomeData.setSpeedGateForBiome(biomeIndex: number, speedGate: number)
	for _, gate in GATES do
		if gate.biomeIndex == biomeIndex then
			gate.speedGate = speedGate
			return
		end
	end
	warn("no gate found for biome index", biomeIndex, "cannot set speed gate")
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
