--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local ChestObjectType = {}
ChestObjectType.__index = setmetatable(ChestObjectType, super)


export type ChestObjectType = Types.ChestObjectType

function ChestObjectType.addDataFromInstances(self: ChestObjectType)
	-- chest templates are models with a primary part; a missing one crashed here before typing too
	local template = self:getTemplate() :: Model

	-- modelDepth is how far the model extends below the position of the primary part
	local size = (template.PrimaryPart :: BasePart).Size
	--print("obj", obj, "modelDepth", orientation.Position.Y - size.Y, "pos", orientation.Position.Y, "size", size.Y)
	self.data.modelDepth = size.Y / 2
end


function ChestObjectType.new(): ChestObjectType
	local self = (setmetatable(ObjectType.new(), ChestObjectType) :: any) :: ChestObjectType

	self.type = "chest"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		level = "positiveInteger",
		lootName = "string",
	}

	return self
end

return ChestObjectType
