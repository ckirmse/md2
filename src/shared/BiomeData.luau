--!strict

local BiomeData = {}

export type BiomeGate = {
	biomeIndex: number,
	gateDistance: number,
	speedGate: number,
}

local HALLWAY_ORIGIN = Vector3.new(-1.044, 0.795, 234.622)
local HALLWAY_DIRECTION = Vector3.new(1, 0, 0)

local GATES: { BiomeGate } = {
	{ biomeIndex = 2, gateDistance = 230, speedGate = 130 },
	{ biomeIndex = 3, gateDistance = 430, speedGate = 200 },
}
BiomeData.GATES = GATES
BiomeData.HALLWAY_DIRECTION = HALLWAY_DIRECTION

function BiomeData.getProgress(position: Vector3): number
	return (position - HALLWAY_ORIGIN):Dot(HALLWAY_DIRECTION)
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
