--!strict

local GameDataVerifier = {}
GameDataVerifier.__index = GameDataVerifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local EggSlotConfig = require("@game/ReplicatedStorage/Shared/EggSlotConfig")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local eggLootTablesData = require("@game/ServerScriptService/GameData/Control/EggLootTables")
local playtimeData = require("@game/ServerScriptService/GameData/Control/Playtime")
local rebirthData = require("@game/ServerScriptService/GameData/Control/Rebirth")

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

function GameDataVerifier.verifyCategory(self: GameDataVerifier, folder: Instance, shape: any, hasTemplatePaths: boolean)
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
				warn("GameDataVerifier: loot entry must have exactly one of result, resultLootTable, resultLootTables", inst.Name, i)
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

function GameDataVerifier.verifyRebirthLevels(self: GameDataVerifier)
	local previousEggSlots = EggSlotConfig.EGG_SLOT_COUNT
	local previousDragonLimit = EggSlotConfig.DRAGON_LIMIT

	local level = 1
	while rebirthData.levels[level] do
		local eggSlots = rebirthData.levels[level].eggSlots
		if type(eggSlots) ~= "number" or eggSlots ~= math.floor(eggSlots) or eggSlots < previousEggSlots then
			warn("GameDataVerifier: Rebirth level needs an integer eggSlots not below the previous level's", level, eggSlots, previousEggSlots)
		else
			previousEggSlots = eggSlots
		end

		local dragonLimit = rebirthData.levels[level].dragonLimit
		if type(dragonLimit) ~= "number" or dragonLimit ~= math.floor(dragonLimit) or dragonLimit < previousDragonLimit then
			warn("GameDataVerifier: Rebirth level needs an integer dragonLimit not below the previous level's", level, dragonLimit, previousDragonLimit)
		else
			previousDragonLimit = dragonLimit
		end

		level += 1
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
			if type(entry.minCoins) ~= "number" or type(entry.maxCoins) ~= "number" or entry.minCoins > entry.maxCoins then
				warn("GameDataVerifier: Playtime COINS reward needs numeric minCoins <= maxCoins", i, entry.minCoins, entry.maxCoins)
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
				warn("GameDataVerifier: Playtime RANDOM_BY_RARITY reward has an unknown itemType (use Enums.ItemType)", i, entry.itemType)
				continue
			end
			if not Enums.isValidValue(Enums.Rarity, entry.rarity) then
				warn("GameDataVerifier: Playtime RANDOM_BY_RARITY reward has an unknown rarity (use Enums.Rarity)", i, entry.rarity)
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
				warn("GameDataVerifier: Playtime RANDOM_BY_RARITY reward matches no object", i, entry.itemType, entry.rarity)
			end
		elseif entry.kind == kinds.LOOT_TABLE then
			local lootTableModule = if type(entry.lootTableName) == "string" then LootTables:FindFirstChild(entry.lootTableName, true) else nil
			if not lootTableModule or not lootTableModule:IsA("ModuleScript") then
				warn("GameDataVerifier: Playtime LOOT_TABLE reward has an unknown lootTableName", i, entry.lootTableName)
				continue
			end
			for lootIndex, lootEntry in require(lootTableModule) :: any do
				if not Validate.isTable(lootEntry.result) or type(lootEntry.result.itemName) ~= "string" then
					warn("GameDataVerifier: Playtime loot table results must be { itemName = string }", entry.lootTableName, lootIndex)
				end
			end
		end
	end
end

function GameDataVerifier.verifyAll(self: GameDataVerifier)
	self:verifyVanity()
	self:verifyLootTableItems()
	self:verifyEggLootTables()
	self:verifyRebirthLevels()
	self:verifyPlaytimeRewards()
end

function GameDataVerifier.new(): GameDataVerifier
	local self: GameDataVerifier = setmetatable({} :: GameDataVerifierFields, GameDataVerifier)
	return self
end

return GameDataVerifier.new()
