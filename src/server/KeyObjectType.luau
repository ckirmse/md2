--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local KeyObjectType = {}
KeyObjectType.__index = setmetatable(KeyObjectType, super)


export type KeyObjectType = Types.KeyObjectType

function KeyObjectType.new(): KeyObjectType
	local self = (setmetatable(ObjectType.new(), KeyObjectType) :: any) :: KeyObjectType

	self.type = "key"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = "string",
		templatePath = "string",
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		boardSpacing = "nonnegativeNumber",
		capacityCost = "nonnegativeNumber",
		level = "nonnegativeInteger",
		mixins = "table", -- should have more detailed type here
	}

	return self
end

return KeyObjectType
