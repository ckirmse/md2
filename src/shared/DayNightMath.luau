--!strict

-- Pure day/night math. The phase is a function of server time, so every client and the server agree with no state or
-- remote. A cycle is a day of dayDurationSec followed by a night of nightDurationSec.
local DayNightMath = {}

export type LightLook = {
	clockTime: number,
	brightness: number,
	outdoorAmbient: Color3,
}

export type EggLight = {
	brightness: number,
	range: number,
	color: Color3,
}

export type DayNightConfig = {
	isEnabled: boolean,
	dayDurationSec: number,
	nightDurationSec: number,
	fadeSec: number,
	day: LightLook,
	night: LightLook,
	eggLight: EggLight,
}

export type Phase = {
	isNight: boolean,
	remainingSec: number,
}

function DayNightMath.getPhase(serverTime: number, dayDurationSec: number, nightDurationSec: number, offsetSec: number): Phase
	local cycleSec = dayDurationSec + nightDurationSec
	local position = (serverTime + offsetSec) % cycleSec
	local isNight = position >= dayDurationSec

	return {
		isNight = isNight,
		remainingSec = if isNight then cycleSec - position else dayDurationSec - position,
	}
end

-- the master switch: with the cycle disabled it is always day, with nothing remaining
function DayNightMath.getState(config: DayNightConfig, serverTime: number, offsetSec: number): Phase
	if not config.isEnabled then
		return { isNight = false, remainingSec = 0 }
	end

	return DayNightMath.getPhase(serverTime, config.dayDurationSec, config.nightDurationSec, offsetSec)
end

function DayNightMath.isNight(config: DayNightConfig, serverTime: number, offsetSec: number): boolean
	return DayNightMath.getState(config, serverTime, offsetSec).isNight
end

-- the offset that makes `serverTime` the start of a day or a night
function DayNightMath.getOffsetForPhase(serverTime: number, dayDurationSec: number, nightDurationSec: number, isNight: boolean): number
	local target = if isNight then dayDurationSec else 0

	return (target - serverTime) % (dayDurationSec + nightDurationSec)
end

local function validateLook(look: any, name: string): string?
	if type(look) ~= "table" then
		return name .. " must be a table"
	end
	if type(look.clockTime) ~= "number" or look.clockTime < 0 or look.clockTime > 24 then
		return name .. ".clockTime must be a number from 0 to 24"
	end
	if type(look.brightness) ~= "number" or look.brightness < 0 then
		return name .. ".brightness must be a number >= 0"
	end
	if typeof(look.outdoorAmbient) ~= "Color3" then
		return name .. ".outdoorAmbient must be a Color3"
	end

	return nil
end

-- returns an error message, or nil when the config is valid
function DayNightMath.validateConfig(config: any): string?
	if type(config) ~= "table" then
		return "config must be a table"
	end
	if type(config.isEnabled) ~= "boolean" then
		return "isEnabled must be true or false"
	end
	if type(config.dayDurationSec) ~= "number" or config.dayDurationSec <= 0 then
		return "dayDurationSec must be a number > 0"
	end
	if type(config.nightDurationSec) ~= "number" or config.nightDurationSec <= 0 then
		return "nightDurationSec must be a number > 0"
	end
	if type(config.fadeSec) ~= "number" or config.fadeSec < 0 then
		return "fadeSec must be a number >= 0"
	end

	local dayError = validateLook(config.day, "day")
	if dayError then
		return dayError
	end
	local nightError = validateLook(config.night, "night")
	if nightError then
		return nightError
	end

	local eggLight = config.eggLight
	if type(eggLight) ~= "table" then
		return "eggLight must be a table"
	end
	if type(eggLight.brightness) ~= "number" or eggLight.brightness < 0 then
		return "eggLight.brightness must be a number >= 0"
	end
	if type(eggLight.range) ~= "number" or eggLight.range <= 0 then
		return "eggLight.range must be a number > 0"
	end
	if typeof(eggLight.color) ~= "Color3" then
		return "eggLight.color must be a Color3"
	end

	return nil
end

return DayNightMath
