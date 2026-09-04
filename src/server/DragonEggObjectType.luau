--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local DragonEggObjectType = {}
DragonEggObjectType.__index = setmetatable(DragonEggObjectType, super)


export type DragonEggObjectType = Types.DragonEggObjectType

function DragonEggObjectType.addDataFromInstances(self: DragonEggObjectType)
	-- egg templates are models; a non-model template crashed here before typing too
	local template = self:getTemplate() :: Model

	-- modelDepth is how far the dragon model extends below the position of the primary part (egg)
	local _, size = template:GetBoundingBox()
	--print("obj", obj, "modelDepth", orientation.Position.Y - size.Y, "pos", orientation.Position.Y, "size", size.Y)
	self.data.modelDepth = size.Y / 2
end

function DragonEggObjectType.new(): DragonEggObjectType
	local self = (setmetatable(ObjectType.new(), DragonEggObjectType) :: any) :: DragonEggObjectType

	self.type = "dragonEgg"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = "string",
		templatePath = "string",
		rarity = {
			type = "enum",
			name = "Rarity",
		},
		primaryElement = {
			type = "enum",
			name = "PrimaryElements",
		},
		sortPriority = "integer",
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		boardSpacing = "nonnegativeNumber",
		capacityCost = "nonnegativeNumber",
		level = "nonnegativeInteger",
		mixins = "table", -- should have more detailed type here

		buy = {
			type = {
				description = "string",
				minElementLevel = "nonnegativeInteger",
				unlockElement = {
					type = "enum",
					name = "PrimaryElements",
					optional = true,
				},
				category = {
					type = "enum",
					name = "ShopCategory",
					optional = true,
				},
				coins = "nonnegativeInteger",
				stock = {
					type = "array",
					elementType = {
						count = "nonnegativeInteger",
						percent = "nonnegativeNumber",
					},
				},
				cameraPosition = {
					type = "array",
					length = 3,
					elementType = "number",
				},
				robuxProductId = {
					type = "nonnegativeInteger",
					optional = true,
				},
				robuxCount = "positiveInteger", -- how many of this item the player gets if they buy this with robux
			},
			optional = true,
		},

		indexCameraPosition = {
			type = "array",
			length = 3,
			elementType = "number",
			optional = true,
		},
	}

	return self
end

return DragonEggObjectType
