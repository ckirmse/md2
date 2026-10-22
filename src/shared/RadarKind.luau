--!strict

local RadarKind = {}

RadarKind.COSMIC = 0

function RadarKind.get(targetRarity: number, targetsCosmic: boolean): number
	return if targetsCosmic then RadarKind.COSMIC else targetRarity
end

return RadarKind
