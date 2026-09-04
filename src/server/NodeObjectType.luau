--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local NodeObjectType = {}
NodeObjectType.__index = setmetatable(NodeObjectType, super)


export type NodeObjectType = Types.NodeObjectType

function NodeObjectType.addDataFromInstances(self: NodeObjectType)
	-- node templates are models with a primary part; a missing one crashed here before typing too
	local template = self:getTemplate() :: Model

	-- modelDepth is how far the model extends below the position of the primary part
	local size = (template.PrimaryPart :: BasePart).Size
	--print("obj", obj, "modelDepth", orientation.Position.Y - size.Y, "pos", orientation.Position.Y, "size", size.Y)
	self.data.modelDepth = size.Y / 2
end


function NodeObjectType.new(): NodeObjectType
	local self = (setmetatable(ObjectType.new(), NodeObjectType) :: any) :: NodeObjectType

	self.type = "node"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		lootName = "string",
		targetSize = "nonnegativeNumber",
		primaryElement = {
			type = "enum",
			name = "PrimaryElements",
		},

		animation = {
			type = "table", -- should have more detailed type here
			optional = true,
		},
	}

	return self
end

return NodeObjectType
