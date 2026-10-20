--!strict

local DayNightManager = {}
DayNightManager.__index = DayNightManager

local dayNightData = require("@game/ServerScriptService/GameData/Control/DayNight")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local DayNightMath = require("@game/ReplicatedStorage/Shared/DayNightMath")

type DayNightManagerFields = {
	config: DayNightMath.DayNightConfig,
}

export type DayNightManager = typeof(setmetatable({} :: DayNightManagerFields, DayNightManager))

local function getOffsetSec(): number
	return (workspace:GetAttribute(Attributes.DAY_NIGHT_OFFSET_SEC) :: number?) or 0
end

function DayNightManager.isNight(self: DayNightManager): boolean
	return DayNightMath.isNight(self.config, workspace:GetServerTimeNow(), getOffsetSec())
end

function DayNightManager.getClientConfig(self: DayNightManager): DayNightMath.DayNightConfig
	return self.config
end

-- dev only: shifts the shared clock so the current moment starts a day or a night; clients read the same attribute
function DayNightManager.devSetPhase(self: DayNightManager, isNight: boolean)
	local offsetSec = DayNightMath.getOffsetForPhase(workspace:GetServerTimeNow(), self.config.dayDurationSec, self.config.nightDurationSec, isNight)
	workspace:SetAttribute(Attributes.DAY_NIGHT_OFFSET_SEC, offsetSec)
end

function DayNightManager.devReset(self: DayNightManager)
	workspace:SetAttribute(Attributes.DAY_NIGHT_OFFSET_SEC, nil)
end

function DayNightManager.init(self: DayNightManager)
	local errorMessage = DayNightMath.validateConfig(dayNightData)
	if errorMessage then
		error("DayNightManager: Control/DayNight is invalid: " .. errorMessage)
	end

	self.config = dayNightData :: DayNightMath.DayNightConfig
end

function DayNightManager.new(): DayNightManager
	local self = setmetatable({} :: DayNightManagerFields, DayNightManager)
	return self
end

local singleton = DayNightManager.new()

return singleton
