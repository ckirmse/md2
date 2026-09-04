--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local PackObjectType = {}
PackObjectType.__index = setmetatable(PackObjectType, super)


export type PackObjectType = Types.PackObjectType

function PackObjectType.validateInstances(self: PackObjectType): boolean
	if not super.validateInstances(self) then
		return false
	end

	-- the template is set by super.validateInstances, so the cast cannot fail here
	local template = self:getTemplate() :: Instance

	if utils.findFirstDescendant(template, "Hold") == nil then
		warn("Pack is missing a Hold attachment, will not work", template)
		return false
	end

	return true
end

function PackObjectType.new(): PackObjectType
	local self = (setmetatable(ObjectType.new(), PackObjectType) :: any) :: PackObjectType

	self.type = "pack"

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
		mixins = "table", -- should have more detailed type here
		lootName = "string",
		sortPriority = "integer",
		filterType = {
			type = "string",
			optional = true,
		},

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
				robuxProductId = "nonnegativeInteger",
				robuxCount = "positiveInteger", -- how many of this item the player gets if they buy this with robux
			},
			optional = true,
		},
	}

	return self
end

return PackObjectType
