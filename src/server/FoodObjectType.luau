--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local FoodObjectType = {}
FoodObjectType.__index = setmetatable(FoodObjectType, super)


export type FoodObjectType = Types.FoodObjectType

function FoodObjectType.new(): FoodObjectType
	local self = (setmetatable(ObjectType.new(), FoodObjectType) :: any) :: FoodObjectType

	self.type = "food"

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
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		boardSpacing = "nonnegativeNumber",
		capacityCost = "nonnegativeNumber",
		sortPriority = "integer",
		mixins = "table", -- should have more detailed type here

		-- how much dragon XP one use of this food grants
		foodXp = "nonnegativeNumber",

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
				robuxCount = {
					type = "positiveInteger", -- how many of this item the player gets if they buy this with robux
					optional = true,
				},
			},
			optional = true,
		},
	}

	return self
end

return FoodObjectType
