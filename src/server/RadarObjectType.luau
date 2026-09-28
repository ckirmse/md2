--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local RadarObjectType = {}
RadarObjectType.__index = setmetatable(RadarObjectType, super)


export type RadarObjectType = Types.RadarObjectType

function RadarObjectType.addDataFromInstances(self: RadarObjectType)
	-- item rarity always matches the egg rarity a radar searches for
	self.data.rarity = self.data.targetRarity
end

function RadarObjectType.new(): RadarObjectType
	local self = (setmetatable(ObjectType.new(), RadarObjectType) :: any) :: RadarObjectType

	self.type = "radar"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = "string",
		templatePath = "string",
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

		-- the rarity of special egg this radar tier searches for
		targetRarity = {
			type = "enum",
			name = "Rarity",
		},
		-- max search distance, in studs, from the activating player
		range = "nonnegativeNumber",
		-- how long the client-side directional guidance stays up after a successful search
		guidanceDurationSec = "nonnegativeNumber",

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

return RadarObjectType
