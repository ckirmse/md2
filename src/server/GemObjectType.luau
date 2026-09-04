--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local GemObjectType = {}
GemObjectType.__index = setmetatable(GemObjectType, super)


export type GemObjectType = Types.GemObjectType

function GemObjectType.addDataFromInstances(self: GemObjectType)
	-- gem templates are parts; a non-part template crashed here before typing too
	local template = self:getTemplate() :: BasePart

	--print("obj", obj, "size X", obj.Size.X, "size Z", obj.Size.Z)
	self.data.modelWidth = math.max(template.Size.X, template.Size.Z) / 2
end

function GemObjectType.new(): GemObjectType
	local self = (setmetatable(ObjectType.new(), GemObjectType) :: any) :: GemObjectType

	self.type = "gem"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		primaryElement = {
			type = "enum",
			name = "PrimaryElements",
		},
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		capacityCost = "nonnegativeNumber",
		mixins = "table", -- should have more detailed type here

		denominations = {
			type = {
				type = "array",
				elementType = {
					itemName = "string",
					value = "nonnegativeInteger",
				},
			},
			optional = true,
		},
	}


	return self
end

return GemObjectType
