--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local CrystalObjectType = {}
CrystalObjectType.__index = setmetatable(CrystalObjectType, super)


export type CrystalObjectType = Types.CrystalObjectType

function CrystalObjectType.validateInstances(self: CrystalObjectType): boolean
	if not super.validateInstances(self) then
		return false
	end

	-- the template is set by super.validateInstances, so the cast cannot fail here
	local template = self:getTemplate() :: Instance

	if utils.findFirstDescendant(template, "Hold") == nil then
		warn("Crystal is missing a Hold attachment, will not work", template)
		return false
	end

	return true
end

function CrystalObjectType.new(): CrystalObjectType
	local self = (setmetatable(ObjectType.new(), CrystalObjectType) :: any) :: CrystalObjectType

	self.type = "crystal"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = {
			type = "string",
			optional = true,
		},
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
		level = "nonnegativeInteger",
		mixins = "table", -- should have more detailed type here

		open = {
			type = {
				minDragonLevel = "nonnegativeInteger",
				durationSec = "nonnegativeNumber",
				lootName = "string",
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

return CrystalObjectType
