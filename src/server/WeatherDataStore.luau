--!strict

local WeatherDataStore = {}
WeatherDataStore.__index = WeatherDataStore

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weather = ReplicatedStorage:WaitForChild("Weather")

local enums = require("@game/ReplicatedStorage/Shared/Enums")

export type WorldLightingData = {
	Brightness: number,
	OutdoorAmbient: Color3,
}

export type WeatherData = {
	name: string,
	description: string,
	templatePath: string,
	percent: number,
	duration: {
		min: number,
		max: number,
	},
	worldLighting: WorldLightingData?,
	effect: {
		sec: number,
		apply: {
			count: number,
			modification: number,
		},
	},
	iconAssetId: string,
	-- resolved from templatePath by tryInitData
	template: Instance?,
}

type WeatherDataStoreFields = {
	weatherDatas: { WeatherData },
}

export type WeatherDataStore = typeof(setmetatable({} :: WeatherDataStoreFields, WeatherDataStore))

local defaultWorldLightingData: WorldLightingData = {
	Brightness = 2,
	OutdoorAmbient = Color3.fromRGB(70, 70, 70)
}

local weatherDatas: { WeatherData } = {
	{
		name = "Rain",
		description = "It is raining, increasing chance of wet crops and dragons",
		templatePath = "Rain",
		percent = 6,
		duration = {
			min = 180,
			max = 299,
		},
		effect = {
			sec = 60,
			apply = {
				count = 1,
				modification = enums.Modifications.WET,
			}
		},
		iconAssetId = "99655556568512",
	},
	{
		name = "Bloom",
		description = "The weather is beautiful and everything is blooming",
		templatePath = "Bloom",
		percent = 6,
		duration = {
			min = 180,
			max = 299,
		},
		effect = {
			sec = 60,
			apply = {
				count = 1,
				modification = enums.Modifications.BLOOM,
			}
		},
		iconAssetId = "72818048070654",
	},
	{
		name = "Wind",
		description = "The wind is coming through the area with intensity",
		templatePath = "Wind",
		percent = 6,
		duration = {
			min = 180,
			max = 299,
		},
		effect = {
			sec = 60,
			apply = {
				count = 1,
				modification = enums.Modifications.WINDY,
			}
		},
		iconAssetId = "115402201084939",
	},
	{
		name = "Heat",
		description = "The sun is intense, heating up the world",
		templatePath = "Heat",
		percent = 6,
		duration = {
			min = 180,
			max = 299,
		},
		worldLighting = {
			Brightness = 6,
			OutdoorAmbient = Color3.fromRGB(255, 252, 121),
		},
		effect = {
			sec = 60,
			apply = {
				count = 1,
				modification = enums.Modifications.HOT,
			}
		},
		iconAssetId = "104810307324479",
	},
}

function WeatherDataStore.getDefaultWorldLightingData(self: WeatherDataStore): WorldLightingData
	return defaultWorldLightingData
end

function WeatherDataStore.getAllWeatherNames(self: WeatherDataStore): { string }
	local result: { string } = {}
	for _, weatherData in self.weatherDatas do
		table.insert(result, weatherData.name)
	end
	return result
end

function WeatherDataStore.getWeatherDataByName(self: WeatherDataStore, name: string): WeatherData?
	for _, weatherData in self.weatherDatas do
		if weatherData.name ~= name then
			continue
		end
		return weatherData
	end
	return nil
end

function WeatherDataStore.tryInitData(self: WeatherDataStore): boolean
	local alreadyDone = 0
	local loadedNow = 0
	local failedNow = 0
	self.weatherDatas = weatherDatas
	for _, weatherData in self.weatherDatas do
		if weatherData.template then
			alreadyDone += 1
			continue
		end
		local path = string.split(weatherData.templatePath, ".")
		local inst: Instance? = Weather
		for _, pathNode in path do
			inst = (inst :: Instance):WaitForChild(pathNode, 2)
			if inst == nil then
				print("failed to load weather template", path, pathNode)
				break
			end
		end
		if not inst then
			failedNow += 1
			continue
		end
		weatherData.template = inst
		loadedNow += 1
	end

	if alreadyDone > 0 or failedNow > 0 then
		warn("weatherDataStore init, already done", alreadyDone, "loaded now", loadedNow, "failedNow", failedNow)
	end

	return failedNow == 0
end

function WeatherDataStore.new(): WeatherDataStore
	local self: WeatherDataStore = setmetatable({} :: WeatherDataStoreFields, WeatherDataStore)

	while true do
		local success, _ = pcall(
			function ()
				self:tryInitData()
			end
		)
		if success then
			break
		end

		print("failed to init weather data store")
		task.wait(2)
		print("retrying to init weather data store")
	end

	return self
end

local singleton = WeatherDataStore.new()

return singleton
