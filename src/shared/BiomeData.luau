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
local GATES: { BiomeGate } = {
	{ biomeIndex = 2, gateZ = 460.4, speedGate = 130 },
}
BiomeData.GATES = GATES

-- the gate governing position z: the crossed gate with the highest gateZ, or nil before all gates
function BiomeData.getGoverningGate(z: number): BiomeGate?
	local governing: BiomeGate? = nil
	for _, gate in BiomeData.GATES do
		if z >= gate.gateZ and (governing == nil or gate.gateZ > (governing :: BiomeGate).gateZ) then
			governing = gate
		end
	end
	return governing
end

return BiomeData
