--!strict

local BiomeData = {}

export type BiomeGate = {
	biomeIndex: number,
	gateZ: number,
	speedGate: number,
}

-- biomes sit in a straight line along +Z; each gate covers everything from its gateZ onward until
-- the next gate's gateZ. gateZ values are placeholders (no Studio geometry yet); speedGate values
-- are document 3's real numbers. Append entries here as more biomes get built.
BiomeData.GATES: { BiomeGate } = {
	{ biomeIndex = 2, gateZ = 460.4, speedGate = 130 },
}

function BiomeData.getRequiredSpeedForZ(z: number): number
	local required = 0
	for _, gate in BiomeData.GATES do
		if z >= gate.gateZ and gate.speedGate > required then
			required = gate.speedGate
		end
	end
	return required
end

return BiomeData
