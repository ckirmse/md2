--!strict

-- Pure rarity/leveling math from the v1.0 design spec ("Rarity, Leveling & Fusion" > Master Table and Formulas).
-- The per-rarity numbers live in the Studio-only GameData/Control/Rarities table (one row per Enums.Rarity); this module
-- only turns a row into the spec's formulas, so it never reads GameData and runs on client or server.

local RarityMath = {}

-- one row of the Master Table (GameData/Control/Rarities). hatchOddsN and hatchTimerSec belong to the egg modules and
-- fusionPremium to fusion; they are verified with the rest so the whole table is authored in one place
export type RarityRow = {
	hatchOddsN: number, -- "1 in N" hatch odds
	hatchTimerSec: number,
	baseIncome: number,
	baseSpeed: number, -- multiplier
	modelScale: number, -- RarityScale(r), the model scale at level 1
	levelCap: number,
	timeToCapSec: number, -- on the plot, documentation for the designer (xpToCap / plot XP rate)
	xpToCap: number, -- total XP from level 1 to the cap
	fusionPremium: number?, -- nil for Common (nothing fuses into it)
}

-- XP to next level = a_r * XP_GROWTH^(L - 1), with a_r set so the total from level 1 to the cap equals xpToCap
RarityMath.XP_GROWTH = 1.1

-- visual growth from level 1 to the cap (Growth(L) = 1 + MODEL_GROWTH_AT_CAP * (L - 1) / (cap - 1))
RarityMath.MODEL_GROWTH_AT_CAP = 0.2

-- LevelSpeed gains at most +25% at the cap (consumed by the speed module)
RarityMath.SPEED_GAIN_AT_CAP = 0.25

RarityMath.SIZE_SCALE_MIN = 0.85
RarityMath.SIZE_SCALE_SPAN = 0.30

RarityMath.DEFAULT_SIZE_PERCENTILE = 50

-- an egg that authors no size range rolls as Standard
RarityMath.STANDARD_SIZE_PERCENTILE_MIN = 0
RarityMath.STANDARD_SIZE_PERCENTILE_MAX = 70

-- progress through the levels: 0 at level 1, 1 at the cap
local function levelProgress(level: number, levelCap: number): number
	if levelCap <= 1 then
		return 1
	end
	return math.clamp((level - 1) / (levelCap - 1), 0, 1)
end

-- a_r: the XP needed to go from level 1 to level 2
function RarityMath.getXpScale(row: RarityRow): number
	-- sum of XP_GROWTH^(k) for k = 0 .. cap - 2
	local steps = row.levelCap - 1
	local geometricSum = (RarityMath.XP_GROWTH ^ steps - 1) / (RarityMath.XP_GROWTH - 1)
	return row.xpToCap / geometricSum
end

-- XP needed to leave `level`, or nil at the cap
function RarityMath.getNextLevelXp(row: RarityRow, level: number): number?
	if level >= row.levelCap then
		return nil
	end
	return math.max(1, math.floor(RarityMath.getXpScale(row) * RarityMath.XP_GROWTH ^ (level - 1) + 0.5))
end

-- LevelMod = 1 + (L - 1) / (cap - 1): exactly 2.0x at the cap for every rarity
function RarityMath.getLevelMod(row: RarityRow, level: number): number
	return 1 + levelProgress(level, row.levelCap)
end

-- LevelSpeed = 1 + 0.25 * (L - 1) / (cap - 1)
function RarityMath.getLevelSpeed(row: RarityRow, level: number): number
	return 1 + RarityMath.SPEED_GAIN_AT_CAP * levelProgress(level, row.levelCap)
end

-- Growth(L) = 1 + 0.2 * (L - 1) / (cap - 1): visual only, the Size stat never changes with level
function RarityMath.getGrowth(row: RarityRow, level: number): number
	return 1 + RarityMath.MODEL_GROWTH_AT_CAP * levelProgress(level, row.levelCap)
end

function RarityMath.getSizeScale(sizePercentile: number): number
	return RarityMath.SIZE_SCALE_MIN + RarityMath.SIZE_SCALE_SPAN * math.clamp(sizePercentile, 0, 100) / 100
end

-- Model Scale = RarityScale(r) * SizeScale * Growth(L)
function RarityMath.getModelScale(row: RarityRow, sizeScale: number, level: number): number
	return row.modelScale * sizeScale * RarityMath.getGrowth(row, level)
end

-- the problems with a Master Table row, for the startup verifier (empty when the row is fine)
function RarityMath.validateRow(row: any): { string }
	local problems: { string } = {}
	if type(row) ~= "table" then
		table.insert(problems, "row is missing")
		return problems
	end

	local function needPositive(field: string)
		local value = row[field]
		if type(value) ~= "number" or value ~= value or value <= 0 then
			table.insert(problems, `{field} must be a number > 0`)
		end
	end
	needPositive("hatchOddsN")
	needPositive("hatchTimerSec")
	needPositive("baseIncome")
	needPositive("baseSpeed")
	needPositive("modelScale")
	needPositive("timeToCapSec")
	needPositive("xpToCap")

	local levelCap = row.levelCap
	if type(levelCap) ~= "number" or levelCap ~= math.floor(levelCap) or levelCap < 2 then
		table.insert(problems, "levelCap must be an integer >= 2")
	end
	if row.fusionPremium ~= nil and (type(row.fusionPremium) ~= "number" or row.fusionPremium <= 0) then
		table.insert(problems, "fusionPremium must be a number > 0 or nil")
	end
	return problems
end

return RarityMath
