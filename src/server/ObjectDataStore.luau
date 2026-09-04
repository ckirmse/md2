--!strict

local ObjectDataStore = {}
ObjectDataStore.__index = ObjectDataStore

local BlueprintObjectType = require("./BlueprintObjectType")
local ChestObjectType = require("./ChestObjectType")
local CrateObjectType = require("./CrateObjectType")
local CritterObjectType = require("./CritterObjectType")
local CropObjectType = require("./CropObjectType")
local CrystalObjectType = require("./CrystalObjectType")
local DragonEggObjectType = require("./DragonEggObjectType")
local GemObjectType = require("./GemObjectType")
local KeyObjectType = require("./KeyObjectType")
local NodeObjectType = require("./NodeObjectType")
local PackObjectType = require("./PackObjectType")
local ShadowDragonObjectType = require("./ShadowDragonObjectType")

local ObjectTypeModule = require("./ObjectType")

export type ObjectType = ObjectTypeModule.ObjectType

-- maps the GameData "type" field to the class table used to construct its data type
local dataTypeClassMap: { [string]: any } = {
	blueprint = BlueprintObjectType,
	crop = CropObjectType,
	crystal = CrystalObjectType,
	dragonEgg = DragonEggObjectType,
	gem = GemObjectType,
	key = KeyObjectType,
	pack = PackObjectType,
	shadowDragon = ShadowDragonObjectType,

	chest = ChestObjectType,
	crate = CrateObjectType,
	critter = CritterObjectType,
	node = NodeObjectType,
}

type ObjectDataStoreFields = {
	dataTypes: { [string]: ObjectType },
}

export type ObjectDataStore = typeof(setmetatable({} :: ObjectDataStoreFields, ObjectDataStore))

function ObjectDataStore.getAllObjectNamesByDataKeyValue(self: ObjectDataStore, key: string, value: any): { string }
	local result: { string } = {}
	for objectName, _ in self.dataTypes do
		local objectData = self:getObjectDataByName(objectName)
		if objectData[key] ~= value then
			continue
		end
		table.insert(result, objectName)
	end

	return result
end

function ObjectDataStore.getAllObjectNamesWithDataKeyPath(self: ObjectDataStore, path: string): { string }
	local pathArr = string.split(path, ".")
	local result: { string } = {}
	for objectName, _ in self.dataTypes do
		local objectData = self:getObjectDataByName(objectName)
		local found = true
		local tbl = objectData
		local i = 1
		while i <= #pathArr do
			if not tbl[pathArr[i]] then
				found = false
				break
			end
			tbl = tbl[pathArr[i]]
			i = i + 1
		end
		if not found then
			continue
		end
		table.insert(result, objectName)
	end

	return result
end

function ObjectDataStore.getObjectDataByName(self: ObjectDataStore, objectName: string): any
	local dataType = self.dataTypes[objectName]
	if not dataType then
		warn("cannot find itemType for", objectName)
		return nil
	end

	return dataType:getRawData()
end

function ObjectDataStore.getObjectDataTypeByName(self: ObjectDataStore, objectName: string): ObjectType?
	local dataType = self.dataTypes[objectName]
	if not dataType then
		warn("cannot find itemType for", objectName)
		return nil
	end

	return dataType
end

function ObjectDataStore.initDataTypes(self: ObjectDataStore)
	-- iterate through tree and load all the item data types

	local serverScriptService = game:GetService("ServerScriptService")
	local GameData = serverScriptService:WaitForChild("GameData")
	local Objects = GameData:WaitForChild("Objects")
	for _, inst in Objects:GetDescendants() do
		if not inst:IsA("ModuleScript") then
			continue
		end
		--print("script", inst)
		local data = require(inst) :: any
		if not data.type then
			warn("Invalid object data missing type", inst)
			continue
		end

		if not data.name then
			warn("Invalid object data missing name", inst)
			continue
		end

		--print("got object data", data.type, "name", data.name)

		local dataTypeClass = dataTypeClassMap[data.type]
		if not dataTypeClass then
			warn("unknown object type", data.type, inst)
			continue
		end

		local dataType = dataTypeClass.new()
		dataType:setProperties(data)

		if not dataType:validateData() then
			warn("Invalid data for itemtype, ignoring", inst, data.name)
			continue
		end

		self.dataTypes[data.name] = dataType
	end
end

function ObjectDataStore.init(self: ObjectDataStore)
	for objectName, dataType in self.dataTypes do
		if not dataType:validateInstances() then
			warn("Invalid instances in", objectName)
			continue
		end
		dataType:processInstances()
		dataType:addDataFromInstances()
	end
end

function ObjectDataStore.new(): ObjectDataStore
	local self: ObjectDataStore = setmetatable({
		dataTypes = {},
	} :: ObjectDataStoreFields, ObjectDataStore)

	self:initDataTypes()

	return self
end

local singleton = ObjectDataStore.new()

return singleton
