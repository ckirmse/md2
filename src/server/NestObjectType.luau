--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local NestObjectType = {}
NestObjectType.__index = setmetatable(NestObjectType, super)


export type NestObjectType = Types.NestObjectType

function NestObjectType.validateInstances(self: NestObjectType): boolean
	if not super.validateInstances(self) then
		return false
	end

	-- the template is set by super.validateInstances, so the cast cannot fail here
	local template = self:getTemplate() :: Instance

	if utils.findFirstDescendant(template, "EggSpawn") == nil then
		warn("Nest is missing an EggSpawn attachment, will not work", template)
		return false
	end

	return true
end

function NestObjectType.new(): NestObjectType
	local self = (setmetatable(ObjectType.new(), NestObjectType) :: any) :: NestObjectType

	self.type = "nest"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		eggItemName = "string",
		respawnSec = "nonnegativeNumber",
	}

	return self
end

return NestObjectType
