--!strict

-- Client side of WeatherEventManager. Stays off when the server sends no weather data (legacy ClientWeatherManager runs then).
local ClientWeatherEventManager = {}
ClientWeatherEventManager.__index = ClientWeatherEventManager

-- vendored library (out of scope per CLAUDE.md); crosses this boundary untyped
local Rain: any = require("./Libs/Rain/Rain") :: any

local DayNightMath = require("@game/ReplicatedStorage/Shared/DayNightMath")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local ClientDayNightManager = require("./ClientDayNightManager")
local clientThunderstormEffects = require("./ClientThunderstormEffects")
local ClientTicker = require("./ClientTicker")

local player = game:GetService("Players").LocalPlayer :: Player

type ClientEvent = {
	weather: number,
	displayName: string,
	description: string,
	iconAssetId: string,
	lighting: DayNightMath.WeatherLighting?,
	lockNight: boolean,
}

type ActiveWeather = {
	weather: number,
	startTime: number,
	endTime: number,
}

-- the HUD's shape only exists in Studio, so its instances are untyped here
type ClientWeatherEventManagerFields = {
	isOn: boolean,
	eventsByWeather: { [number]: ClientEvent },
	active: ActiveWeather?,
	weatherFrame: any?,
	template: any?,
	icon: any?,
	timerLabel: any?,
	toolTip: any?,
	isRainEnabled: boolean,
	effectsWeather: number?,
	shownRemainingSec: number?,
}

export type ClientWeatherEventManager = typeof(setmetatable({} :: ClientWeatherEventManagerFields, ClientWeatherEventManager))

-- weathers with ambient effects of their own; onStart / onEnd run when that weather starts and ends
local EFFECT_HANDLERS: { [number]: { onStart: (self: any, startTime: number, endTime: number) -> (), onEnd: (self: any) -> () } } = {
	[Enums.Weather.THUNDERSTORM] = clientThunderstormEffects :: any,
}

local TICK_INTERVAL_SEC = 0.25
local ICON_NAME = "ActiveWeather"

function ClientWeatherEventManager.isEnabled(self: ClientWeatherEventManager): boolean
	return self.isOn
end

function ClientWeatherEventManager.getEvents(self: ClientWeatherEventManager): { [number]: ClientEvent }
	return self.eventsByWeather
end

function ClientWeatherEventManager.clearIcon(self: ClientWeatherEventManager)
	local weatherFrame = self.weatherFrame
	if weatherFrame then
		local existing = weatherFrame:FindFirstChild(ICON_NAME)
		if existing then
			existing:Destroy()
		end
		weatherFrame.Visible = false
	end

	self.icon = nil
	self.timerLabel = nil
	self.toolTip = nil
	self.shownRemainingSec = nil
end

function ClientWeatherEventManager.showIcon(self: ClientWeatherEventManager, event: ClientEvent)
	local weatherFrame = self.weatherFrame
	local template = self.template
	if not weatherFrame or not template then
		return
	end

	self:clearIcon()

	local icon: any = template:Clone()
	icon.Name = ICON_NAME
	icon.Visible = true

	local iconImage: any = utils.findFirstDescendant(icon, "Icon")
	if iconImage and event.iconAssetId ~= "" then
		iconImage.Image = "rbxassetid://" .. event.iconAssetId
	end

	local toolTip: any
	local toolTipLabel: any
	for _, descendant in icon:GetDescendants() do
		local lowerName = string.lower(descendant.Name)
		if not toolTip and lowerName == "tooltip" and descendant:IsA("GuiObject") then
			toolTip = descendant
		elseif not toolTipLabel and lowerName == "tooltipinfo" and descendant:IsA("TextLabel") then
			toolTipLabel = descendant
		end
	end
	if toolTip and not toolTipLabel then
		toolTipLabel = if toolTip:IsA("TextLabel") then toolTip else utils.findFirstDescendantOfClass(toolTip, "TextLabel")
	end
	if not toolTip or not toolTipLabel then
		warn("ClientWeatherEventManager: no Tooltip (a TextLabel, or a Frame holding one) in TemplateWeather, so the weather has no tooltip")
	else
		toolTip.ZIndex = 10
		toolTipLabel.ZIndex = 11
		toolTipLabel.RichText = true
		local textSize = toolTipLabel.TextSize
		toolTipLabel.Text = string.format(
			'<font size="%d">%s</font>\n<font size="%d"> </font>\n%s',
			textSize + 4,
			event.displayName,
			math.floor(textSize / 2),
			event.description
		)
		toolTip.Visible = false
		toolTip.Active = false

		local hoverId = 0
		local function onEnter()
			hoverId += 1
			toolTip.Visible = true
		end
		local function onLeave()
			hoverId += 1
			local thisId = hoverId
			task.defer(function()
				if hoverId == thisId then
					toolTip.Visible = false
				end
			end)
		end
		local function hookHover(guiObject: any)
			guiObject.Active = true
			guiObject.MouseEnter:Connect(onEnter)
			guiObject.MouseLeave:Connect(onLeave)
		end
		hookHover(icon)
		for _, descendant in icon:GetDescendants() do
			if descendant:IsA("GuiObject") and descendant ~= toolTip and not descendant:IsDescendantOf(toolTip) then
				hookHover(descendant)
			end
		end

		icon.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				toolTip.Visible = not toolTip.Visible
			end
		end)
	end

	self.icon = icon
	self.timerLabel = utils.findFirstDescendant(icon, "Timer")
	self.toolTip = toolTip
	icon.Parent = weatherFrame
	weatherFrame.Visible = true
end

function ClientWeatherEventManager.updateTimer(self: ClientWeatherEventManager)
	local active = self.active
	local timerLabel = self.timerLabel
	if not active or not timerLabel then
		return
	end

	local wholeSec = math.max(0, math.ceil(active.endTime - workspace:GetServerTimeNow()))
	if wholeSec ~= self.shownRemainingSec then
		self.shownRemainingSec = wholeSec
		timerLabel.Text = string.format("%d:%02d", wholeSec // 60, wholeSec % 60)
	end
end

function ClientWeatherEventManager.setRain(self: ClientWeatherEventManager, isRaining: boolean)
	if isRaining == self.isRainEnabled then
		return
	end

	self.isRainEnabled = isRaining
	if isRaining then
		Rain:Enable(TweenInfo.new(1))
	else
		Rain:Disable(TweenInfo.new(1))
	end
end

function ClientWeatherEventManager.setEffects(self: ClientWeatherEventManager, active: ActiveWeather?)
	local weather = if active then active.weather else nil
	if weather == self.effectsWeather then
		return
	end

	local previous = self.effectsWeather and EFFECT_HANDLERS[self.effectsWeather]
	if previous then
		previous:onEnd()
	end

	self.effectsWeather = weather
	local handler = weather and EFFECT_HANDLERS[weather]
	if handler and active then
		handler:onStart(active.startTime, active.endTime)
	end
end

function ClientWeatherEventManager.apply(self: ClientWeatherEventManager)
	if not self.isOn then
		return
	end

	local active = self.active
	local event = if active then self.eventsByWeather[active.weather] else nil

	ClientDayNightManager:setWeatherLighting(if event then event.lighting else nil)
	ClientDayNightManager:setNightLock(if event and event.lockNight and active then active.endTime else nil)
	self:setRain(event ~= nil and event.weather == Enums.Weather.RAIN)
	self:setEffects(active)

	if event then
		self:showIcon(event)
		self:updateTimer()
	else
		self:clearIcon()
	end
end

function ClientWeatherEventManager.setActive(self: ClientWeatherEventManager, active: any)
	if type(active) == "table" then
		self.active = active :: ActiveWeather
	else
		self.active = nil
	end

	self:apply()
end

function ClientWeatherEventManager.setData(self: ClientWeatherEventManager, data: any)
	if type(data) ~= "table" or type(data.weatherEvents) ~= "table" then
		self.isOn = false
		return
	end

	self.isOn = true
	self.eventsByWeather = {}
	for _, event in data.weatherEvents do
		self.eventsByWeather[event.weather] = event :: ClientEvent
	end

	self:setActive(data.active)
end

function ClientWeatherEventManager.bindHud(self: ClientWeatherEventManager)
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui: any = playerGui:WaitForChild("ScreenGui")
	local weatherFrame: any = screenGui:WaitForChild("WeatherFrame", 10)
	if not weatherFrame then
		warn("ClientWeatherEventManager: no WeatherFrame in the HUD ScreenGui; no weather icon")
		return
	end

	local template: any = weatherFrame:FindFirstChild("TemplateWeather")
	if not template then
		warn("ClientWeatherEventManager: WeatherFrame has no TemplateWeather; no weather icon")
		return
	end

	template.Visible = false
	weatherFrame.Visible = false
	self.weatherFrame = weatherFrame
	self.template = template
	self:apply()
end

function ClientWeatherEventManager.init(self: ClientWeatherEventManager)
	task.spawn(function()
		self:bindHud()
	end)

	ClientTicker.every(TICK_INTERVAL_SEC, function()
		self:updateTimer()
	end)
end

function ClientWeatherEventManager.new(): ClientWeatherEventManager
	local self = setmetatable({} :: ClientWeatherEventManagerFields, ClientWeatherEventManager)

	self.isOn = false
	self.eventsByWeather = {}
	self.active = nil
	self.weatherFrame = nil
	self.template = nil
	self.icon = nil
	self.timerLabel = nil
	self.toolTip = nil
	self.isRainEnabled = false
	self.effectsWeather = nil
	self.shownRemainingSec = nil

	return self
end

local singleton = ClientWeatherEventManager.new()

return singleton
