--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local GuardianObjectType = {}
GuardianObjectType.__index = setmetatable(GuardianObjectType, super)


export type GuardianObjectType = Types.GuardianObjectType

function GuardianObjectType.new(): GuardianObjectType
	local self = (setmetatable(ObjectType.new(), GuardianObjectType) :: any) :: GuardianObjectType

	self.type = "guardian"

	self.dataTableShape = {
		type = "string",
		name = "string",
		templatePath = "string",
		biomeIndex = "positiveInteger",
		spawnMarkerName = "string",
		telegraphSec = "nonnegativeNumber",
		chaseMaxSec = "nonnegativeNumber",
		chaseSpeedMultiplier = "nonnegativeNumber",
		catchDistance = "nonnegativeNumber",
		wakeCheckIntervalSec = "nonnegativeNumber",
		returnSpeed = "nonnegativeNumber",
		stunSec = "nonnegativeNumber",
	}

	return self
end

return GuardianObjectType
