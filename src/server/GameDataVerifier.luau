--!strict

local GameDataVerifier = {}
GameDataVerifier.__index = GameDataVerifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DailyLoginMath = require("@game/ReplicatedStorage/Shared/DailyLoginMath")
local EggSlotConfig = require("@game/ReplicatedStorage/Shared/EggSlotConfig")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local RarityMath = require("@game/ReplicatedStorage/Shared/RarityMath")
local dailyLoginData = require("@game/ServerScriptService/GameData/Control/DailyLogin")
local eggLootTablesData = require("@game/ServerScriptService/GameData/Control/EggLootTables")
local eggSpawningData = require("@game/ServerScriptService/GameData/Control/EggSpawning")
local dragonProgressionData = require("@game/ServerScriptService/GameData/Control/DragonProgression")
local playtimeData = require("@game/ServerScriptService/GameData/Control/Playtime")
local rarityData = require("@game/ServerScriptService/GameData/Control/Rarities")
local hatchingData = require("@game/ServerScriptService/GameData/Control/Hatching")
local indexRewardsData = require("@game/ServerScriptService/GameData/Control/IndexRewards")
local rebirthData = require("@game/ServerScriptService/GameData/Control/Rebirth")
local spinWheelData = require("@game/ServerScriptService/GameData/Control/SpinWheel")

local objectDataStore = require("./ObjectDataStore")
local Validate = require("./Validate")

type GameDataVerifierFields = {}

export type GameDataVerifier = typeof(setmetatable({} :: GameDataVerifierFields, GameDataVerifier))

local lootEntryShape = {
	weight = "nonnegativeNumber",
	result = {
		type = "table",
		optional = true,
	},
	resultLootTable = {
		type = "table",
		optional = true,
		shape = {
			lootTableName = "string",
			count = "positiveInteger",
		},
	},
	resultLootTables = {
		type = "array",
		optional = true,
		nonempty = true,
		elementType = {
			lootTableName = "string",
			count = "positiveInteger",
		},
	},
	requiredConfig = {
		type = "string",
		optional = true,
	},
}

local singlePathShape = {
	name = "string",
	displayName = "string",
	templatePath = "string",
	rarity = { type = "enum", name = "Rarity" },
	blueprintName = { type = "string", optional = true },
}

local multiPathShape = {
	name = "string",
	displayName = "string",
	templatePaths = "table",
	rarity = { type = "enum", name = "Rarity" },
	blueprintName = { type = "string", optional = true },
}

function GameDataVerifier.checkAssetPath(self: GameDataVerifier, itemName: string, path: string): boolean
	local pathArr = string.split(path, ".")
	local inst: Instance? = GameAssets
	for _, segment in pathArr do
		inst = (inst :: Instance):FindFirstChild(segment)
		if inst == nil then
			warn("GameDataVerifier: missing asset path", itemName, path)
			return false
		end
	end
	return true
end

function GameDataVerifier.verifyCategory(
	self: GameDataVerifier,
	folder: Instance,
	shape: any,
	hasTemplatePaths: boolean
)
	for _, inst in folder:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		local data = require(inst) :: any
		local isValid, err = Validate.isTableShape(data, shape)
		if not isValid then
			warn("GameDataVerifier: invalid vanity data", inst.Name, err)
			continue
		end
		if hasTemplatePaths then
			for _, path in data.templatePaths do
				self:checkAssetPath(data.name, path)
			end
		else
			self:checkAssetPath(data.name, data.templatePath)
		end
		if data.blueprintName then
			if objectDataStore:getObjectDataByName(data.blueprintName) == nil then
				warn("GameDataVerifier: unknown blueprintName", data.name, data.blueprintName)
			end
		end
	end
end

function GameDataVerifier.verifyVanity(self: GameDataVerifier)
	local Vanity = ServerScriptService:WaitForChild("GameData"):WaitForChild("Vanity")

	self:verifyCategory(Vanity:WaitForChild("MainPlotInner"), singlePathShape, false)
	self:verifyCategory(Vanity:WaitForChild("MainPlotOuter"), singlePathShape, false)
	self:verifyCategory(Vanity:WaitForChild("ExpansionInner"), multiPathShape, true)
	self:verifyCategory(Vanity:WaitForChild("ExpansionOuter"), multiPathShape, true)
	self:verifyCategory(Vanity:WaitForChild("Fence"), multiPathShape, true)
end

function GameDataVerifier.verifyLootTableItems(self: GameDataVerifier)
	local LootTables = ServerScriptService:WaitForChild("GameData"):WaitForChild("LootTables")

	for _, inst in LootTables:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end

		local data = require(inst) :: any
		local isArray, err = Validate.isArray(data)
		if not isArray then
			warn("GameDataVerifier: loot table is not an array", inst.Name, err)
			continue
		end

		for i, lootEntry in data do
			local resultCount = (lootEntry.result and 1 or 0)
				+ (lootEntry.resultLootTable and 1 or 0)
				+ (lootEntry.resultLootTables and 1 or 0)
			if resultCount ~= 1 then
				warn(
					"GameDataVerifier: loot entry must have exactly one of result, resultLootTable, resultLootTables",
					inst.Name,
					i
				)
			end

			local ok, shapeErr = Validate.isTableShape(lootEntry, lootEntryShape)
			if not ok then
				warn("GameDataVerifier: invalid loot table entry", inst.Name, i, shapeErr)
				continue
			end

			if lootEntry.result and Validate.isTable(lootEntry.result) and lootEntry.result.itemName then
				if objectDataStore:getObjectDataByName(lootEntry.result.itemName) == nil then
					warn("GameDataVerifier: unknown itemName in loot table", inst.Name, i, lootEntry.result.itemName)
				end
			end
		end
	end
end

function GameDataVerifier.verifyEggLootTables(self: GameDataVerifier)
	local standardLootTables = eggLootTablesData.standardLootTables

	if not Validate.isTable(standardLootTables) or next(standardLootTables) == nil then
		warn("GameDataVerifier: EggLootTables.standardLootTables is missing or empty")
		return
	end

	for tableName, weights in standardLootTables do
		if not Validate.isTable(weights) or next(weights) == nil then
			warn("GameDataVerifier: standardLootTables entry has no weight entries", tableName)
			continue
		end
		for eggName, weight in weights do
			if type(weight) ~= "number" or weight < 0 then
				warn("GameDataVerifier: standardLootTables entry has an invalid weight", tableName, eggName, weight)
			end
			if objectDataStore:getObjectDataByName(eggName) == nil then
				warn("GameDataVerifier: unknown egg name in standardLootTables", tableName, eggName)
			end
		end
	end

	if not standardLootTables[Constants.DEFAULT_STANDARD_LOOT_TABLE_NAME] then
		warn(
			"GameDataVerifier: standardLootTables is missing the reserved default fallback table",
			Constants.DEFAULT_STANDARD_LOOT_TABLE_NAME
		)
	end
end

-- the v1.0 Master Table: every Enums.Rarity needs a complete row, and income, speed, model scale, level cap and
-- time to cap must not decrease as rarity rises (each rarity step is a fixed multiple in the spec)
function GameDataVerifier.verifyRarities(self: GameDataVerifier)
	if type(rarityData.rarities) ~= "table" then
		warn("GameDataVerifier: Control/Rarities needs a rarities table keyed by Enums.Rarity")
		return
	end

	local previousRow: any = nil
	for _, rarity in Enums.getAllValues(Enums.Rarity) do
		local rarityName = Enums.getName(Enums.Rarity, rarity)
		local row = rarityData.rarities[rarity]
		for _, problem in RarityMath.validateRow(row) do
			warn("GameDataVerifier: Rarities", rarityName, problem)
		end

		-- fusionPremium is only for rarities above Common
		if rarity == Enums.Rarity.COMMON and type(row) == "table" and row.fusionPremium ~= nil then
			warn("GameDataVerifier: Rarities Common must not have a fusionPremium (nothing fuses into it)")
		elseif rarity ~= Enums.Rarity.COMMON and type(row) == "table" and row.fusionPremium == nil then
			warn("GameDataVerifier: Rarities", rarityName, "needs a fusionPremium")
		end

		if previousRow and type(row) == "table" and #RarityMath.validateRow(row) == 0 then
			for _, field in
				{
					"hatchOddsN",
					"hatchTimerSec",
					"baseIncome",
					"baseSpeed",
					"modelScale",
					"levelCap",
					"timeToCapSec",
					"xpToCap",
				}
			do
				if row[field] < previousRow[field] then
					warn("GameDataVerifier: Rarities", rarityName, field, "is lower than the previous rarity's")
				end
			end
		end
		if type(row) == "table" and #RarityMath.validateRow(row) == 0 then
			local plotXpPerSec = dragonProgressionData.assignXpPerSec
			if type(plotXpPerSec) == "number" and plotXpPerSec > 0 then
				local expectedSec = row.xpToCap / plotXpPerSec
				if math.abs(row.timeToCapSec - expectedSec) > expectedSec * 0.01 then
					warn(
						"GameDataVerifier: Rarities",
						rarityName,
						"timeToCapSec does not match xpToCap / assignXpPerSec",
						row.timeToCapSec,
						expectedSec
					)
				end
			end
		end
		if type(row) == "table" then
			previousRow = row
		end
	end
end

function GameDataVerifier.verifyEggSizes(self: GameDataVerifier)
	for _, eggName in objectDataStore:getAllObjectNamesByDataKeyValue("type", "dragonEgg") do
		local itemData = objectDataStore:getObjectDataByName(eggName)
		local low = itemData.sizePercentileMin
		local high = itemData.sizePercentileMax
		if (low == nil) ~= (high == nil) then
			warn(
				"GameDataVerifier: egg needs both sizePercentileMin and sizePercentileMax, or neither (Standard 0 to 70)",
				eggName
			)
		elseif low ~= nil and (low > high or high > 100) then
			warn("GameDataVerifier: egg size percentile range must satisfy min <= max <= 100", eggName, low, high)
		end
	end
end

function GameDataVerifier.verifyRebirthLevels(self: GameDataVerifier)
	local previousEggSlots = EggSlotConfig.EGG_SLOT_COUNT
	local previousDragonLimit = EggSlotConfig.DRAGON_LIMIT

	local level = 1
	while rebirthData.levels[level] do
		local levelData = rebirthData.levels[level]
		if levelData.requiredRarity == nil or Enums.getName(Enums.Rarity, levelData.requiredRarity) == nil then
			warn(
				"GameDataVerifier: Rebirth level needs a requiredRarity (use Enums.Rarity)",
				level,
				levelData.requiredRarity
			)
		end
		if
			levelData.bypassCoinCost ~= nil
			and (type(levelData.bypassCoinCost) ~= "number" or levelData.bypassCoinCost <= 0)
		then
			warn(
				"GameDataVerifier: Rebirth level bypassCoinCost must be a number > 0 or absent",
				level,
				levelData.bypassCoinCost
			)
		end

		local eggSlots = rebirthData.levels[level].eggSlots
		if type(eggSlots) ~= "number" or eggSlots ~= math.floor(eggSlots) or eggSlots < previousEggSlots then
			warn(
				"GameDataVerifier: Rebirth level needs an integer eggSlots not below the previous level's",
				level,
				eggSlots,
				previousEggSlots
			)
		else
			previousEggSlots = eggSlots
		end

		local dragonLimit = rebirthData.levels[level].dragonLimit
		if
			type(dragonLimit) ~= "number"
			or dragonLimit ~= math.floor(dragonLimit)
			or dragonLimit < previousDragonLimit
		then
			warn(
				"GameDataVerifier: Rebirth level needs an integer dragonLimit not below the previous level's",
				level,
				dragonLimit,
				previousDragonLimit
			)
		else
			previousDragonLimit = dragonLimit
		end

		level += 1
	end
end

local INDEX_REWARD_FIELDS: { [string]: { string } } = {
	["Income Bonus"] = { "bonusPercent" },
	["Chamber Pull"] = { "lootTableName" },
	["Chest Pull"] = { "lootTableName" },
	["Stat Buff"] = { "attribute", "amount" },
	["Mutation Chance"] = { "amount" },
	["Diamonds"] = { "amount" },
}

local INDEX_REWARD_SIZES: { [string]: boolean } = { small = true, medium = true, large = true }

function GameDataVerifier.verifyIndexRewardEntry(self: GameDataVerifier, label: string, entry: any)
	if type(entry) ~= "table" or type(entry.displayText) ~= "string" or type(entry.reward) ~= "table" then
		warn("GameDataVerifier: Index reward needs a displayText and a reward table", label)
		return
	end

	if entry.reward.icon ~= nil and type(entry.reward.icon) ~= "string" then
		warn("GameDataVerifier: Index reward icon must be an asset id string", label)
	end

	local requiredFields = INDEX_REWARD_FIELDS[entry.reward.rewardType]
	if not requiredFields then
		warn("GameDataVerifier: Index reward has an unknown rewardType", label, entry.reward.rewardType)
		return
	end

	for _, field in requiredFields do
		local value = entry.reward[field]
		local isValid = if field == "lootTableName" or field == "attribute"
			then type(value) == "string"
			else type(value) == "number"
		if not isValid then
			warn("GameDataVerifier: Index reward is missing or has a bad field", label, entry.reward.rewardType, field)
		end
	end

	local diamondAmount = entry.reward.amount
	if entry.reward.rewardType == "Diamonds" and type(diamondAmount) == "number" and (diamondAmount < 1 or diamondAmount ~= math.floor(diamondAmount)) then
		warn("GameDataVerifier: Index Diamonds reward needs a whole amount >= 1", label, diamondAmount)
	end

	if entry.reward.size ~= nil and not INDEX_REWARD_SIZES[entry.reward.size] then
		warn("GameDataVerifier: Index reward has an unknown crate size", label, entry.reward.size)
	end
end

function GameDataVerifier.verifyHatching(self: GameDataVerifier)
	if type(hatchingData.hatchHoldSec) ~= "number" or hatchingData.hatchHoldSec < 0 then
		warn("GameDataVerifier: Hatching needs hatchHoldSec >= 0 (seconds to hold the hatch prompt); using the default", hatchingData.hatchHoldSec)
	end
	if type(hatchingData.skipSecPerDiamond) ~= "number" or hatchingData.skipSecPerDiamond <= 0 then
		warn("GameDataVerifier: Hatching needs skipSecPerDiamond > 0 (hatch seconds one Diamond skips); using the default", hatchingData.skipSecPerDiamond)
	end
end

function GameDataVerifier.verifyIndexRewards(self: GameDataVerifier)
	for category, rarityRows in indexRewardsData.rowRewards or {} do
		local categoryName = Enums.getPublicName(Enums.IndexCategory, category)
		if category ~= Enums.IndexCategory.DRAGON and category ~= Enums.IndexCategory.EGG then
			warn("GameDataVerifier: Index rowRewards only apply to the Dragon and Egg categories", category)
			continue
		end

		for rarity, entry in rarityRows do
			if not Enums.isValidValue(Enums.Rarity, rarity) then
				warn("GameDataVerifier: Index rowRewards has an unknown rarity key", categoryName, rarity)
				continue
			end
			self:verifyIndexRewardEntry(`rowRewards {categoryName} {Enums.getPublicName(Enums.Rarity, rarity)}`, entry)
		end
	end

	if indexRewardsData.useLegacyIndex ~= nil and type(indexRewardsData.useLegacyIndex) ~= "boolean" then
		warn("GameDataVerifier: Index useLegacyIndex must be a boolean")
	end

	if indexRewardsData.singleTierBar ~= nil and type(indexRewardsData.singleTierBar) ~= "boolean" then
		warn("GameDataVerifier: Index singleTierBar must be a boolean")
	end

	local entryRewards = indexRewardsData.entryRewards
	if entryRewards then
		if type(entryRewards.isEnabled) ~= "boolean" then
			warn("GameDataVerifier: Index entryRewards needs a boolean isEnabled")
		end
		for _, currencyField in { "coins", "diamonds" } do
			for category, amounts in entryRewards[currencyField] or {} do
				if not Enums.isValidValue(Enums.IndexCategory, category) then
					warn(`GameDataVerifier: Index entryRewards.{currencyField} has an unknown category key`, category)
				elseif type(amounts) == "table" then
					for rarity, amount in amounts do
						if not Enums.isValidValue(Enums.Rarity, rarity) or type(amount) ~= "number" or amount < 0 then
							warn(
								`GameDataVerifier: Index entryRewards.{currencyField} needs a rarity key and a non-negative amount`,
								category,
								rarity,
								amount
							)
						end
					end
				elseif type(amounts) ~= "number" or amounts < 0 then
					warn(
						`GameDataVerifier: Index entryRewards.{currencyField} needs a non-negative number or a rarity table`,
						category,
						amounts
					)
				end
			end
		end
	end

	for category, tiers in indexRewardsData.categoryTiers or {} do
		local categoryName = Enums.getPublicName(Enums.IndexCategory, category)
		if not Enums.isValidValue(Enums.IndexCategory, category) then
			warn("GameDataVerifier: Index categoryTiers has an unknown category key", category)
			continue
		end

		local previousPercent = 0
		for tierIndex, tier in tiers do
			self:verifyIndexRewardEntry(`categoryTiers {categoryName} {tierIndex}`, tier)

			local requiredPercent = tier.requiredPercent
			if type(requiredPercent) ~= "number" or requiredPercent <= previousPercent or requiredPercent > 100 then
				warn(
					"GameDataVerifier: Index tier needs a requiredPercent above the previous tier's and at most 100",
					categoryName,
					tierIndex,
					requiredPercent
				)
			else
				previousPercent = requiredPercent
			end
		end
	end
end

-- each playtime reward needs a known kind, a positive unlockSec and the fields its kind reads
function GameDataVerifier.verifyPlaytimeRewards(self: GameDataVerifier)
	local rewards = playtimeData.rewards
	if not Validate.isTable(rewards) or #rewards == 0 then
		warn("GameDataVerifier: Playtime.rewards is missing or empty")
		return
	end

	local LootTables = ServerScriptService:WaitForChild("GameData"):WaitForChild("LootTables")
	local kinds = Enums.PlaytimeRewardKind

	for i, entry in rewards do
		if not Validate.isTable(entry) then
			warn("GameDataVerifier: Playtime reward is not a table", i)
			continue
		end
		if not Enums.isValidValue(kinds, entry.kind) then
			warn("GameDataVerifier: Playtime reward has an unknown kind", i, entry.kind)
			continue
		end
		if type(entry.unlockSec) ~= "number" or entry.unlockSec <= 0 then
			warn("GameDataVerifier: Playtime reward needs a positive unlockSec", i, entry.unlockSec)
		end

		if entry.kind == kinds.COINS then
			if type(entry.hourlyPercent) ~= "number" or entry.hourlyPercent < 0 then
				warn("GameDataVerifier: Playtime COINS reward needs hourlyPercent >= 0", i, entry.hourlyPercent)
			end
			if
				type(entry.minCoins) ~= "number"
				or type(entry.maxCoins) ~= "number"
				or entry.minCoins > entry.maxCoins
			then
				warn(
					"GameDataVerifier: Playtime COINS reward needs numeric minCoins <= maxCoins",
					i,
					entry.minCoins,
					entry.maxCoins
				)
			end
		elseif entry.kind == kinds.DIAMONDS then
			if
				type(entry.diamondAmount) ~= "number"
				or entry.diamondAmount < 1
				or entry.diamondAmount ~= math.floor(entry.diamondAmount)
			then
				warn(
					"GameDataVerifier: Playtime DIAMONDS reward needs a whole diamondAmount >= 1",
					i,
					entry.diamondAmount
				)
			end
		elseif entry.kind == kinds.TIME_SKIP then
			if type(entry.skipSec) ~= "number" or entry.skipSec <= 0 then
				warn("GameDataVerifier: Playtime TIME_SKIP reward needs a positive skipSec", i, entry.skipSec)
			end
		elseif entry.kind == kinds.FIXED_ITEM then
			if type(entry.itemName) ~= "string" or objectDataStore:getObjectDataByName(entry.itemName) == nil then
				warn("GameDataVerifier: Playtime FIXED_ITEM reward has an unknown itemName", i, entry.itemName)
			end
		elseif entry.kind == kinds.RANDOM_BY_RARITY then
			local objectType = Enums.ItemType.ObjectTypes[entry.itemType]
			if objectType == nil then
				warn(
					"GameDataVerifier: Playtime RANDOM_BY_RARITY reward has an unknown itemType (use Enums.ItemType)",
					i,
					entry.itemType
				)
				continue
			end
			if not Enums.isValidValue(Enums.Rarity, entry.rarity) then
				warn(
					"GameDataVerifier: Playtime RANDOM_BY_RARITY reward has an unknown rarity (use Enums.Rarity)",
					i,
					entry.rarity
				)
				continue
			end
			local hasMatch = false
			for _, objectName in objectDataStore:getAllObjectNamesByDataKeyValue("type", objectType) do
				if objectDataStore:getObjectDataByName(objectName).rarity == entry.rarity then
					hasMatch = true
					break
				end
			end
			if not hasMatch then
				warn(
					"GameDataVerifier: Playtime RANDOM_BY_RARITY reward matches no object",
					i,
					entry.itemType,
					entry.rarity
				)
			end
		elseif entry.kind == kinds.LOOT_TABLE then
			local lootTableModule = if type(entry.lootTableName) == "string"
				then LootTables:FindFirstChild(entry.lootTableName, true)
				else nil
			if not lootTableModule or not lootTableModule:IsA("ModuleScript") then
				warn(
					"GameDataVerifier: Playtime LOOT_TABLE reward has an unknown lootTableName",
					i,
					entry.lootTableName
				)
				continue
			end
			for lootIndex, lootEntry in require(lootTableModule) :: any do
				if not Validate.isTable(lootEntry.result) or type(lootEntry.result.itemName) ~= "string" then
					warn(
						"GameDataVerifier: Playtime loot table results must be { itemName = string }",
						entry.lootTableName,
						lootIndex
					)
				end
			end
		end
	end
end

-- exactly TILE_COUNT fixed rewards: days 1 to 7 and the repeating last tile; only coins, time skips and items
function GameDataVerifier.verifyDailyLogin(self: GameDataVerifier)
	local rewards = dailyLoginData.rewards
	if not Validate.isTable(rewards) or #rewards ~= DailyLoginMath.TILE_COUNT then
		warn("GameDataVerifier: DailyLogin.rewards must have exactly", DailyLoginMath.TILE_COUNT, "entries")
		return
	end

	local kinds = Enums.PlaytimeRewardKind

	for i, entry in rewards do
		if not Validate.isTable(entry) then
			warn("GameDataVerifier: DailyLogin reward is not a table", i)
			continue
		end

		if entry.kind == kinds.COINS then
			if
				type(entry.minCoins) ~= "number"
				or entry.minCoins < 1
				or entry.minCoins ~= math.floor(entry.minCoins)
			then
				warn("GameDataVerifier: DailyLogin COINS reward needs a whole minCoins >= 1", i, entry.minCoins)
			elseif entry.maxCoins ~= entry.minCoins then
				warn(
					"GameDataVerifier: DailyLogin COINS reward needs maxCoins equal to minCoins (a fixed amount)",
					i,
					entry.minCoins,
					entry.maxCoins
				)
			end
		elseif entry.kind == kinds.DIAMONDS then
			if
				type(entry.diamondAmount) ~= "number"
				or entry.diamondAmount < 1
				or entry.diamondAmount ~= math.floor(entry.diamondAmount)
			then
				warn(
					"GameDataVerifier: DailyLogin DIAMONDS reward needs a whole diamondAmount >= 1",
					i,
					entry.diamondAmount
				)
			end
		elseif entry.kind == kinds.TIME_SKIP then
			if type(entry.skipSec) ~= "number" or entry.skipSec <= 0 then
				warn("GameDataVerifier: DailyLogin TIME_SKIP reward needs a positive skipSec", i, entry.skipSec)
			end
			if
				type(entry.minCoins) ~= "number"
				or entry.minCoins < 1
				or entry.minCoins ~= math.floor(entry.minCoins)
			then
				warn(
					"GameDataVerifier: DailyLogin TIME_SKIP reward needs a whole minCoins >= 1 (paid when income is low)",
					i,
					entry.minCoins
				)
			end
		elseif entry.kind == kinds.FIXED_ITEM then
			if type(entry.itemName) ~= "string" or objectDataStore:getObjectDataByName(entry.itemName) == nil then
				warn("GameDataVerifier: DailyLogin FIXED_ITEM reward has an unknown itemName", i, entry.itemName)
			end
		else
			warn(
				"GameDataVerifier: DailyLogin supports only COINS, DIAMONDS, TIME_SKIP and FIXED_ITEM rewards",
				i,
				entry.kind
			)
		end
	end
end

-- a loot table ModuleScript by name at any depth; a Folder of the same name is skipped (LootTableManager loads
-- ModuleScripts only)
local function findLootTableModule(name: any): ModuleScript?
	if type(name) ~= "string" then
		return nil
	end
	for _, inst in ServerScriptService:WaitForChild("GameData"):WaitForChild("LootTables"):GetDescendants() do
		if inst:IsA("ModuleScript") and inst.Name == name then
			return inst
		end
	end
	return nil
end

-- the wheel: control numbers, product ids, and a loot table whose position is the wheel segment (so no filtering or
-- nesting), holding coin, time skip, fixed item and loot-table (rolled item) prizes
function GameDataVerifier.verifySpinWheel(self: GameDataVerifier)
	local function isWholeNumberAtLeast(value: any, least: number): boolean
		return type(value) == "number" and value >= least and value == math.floor(value)
	end

	if not isWholeNumberAtLeast(spinWheelData.maxAccruedFreeSpins, 1) then
		warn(
			"GameDataVerifier: SpinWheel.maxAccruedFreeSpins must be a whole number >= 1",
			spinWheelData.maxAccruedFreeSpins
		)
	end
	if not isWholeNumberAtLeast(spinWheelData.paidLuckMultiplier, 1) then
		warn(
			"GameDataVerifier: SpinWheel.paidLuckMultiplier must be a whole number >= 1",
			spinWheelData.paidLuckMultiplier
		)
	end
	-- the client's longest spin animation is 4 seconds
	if type(spinWheelData.prizeClaimTimeoutSec) ~= "number" or spinWheelData.prizeClaimTimeoutSec <= 4 then
		warn(
			"GameDataVerifier: SpinWheel.prizeClaimTimeoutSec must exceed the 4s spin animation",
			spinWheelData.prizeClaimTimeoutSec
		)
	end

	local robuxProductIds = spinWheelData.robuxProductIds
	if not Validate.isTable(robuxProductIds) then
		warn("GameDataVerifier: SpinWheel.robuxProductIds is missing; the Robux buttons stay inactive")
	else
		local seen: { [number]: string } = {}
		for _, name in { "single", "singleDiscount", "five" } do
			local id = robuxProductIds[name]
			if id == nil or id == 0 then
				warn(
					"GameDataVerifier: SpinWheel.robuxProductIds has no id for",
					name,
					"(that Robux button stays inactive)"
				)
			elseif not isWholeNumberAtLeast(id, 1) then
				warn("GameDataVerifier: SpinWheel.robuxProductIds has an invalid id for", name, id)
			elseif seen[id] then
				warn("GameDataVerifier: SpinWheel.robuxProductIds reuses an id for", seen[id], "and", name, id)
			else
				seen[id] = name
			end
		end
	end

	-- the verifier runs before LootTableManager loads, so read the module itself
	local lootTableModule = findLootTableModule(spinWheelData.lootTableName)
	if not lootTableModule then
		warn(
			"GameDataVerifier: no ModuleScript named",
			spinWheelData.lootTableName,
			"anywhere under GameData/LootTables (a Folder of that name does not count)"
		)
		return
	end
	local lootTable: any = require(lootTableModule)
	if not Validate.isTable(lootTable) then
		warn(
			"GameDataVerifier: SpinWheel loot table returned a",
			typeof(lootTable),
			"at",
			lootTableModule:GetFullName(),
			"but must return an array"
		)
		return
	elseif #lootTable == 0 then
		warn(
			"GameDataVerifier: SpinWheel loot table has no array entries (a dictionary or empty table?) at",
			lootTableModule:GetFullName()
		)
		return
	end

	local kinds = Enums.PlaytimeRewardKind

	for i, entry in lootTable do
		if not Validate.isTable(entry) or not Validate.isTable(entry.result) then
			warn("GameDataVerifier: SpinWheel loot entry needs a result table", i)
			continue
		end
		if entry.requiredConfig or entry.resultLootTable or entry.resultLootTables then
			warn(
				"GameDataVerifier: SpinWheel loot entry must not use requiredConfig or nested tables (position is the wheel segment)",
				i
			)
		end

		local result = entry.result
		if result.kind == kinds.COINS then
			if not isWholeNumberAtLeast(result.minCoins, 1) or result.maxCoins ~= result.minCoins then
				warn(
					"GameDataVerifier: SpinWheel COINS prize needs a whole minCoins >= 1 and maxCoins equal to it",
					i,
					result.minCoins,
					result.maxCoins
				)
			end
		elseif result.kind == kinds.DIAMONDS then
			if not isWholeNumberAtLeast(result.diamondAmount, 1) then
				warn(
					"GameDataVerifier: SpinWheel DIAMONDS prize needs a whole diamondAmount >= 1",
					i,
					result.diamondAmount
				)
			end
		elseif result.kind == kinds.TIME_SKIP then
			if type(result.skipSec) ~= "number" or result.skipSec <= 0 then
				warn("GameDataVerifier: SpinWheel TIME_SKIP prize needs a positive skipSec", i, result.skipSec)
			end
			if not isWholeNumberAtLeast(result.minCoins, 1) then
				warn(
					"GameDataVerifier: SpinWheel TIME_SKIP prize needs a whole minCoins >= 1 (paid when income is low)",
					i,
					result.minCoins
				)
			end
		elseif result.kind == kinds.FIXED_ITEM then
			if type(result.itemName) ~= "string" or objectDataStore:getObjectDataByName(result.itemName) == nil then
				warn("GameDataVerifier: SpinWheel FIXED_ITEM prize has an unknown itemName", i, result.itemName)
			end
		elseif result.kind == kinds.LOOT_TABLE then
			-- the segment shows displayName; the item is rolled from lootTableName when the spin is decided
			if type(result.displayName) ~= "string" then
				warn("GameDataVerifier: SpinWheel LOOT_TABLE prize needs a displayName", i)
			end
			if result.rarity ~= nil and Enums.getName(Enums.Rarity, result.rarity) == nil then
				warn("GameDataVerifier: SpinWheel LOOT_TABLE prize has an unknown rarity", i, result.rarity)
			end
			if result.iconAssetId ~= nil and type(result.iconAssetId) ~= "string" then
				warn(
					"GameDataVerifier: SpinWheel LOOT_TABLE iconAssetId must be an rbxassetid:// string",
					i,
					result.iconAssetId
				)
			end
			local rolledModule = findLootTableModule(result.lootTableName)
			if not rolledModule then
				warn(
					"GameDataVerifier: SpinWheel LOOT_TABLE prize has an unknown lootTableName",
					i,
					result.lootTableName
				)
				continue
			end
			for rolledIndex, rolledEntry in require(rolledModule) :: any do
				local rolledName = if Validate.isTable(rolledEntry.result) then rolledEntry.result.itemName else nil
				if type(rolledName) ~= "string" or objectDataStore:getObjectDataByName(rolledName) == nil then
					warn(
						"GameDataVerifier: SpinWheel loot table results must be { itemName = an existing object }",
						result.lootTableName,
						rolledIndex,
						rolledName
					)
				end
			end
		else
			warn(
				"GameDataVerifier: SpinWheel supports only COINS, TIME_SKIP, FIXED_ITEM and LOOT_TABLE prizes",
				i,
				result.kind
			)
		end
	end
end

-- Control/EggSpawning: the optional world egg target and the optional loot table per island distance zone
function GameDataVerifier.verifyEggSpawning(self: GameDataVerifier)
	local target = eggSpawningData.targetTotalEggs
	if target ~= nil and (type(target) ~= "number" or target < 0 or target ~= math.floor(target)) then
		warn("GameDataVerifier: EggSpawning.targetTotalEggs must be a whole number >= 0 (0 or missing turns island egg zones off)", target)
	end

	local eggsPerTick = eggSpawningData.refreshEggsPerTick
	if eggsPerTick ~= nil and (type(eggsPerTick) ~= "number" or eggsPerTick < 1) then
		warn("GameDataVerifier: EggSpawning.refreshEggsPerTick must be a number >= 1 (eggs respawned per 0.5 s tick of a global refresh; missing uses 60)", eggsPerTick)
	end

	local zoneLootTables = eggSpawningData.islandZoneLootTables
	if zoneLootTables == nil then
		return
	end
	if type(zoneLootTables) ~= "table" then
		warn("GameDataVerifier: EggSpawning.islandZoneLootTables must be a table from zone name (zone1 to zone4) to a standard egg loot table name")
		return
	end
	for zoneName, lootTableName in zoneLootTables do
		if type(lootTableName) ~= "string" or not eggLootTablesData.standardLootTables[lootTableName] then
			warn("GameDataVerifier: EggSpawning.islandZoneLootTables names an unknown egg loot table", zoneName, lootTableName)
		end
	end
end

function GameDataVerifier.verifyAll(self: GameDataVerifier)
	self:verifyVanity()
	self:verifyLootTableItems()
	self:verifyEggLootTables()
	self:verifyEggSpawning()
	self:verifyRarities()
	self:verifyEggSizes()
	self:verifyRebirthLevels()
	self:verifyHatching()
	self:verifyIndexRewards()
	self:verifyPlaytimeRewards()
	self:verifyDailyLogin()
	self:verifySpinWheel()
end

function GameDataVerifier.new(): GameDataVerifier
	local self: GameDataVerifier = setmetatable({} :: GameDataVerifierFields, GameDataVerifier)
	return self
end

return GameDataVerifier.new()
