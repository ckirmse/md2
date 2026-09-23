--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local ScatterZoneObjectType = {}
ScatterZoneObjectType.__index = setmetatable(ScatterZoneObjectType, super)


export type ScatterZoneObjectType = Types.ScatterZoneObjectType

-- no cloned template, so skip ObjectType's template resolution
function ScatterZoneObjectType.validateInstances(self: ScatterZoneObjectType): boolean
	return true
end

function ScatterZoneObjectType.processInstances(self: ScatterZoneObjectType) end

function ScatterZoneObjectType.new(): ScatterZoneObjectType
	local self = (setmetatable(ObjectType.new(), ScatterZoneObjectType) :: any) :: ScatterZoneObjectType

	self.type = "scatterZone"

	self.dataTableShape = {
		type = "string",
		name = "string",
		respawnSec = "nonnegativeNumber",
		maxEggsInZone = "nonnegativeInteger",
		minEggSpacing = "nonnegativeNumber",
	}

	return self
end

return ScatterZoneObjectType
