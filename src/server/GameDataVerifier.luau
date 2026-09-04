--!strict

local GameDataVerifier = {}
GameDataVerifier.__index = GameDataVerifier

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

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

function GameDataVerifier.verifyAll(self: GameDataVerifier)
	self:verifyVanity()
	self:verifyLootTableItems()
end

function GameDataVerifier.new(): GameDataVerifier
	local self: GameDataVerifier = setmetatable({} :: GameDataVerifierFields, GameDataVerifier)
	return self
end

return GameDataVerifier.new()
