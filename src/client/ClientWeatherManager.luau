--!strict

local ClientWeatherManager = {}
ClientWeatherManager.__index = ClientWeatherManager

-- vendored library (out of scope per CLAUDE.md); crosses this boundary untyped
local Rain: any = require("./Libs/Rain/Rain") :: any

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance

-- server-sent record (WeatherManager:getClientWeatherDatas()); only the name is consumed here
type ClientWeatherData = {
	name: string,
}

type ClientWeatherManagerFields = {
	clientWeatherDatas: { ClientWeatherData },
	isRainEnabled: boolean,
}

export type ClientWeatherManager = typeof(setmetatable({} :: ClientWeatherManagerFields, ClientWeatherManager))

function ClientWeatherManager.setClientWeatherDatas(self: ClientWeatherManager, clientWeatherDatas: { ClientWeatherData })
	--print("active weathers:", clientWeatherDatas)

	local ScreenGui = playerGui:WaitForChild("ScreenGui")
	-- the gui's shape only exists in Studio, so it is untyped here
	local WeatherFrame: any = ScreenGui:WaitForChild("WeatherFrame")
	local template: any = WeatherFrame:FindFirstChild("TemplateWeather")
	template.Visible = false

	WeatherFrame.Visible = true

	-- remove any existing weather icons
	for _, inst in (WeatherFrame :: Instance):GetChildren() do
		if inst.Name == "TemplateWeather" then
			continue
		end
		if inst.ClassName ~= "Frame" then
			continue
		end

		inst:Destroy()
	end

	self.clientWeatherDatas = clientWeatherDatas

	local splendidDataFolder = playerGui:WaitForChild("SplendidData")
	local weatherDataFolder = splendidDataFolder:WaitForChild("Weather")

	-- create weather icon for each active one
	for _, clientWeatherData in self.clientWeatherDatas do
		local dataInst = weatherDataFolder:FindFirstChild(clientWeatherData.name)
		if not dataInst then
			warn("no weather data instance for", clientWeatherData.name)
			continue
		end

		local inst: any = template:Clone()

		local icon: any = utils.findFirstDescendant(inst, "Icon")
		icon.Image = "rbxassetid://" .. tostring(dataInst:GetAttribute(Attributes.ASSET_ID))

		inst.Name = clientWeatherData.name
		inst.Visible = true
		--inst.Text = clientWeatherData.name

		inst.Parent = WeatherFrame
	end

	if self:isWeatherActive("Rain") then
		if not self.isRainEnabled then
			Rain:Enable(TweenInfo.new(1))
			self.isRainEnabled = true
		end
	else
		if self.isRainEnabled then
			Rain:Disable(TweenInfo.new(1))
			self.isRainEnabled = false
		end
	end

end

function ClientWeatherManager.getClientWeatherDatas(self: ClientWeatherManager): { ClientWeatherData }
	return self.clientWeatherDatas
end

function ClientWeatherManager.isWeatherActive(self: ClientWeatherManager, weatherName: string): boolean
	for _, clientWeatherData in self.clientWeatherDatas do
		if clientWeatherData.name == weatherName then
			return true
		end
	end

	return false
end

function ClientWeatherManager.new(): ClientWeatherManager
	local self = setmetatable({} :: ClientWeatherManagerFields, ClientWeatherManager)

	self.clientWeatherDatas = {}

	self.isRainEnabled = false

	return self
end

local singleton = ClientWeatherManager.new()

return singleton
