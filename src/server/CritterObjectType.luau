--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local CritterObjectType = {}
CritterObjectType.__index = setmetatable(CritterObjectType, super)


export type CritterObjectType = Types.CritterObjectType

function CritterObjectType.new(): CritterObjectType
	local self = (setmetatable(ObjectType.new(), CritterObjectType) :: any) :: CritterObjectType

	self.type = "critter"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		casterPath = "string",
		crateTemplatePath = "string",
		minRadius = "nonnegativeNumber",
		maxRadius = "nonnegativeNumber",
		minPeriod = "positiveNumber",
		maxPeriod = "positiveNumber",
		lootName = "string",
	}

	return self
end

return CritterObjectType
