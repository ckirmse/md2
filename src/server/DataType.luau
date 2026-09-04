--!strict

local DataType = {}
DataType.__index = DataType

local Validate = require("./Validate")
local Types = require("./Types")


export type DataTypeFields = Types.DataTypeFields
export type DataType = Types.DataType

function DataType.setProperties(self: DataType, data: any)
	self.data = data

	-- shove "type" in here
	self.data.type = self.type
end

function DataType.getRawData(self: DataType): any
	return self.data
end

function DataType.validateData(self: DataType): boolean
	local isValid, err = Validate.isTableShape(self.data, self.dataTableShape)
	if not isValid then
		warn("fail to validate data type", self.type, self.dataTableShape, err)
	end

	return isValid
end

function DataType.validateInstances(self: DataType): boolean
	return true
end

function DataType.processInstances(self: DataType)
end

function DataType.addDataFromInstances(self: DataType)
end

function DataType.new(): DataType
	local self: DataType = setmetatable({
		type = "dataType",

		required = {},
		optional = {},

		data = nil,
	} :: DataTypeFields, DataType) :: any

	return self
end

return DataType
