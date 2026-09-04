--!strict

local BaseObject = {}
BaseObject.__index = BaseObject

local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")


export type BaseObjectFields = Types.BaseObjectFields
export type BaseObject = Types.BaseObject

function BaseObject.getObj(self: BaseObject): any
	return self.obj
end

function BaseObject.getObjectId(self: BaseObject): number
	return self.objectId
end

function BaseObject.getObjectName(self: BaseObject): string
	return self.objectName
end

function BaseObject.getObjectData(self: BaseObject): any
	return objectDataStore:getObjectDataByName(self.objectName)
end

function BaseObject.destroy(self: BaseObject)
	if self.obj then
		self.obj:Destroy()
		self.obj = nil
	end
end

function BaseObject.new(objectData: any, cframe: CFrame, objectId: number): BaseObject
	local self: BaseObject = setmetatable({
		objectName = objectData.name,
		objectId = objectId,
	} :: BaseObjectFields, BaseObject) :: any

	local objectDataType = objectDataStore:getObjectDataTypeByName(self.objectName) :: any

	self.obj = objectDataType:getTemplate():Clone()
	self.obj:PivotTo(cframe)

	return self
end

return BaseObject
