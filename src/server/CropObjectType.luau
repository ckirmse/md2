--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local CropObjectType = {}
CropObjectType.__index = setmetatable(CropObjectType, super)


export type CropObjectType = Types.CropObjectType

function CropObjectType.validateInstances(self: CropObjectType): boolean
	if not super.validateInstances(self) then
		return false
	end

	-- the template is set by super.validateInstances, so the cast cannot fail here
	local template = self:getTemplate() :: Instance

	if utils.findFirstDescendant(template, "Hold") == nil then
		warn("Crop is missing a Hold attachment, will not work", template)
		return false
	end

	return true
end

function CropObjectType.new(): CropObjectType
	local self = (setmetatable(ObjectType.new(), CropObjectType) :: any) :: CropObjectType

	self.type = "crop"

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
		food = {
			type = "table", -- should have more detailed type here
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

return CropObjectType
