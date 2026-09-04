--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local CrateObjectType = {}
CrateObjectType.__index = setmetatable(CrateObjectType, super)


export type CrateObjectType = Types.CrateObjectType

function CrateObjectType.validateInstances(self: CrateObjectType): boolean
	if not super.validateInstances(self) then
		return false
	end

	-- the template is set by super.validateInstances, so the cast cannot fail here
	local template = self:getTemplate() :: Instance

	if utils.findFirstDescendant(template, "Hold") == nil then
		warn("Crate is missing a Hold attachment, will not work", template)
		return false
	end

	return true
end

function CrateObjectType.new(): CrateObjectType
	local self = (setmetatable(ObjectType.new(), CrateObjectType) :: any) :: CrateObjectType

	self.type = "crate"

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
		mixins = "table", -- should have more detailed type here
	}

	return self
end

return CrateObjectType
