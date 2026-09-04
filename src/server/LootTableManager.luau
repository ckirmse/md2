--!strict

local LootTableManager = {}
LootTableManager.__index = LootTableManager

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

-- loot tables come straight from GameData modules, so entries stay untyped
type LootTableManagerFields = {
	random: Random,
	lootTables: { [string]: any },
}

export type LootTableManager = typeof(setmetatable({} :: LootTableManagerFields, LootTableManager))

-- returns map from result to fraction, for displaying percentages (compliance)
function LootTableManager.GetLootFractionTable(self: LootTableManager, lootTableName: string): { [any]: number }
	local lootTable = self:getLootTable(lootTableName)

	if not lootTable or #lootTable == 0 then
		warn("loot table not found", lootTableName)
		return {}
	end

	local fractionTable: { [any]: number } = {}

	local filteredLootTable = self:getFilteredLootTable(lootTable)
	lootTable = nil -- so it's not accidentally used

	local totalWeight = 0
	for _, lootEntry in filteredLootTable do
		totalWeight += lootEntry.weight
	end

	for _, lootEntry in filteredLootTable do
		fractionTable[lootEntry.result] = lootEntry.weight / totalWeight
	end

	return fractionTable
end

function LootTableManager.findLootTableEntryWithResultField(self: LootTableManager, lootTableName: string, key: string, value: any): any
	local lootTable = self:getLootTable(lootTableName)

	if not lootTable or #lootTable == 0 then
		warn("invalid loot table", lootTableName)
		return {}
	end

	for _, lootEntry in lootTable do
		if lootEntry.result[key] == value then
			return lootEntry
		end
	end

	warn("loot table entry not found", lootTableName, key, value)

	return nil
end

function LootTableManager.getLootTable(self: LootTableManager, lootTableName: string): any
	return self.lootTables[lootTableName]
end


function LootTableManager.getFilteredLootTable(self: LootTableManager, lootTable: any): { any }
	-- take out anything turned off by config
	local filteredLootTable: { any } = {}
	for _, lootEntry in lootTable do
		if lootEntry.requiredConfig then
			if not gameController:getConfigValue(lootEntry.requiredConfig) then
				--print("skipping loot possibility", lootEntry)
				continue
			end
		end
		table.insert(filteredLootTable, lootEntry)
	end
	return filteredLootTable
end

function LootTableManager.calculateLootResultsByTableAndRandom(self: LootTableManager, lootTable: any, random: Random): { any }
	local filteredLootTable = self:getFilteredLootTable(lootTable)
	lootTable = nil -- so it's not accidentally used

	local totalWeight = 0
	for _, lootEntry in filteredLootTable do
		totalWeight += lootEntry.weight
	end

	local roll = random:NextNumber(0, totalWeight)
	--print("rolled between 0", totalWeight, "got roll", roll)
	local currentWeight = 0
	local lootEntries: { any } = {}

	for _, lootEntry in filteredLootTable do
		currentWeight += lootEntry.weight
		if roll > currentWeight then
			continue
		end

		if lootEntry.result then
			table.insert(lootEntries, lootEntry)
		end
		if lootEntry.resultLootTable then
			for i = 1, lootEntry.resultLootTable.count do
				local additionalLootEntries = self:calculateLootResultsWithRandom(lootEntry.resultLootTable.lootTableName, random)
				for _, additionalLootEntry in additionalLootEntries do
					--print("adding an additional", additionalLootEntry)
					table.insert(lootEntries, additionalLootEntry)
				end
			end
		end
		if lootEntry.resultLootTables then
			for _, resultLootTable in lootEntry.resultLootTables do
				for i = 1, resultLootTable.count do
					local additionalLootEntries = self:calculateLootResultsWithRandom(resultLootTable.lootTableName, random)
					for _, additionalLootEntry in additionalLootEntries do
						--print("adding an additional", additionalLootEntry)
						table.insert(lootEntries, additionalLootEntry)
					end
				end
			end
		end
		break
	end

	return lootEntries
end

function LootTableManager.calculateLootResultsByTable(self: LootTableManager, lootTable: any): { any }
	return self:calculateLootResultsByTableAndRandom(lootTable, self.random)
end

function LootTableManager.calculateLootResultsWithRandom(self: LootTableManager, lootTableName: string, random: Random): { any }
	local lootTable = self:getLootTable(lootTableName)

	if not lootTable or #lootTable == 0 then
		warn("loot table not found", lootTableName)
		return {}
	end

	return self:calculateLootResultsByTableAndRandom(lootTable, random)
end

function LootTableManager.calculateLootResults(self: LootTableManager, lootTableName: string): { any }
	return self:calculateLootResultsWithRandom(lootTableName, self.random)
end

-- returns map from itemName to count
function LootTableManager.getItemCreationDataFromItemLootResults(self: LootTableManager, lootEntries: { any }): { [string]: number }
	local retval: { [string]: number } = {}
	for _, lootEntry in lootEntries do
		local itemName = lootEntry.result.itemName
		if not retval[itemName] then
			retval[itemName] = 0
		end
		retval[itemName] += lootEntry.result.count
	end

	return retval
end

function LootTableManager.init(self: LootTableManager)
	-- iterate through tree and load all the loot table data

	local serverScriptService = game:GetService("ServerScriptService")
	local GameData = serverScriptService:WaitForChild("GameData")
	local LootTableManagerFolder = GameData:WaitForChild("LootTables")
	for _, inst in LootTableManagerFolder:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		--print("script", inst)
		local data = require(inst) :: any
		if typeof(data) ~= "table" then
			warn("loot table data is not a table", inst)
			continue
		end

		self.lootTables[inst.Name] = data
	end
end

function LootTableManager.new(): LootTableManager
	local self: LootTableManager = setmetatable({
		random = Random.new(),

		lootTables = {},
	} :: LootTableManagerFields, LootTableManager)

	return self
end

function LootTableManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = LootTableManager.new()

return singleton
