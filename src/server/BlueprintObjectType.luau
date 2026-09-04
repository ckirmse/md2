--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local BlueprintObjectType = {}
BlueprintObjectType.__index = setmetatable(BlueprintObjectType, super)


export type BlueprintObjectType = Types.BlueprintObjectType

function BlueprintObjectType.new(): BlueprintObjectType
	local self = (setmetatable(ObjectType.new(), BlueprintObjectType) :: any) :: BlueprintObjectType

	self.type = "blueprint"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = "string",
		templatePath = "string",
		rarity = {
			type = "enum",
			name = "Rarity",
		},
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		boardSpacing = "nonnegativeNumber",
		capacityCost = "nonnegativeNumber",
		mixins = "table", -- should have more detailed type here

		indexCameraPosition = {
			type = "array",
			length = 3,
			elementType = "number",
			optional = true,
		},
	}

	return self
end

return BlueprintObjectType
