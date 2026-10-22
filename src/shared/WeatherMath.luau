--!strict

-- Pure weather math: config validation and the era roll (seeded by the era, at most one event per era).
local DayNightMath = require("./DayNightMath")
local Enums = require("./Enums")
local WeatherStrike = require("./WeatherStrike")

local WeatherMath = {}

export type WeatherLighting = DayNightMath.WeatherLighting

export type CosmicEgg = {
	eggName: string,
	rollIntervalSec: number,
	chance: number,
	announcement: string?,
}

export type WeatherEvent = {
	weather: number,
	displayName: string,
	description: string,
	iconAssetId: string,
	startChance: number,
	durationMin: number,
	durationMax: number,
	startCondition: number,
	trait: number,
	traitChance: number,
	templatePath: string?,
	lighting: WeatherLighting?,
	lockNight: boolean?,
	startMessage: string?,
	strikeSpreadSec: number?,
	cosmicEgg: CosmicEgg?,
}

export type WeatherConfig = {
	useLegacyWeather: boolean,
	rollIntervalSec: number,
	weatherEvents: { WeatherEvent },
}

export type EraPlan = {
	event: WeatherEvent,
	startTime: number,
	endTime: number,
}

local function isPercent(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 100
end

local function validateEvent(event: any, label: string): string?
	if type(event) ~= "table" then
		return label .. " must be a table"
	end
	if not Enums.validateValue(Enums.Weather, event.weather) then
		return label .. ".weather must be an Enums.Weather value"
	end
	if type(event.displayName) ~= "string" or event.displayName == "" then
		return label .. ".displayName must be a non-empty string"
	end
	if type(event.description) ~= "string" then
		return label .. ".description must be a string"
	end
	if type(event.iconAssetId) ~= "string" then
		return label .. ".iconAssetId must be a string (empty for no icon)"
	end
	if not isPercent(event.startChance) then
		return label .. ".startChance must be a number from 0 to 100"
	end
	if type(event.durationMin) ~= "number" or event.durationMin <= 0 then
		return label .. ".durationMin must be a number > 0"
	end
	if type(event.durationMax) ~= "number" or event.durationMax < event.durationMin then
		return label .. ".durationMax must be a number >= durationMin"
	end
	if not Enums.validateValue(Enums.WeatherStartCondition, event.startCondition) then
		return label .. ".startCondition must be an Enums.WeatherStartCondition value"
	end
	if not Enums.validateValue(Enums.Trait, event.trait) then
		return label .. ".trait must be an Enums.Trait value"
	end
	if not isPercent(event.traitChance) then
		return label .. ".traitChance must be a number from 0 to 100"
	end
	if event.templatePath ~= nil and type(event.templatePath) ~= "string" then
		return label .. ".templatePath must be a string"
	end
	if event.lockNight ~= nil and type(event.lockNight) ~= "boolean" then
		return label .. ".lockNight must be true or false"
	end
	if event.startMessage ~= nil and type(event.startMessage) ~= "string" then
		return label .. ".startMessage must be a string"
	end
	if event.strikeSpreadSec ~= nil and (type(event.strikeSpreadSec) ~= "number" or event.strikeSpreadSec < 0) then
		return label .. ".strikeSpreadSec must be a number >= 0"
	end
	if event.strikeSpreadSec ~= nil then
		if WeatherStrike.TRAIT_DELAY_SEC[event.weather] == nil then
			return label .. ".strikeSpreadSec is only supported for Thunderstorm and Starlight"
		end
		if event.strikeSpreadSec >= event.durationMin then
			return label .. ".strikeSpreadSec must be shorter than durationMin"
		end
	end

	local cosmicEgg = event.cosmicEgg
	if cosmicEgg ~= nil then
		if event.weather ~= Enums.Weather.STARLIGHT then
			return label .. ".cosmicEgg is only supported for Starlight"
		end
		if type(cosmicEgg) ~= "table" then
			return label .. ".cosmicEgg must be a table"
		end
		if type(cosmicEgg.eggName) ~= "string" or cosmicEgg.eggName == "" then
			return label .. ".cosmicEgg.eggName must be a non-empty string"
		end
		if type(cosmicEgg.rollIntervalSec) ~= "number" or cosmicEgg.rollIntervalSec <= 0 then
			return label .. ".cosmicEgg.rollIntervalSec must be a number > 0"
		end
		if not isPercent(cosmicEgg.chance) then
			return label .. ".cosmicEgg.chance must be a number from 0 to 100"
		end
		if cosmicEgg.announcement ~= nil and type(cosmicEgg.announcement) ~= "string" then
			return label .. ".cosmicEgg.announcement must be a string"
		end
	end

	local lighting = event.lighting
	if lighting ~= nil then
		if type(lighting) ~= "table" then
			return label .. ".lighting must be a table"
		end
		if lighting.brightness ~= nil and (type(lighting.brightness) ~= "number" or lighting.brightness < 0) then
			return label .. ".lighting.brightness must be a number >= 0"
		end
		if lighting.outdoorAmbient ~= nil and typeof(lighting.outdoorAmbient) ~= "Color3" then
			return label .. ".lighting.outdoorAmbient must be a Color3"
		end
	end

	return nil
end

function WeatherMath.validateConfig(config: any): string?
	if type(config) ~= "table" then
		return "config must be a table"
	end
	if type(config.useLegacyWeather) ~= "boolean" then
		return "useLegacyWeather must be true or false"
	end
	if config.useLegacyWeather then
		return nil
	end
	if type(config.rollIntervalSec) ~= "number" or config.rollIntervalSec <= 0 then
		return "rollIntervalSec must be a number > 0"
	end
	if type(config.weatherEvents) ~= "table" or #config.weatherEvents == 0 then
		return "weatherEvents must be a non-empty array"
	end

	local seen: { [number]: boolean } = {}
	for i, event in config.weatherEvents do
		local label = "weatherEvents[" .. tostring(i) .. "]"
		local errorMessage = validateEvent(event, label)
		if errorMessage then
			return errorMessage
		end
		if seen[event.weather] then
			return label .. " repeats weather " .. tostring(event.weather)
		end
		seen[event.weather] = true
	end

	return nil
end

function WeatherMath.findStartTime(
	startCondition: number,
	dayNight: DayNightMath.DayNightConfig,
	eraStart: number,
	eraEnd: number
): number?
	if startCondition == Enums.WeatherStartCondition.ANY then
		return eraStart
	end

	local wantNight = startCondition == Enums.WeatherStartCondition.NIGHT
	if not dayNight.isEnabled then
		return if wantNight then nil else eraStart
	end

	local time = eraStart
	while time < eraEnd do
		local phase = DayNightMath.getPhase(time, dayNight.dayDurationSec, dayNight.nightDurationSec, 0)
		if phase.isNight == wantNight then
			return time
		end
		time += phase.remainingSec + 0.001
	end

	return nil
end

function WeatherMath.planEra(config: WeatherConfig, dayNight: DayNightMath.DayNightConfig, eraStart: number): EraPlan?
	local random = Random.new(eraStart)

	local chosen: WeatherEvent? = nil
	local chosenDuration = 0
	for _, event in config.weatherEvents do
		local roll = random:NextNumber(0, 100)
		local duration = random:NextNumber(event.durationMin, event.durationMax)
		if chosen == nil and roll < event.startChance then
			chosen = event
			chosenDuration = duration
		end
	end
	if not chosen then
		return nil
	end

	local startTime = WeatherMath.findStartTime(chosen.startCondition, dayNight, eraStart, eraStart + config.rollIntervalSec)
	if not startTime then
		return nil
	end

	return {
		event = chosen,
		startTime = startTime,
		endTime = startTime + chosenDuration,
	}
end

return WeatherMath
