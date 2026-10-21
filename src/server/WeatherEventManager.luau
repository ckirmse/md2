--!strict

-- v1.0 weather: one at a time, planned per era from Control/Weather. Runs instead of WeatherManager unless useLegacyWeather is true.
local WeatherEventManager = {}
WeatherEventManager.__index = WeatherEventManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local weatherControl = require("@game/ServerScriptService/GameData/Control/Weather")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local WeatherMath = require("@game/ReplicatedStorage/Shared/WeatherMath")

local dayNightManager = require("./DayNightManager")
local EraManager = require("./EraManager")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Level = workspace:WaitForChild("Level")
local ClonedWeatherElements = Level:WaitForChild("ClonedWeatherElements")

local FADE_SEC = 1

type ActiveWeather = {
	event: WeatherMath.WeatherEvent,
	startTime: number,
	endTime: number,
}

type ActivePayload = {
	weather: number,
	startTime: number,
	endTime: number,
}

type WeatherEventManagerFields = {
	config: WeatherMath.WeatherConfig?,
	eventsByWeather: { [number]: WeatherMath.WeatherEvent },
	clientEvents: { any },
	eraManager: EraManager.EraManager?,
	active: ActiveWeather?,
	startTimer: Timer.Timer?,
	endTimer: Timer.Timer?,
	holder: Folder?,
}

export type WeatherEventManager = typeof(setmetatable({} :: WeatherEventManagerFields, WeatherEventManager))

local function findTemplate(templatePath: string): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Weather")
	for _, name in string.split(templatePath, ".") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function getTransparency(inst: any): number?
	local isSuccess, value = pcall(function()
		return inst.Transparency
	end)
	return if isSuccess and type(value) == "number" then value else nil
end

local function fadeIn(inst: any)
	local goalTransparency = getTransparency(inst)
	if not goalTransparency then
		return
	end

	inst.Transparency = 1
	local tweenInfo = TweenInfo.new(FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	TweenService:Create(inst, tweenInfo, { Transparency = goalTransparency }):Play()
end

local function fadeOutAndDestroy(inst: any)
	if not getTransparency(inst) then
		inst:Destroy()
		return
	end

	local tweenInfo = TweenInfo.new(FADE_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(inst, tweenInfo, { Transparency = 1 })
	tween.Completed:Connect(function()
		inst:Destroy()
	end)
	tween:Play()
end

function WeatherEventManager.isEnabled(self: WeatherEventManager): boolean
	return self.config ~= nil
end

function WeatherEventManager.getActivePayload(self: WeatherEventManager): ActivePayload?
	local active = self.active
	if not active then
		return nil
	end

	return {
		weather = active.event.weather,
		startTime = active.startTime,
		endTime = active.endTime,
	}
end

function WeatherEventManager.getClientData(self: WeatherEventManager): any
	if not self.config then
		return nil
	end

	return {
		weatherEvents = self.clientEvents,
		active = self:getActivePayload(),
	}
end

function WeatherEventManager.broadcast(self: WeatherEventManager)
	RemoteEvents.NotifyWeatherUpdate:FireAllClients({
		isWeatherEvents = true,
		active = self:getActivePayload(),
	})
end

function WeatherEventManager.activateWorld(self: WeatherEventManager, event: WeatherMath.WeatherEvent)
	local templatePath = event.templatePath
	if not templatePath then
		return
	end

	local template = findTemplate(templatePath)
	if not template then
		warn("WeatherEventManager: no weather template at ReplicatedStorage.Weather." .. templatePath)
		return
	end

	local holder = Instance.new("Folder")
	holder.Name = "Weather" .. tostring(event.weather)
	holder.Parent = ClonedWeatherElements
	self.holder = holder

	local mergePlot = template:FindFirstChild("MergePlot")
	if mergePlot then
		for plotIndex = 1, plotsManager:getNumPlots() do
			for _, inst in mergePlot:GetChildren() do
				local newInst: any = inst:Clone()
				newInst:SetAttribute(Attributes.INDEX, plotIndex)
				local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(newInst:GetPivot(), 1)
				newInst:PivotTo(PlotHelpers.translateCFramePlotToWorld(plotCFrame, plotIndex))
				newInst.Parent = holder
				fadeIn(newInst)
			end
		end
	end

	local main = template:FindFirstChild("Main")
	if main then
		for _, inst in main:GetChildren() do
			local newInst: any = inst:Clone()
			newInst.Parent = holder
			fadeIn(newInst)
		end
	end
end

function WeatherEventManager.deactivateWorld(self: WeatherEventManager)
	local holder = self.holder
	if not holder then
		return
	end
	self.holder = nil

	for _, inst in holder:GetChildren() do
		fadeOutAndDestroy(inst)
	end
	task.delay(FADE_SEC + 0.5, function()
		holder:Destroy()
	end)
end

function WeatherEventManager.endActive(self: WeatherEventManager)
	local active = self.active
	if not active then
		return
	end

	local endTimer = self.endTimer
	if endTimer then
		endTimer:cancel()
		self.endTimer = nil
	end

	self.active = nil
	self:deactivateWorld()
	if active.event.lockNight then
		dayNightManager:setNightLocked(false)
	end

	self:broadcast()
end

function WeatherEventManager.startEvent(self: WeatherEventManager, weather: number, startTime: number, endTime: number)
	local event = self.eventsByWeather[weather]
	if not event then
		warn("WeatherEventManager: unknown weather", weather)
		return
	end

	if self.active then
		self:endActive()
	end

	self.active = {
		event = event,
		startTime = startTime,
		endTime = endTime,
	}
	self:activateWorld(event)
	if event.lockNight then
		dayNightManager:setNightLocked(true)
	end

	self.endTimer = Timer.new(math.max(0, endTime - workspace:GetServerTimeNow()), function()
		self.endTimer = nil
		self:endActive()
	end)

	self:broadcast()
	if event.startMessage then
		gameController:sendSystemMessageToAllPlayers(event.startMessage)
	end
end

function WeatherEventManager.planCurrentEra(self: WeatherEventManager)
	local config = self.config :: WeatherMath.WeatherConfig
	local eraManager = self.eraManager :: EraManager.EraManager
	local now = workspace:GetServerTimeNow()

	local startTimer = self.startTimer
	if startTimer then
		startTimer:cancel()
		self.startTimer = nil
	end

	local active = self.active
	if active and now < active.endTime then
		return
	end

	local plan = WeatherMath.planEra(config, dayNightManager:getClientConfig(), eraManager:calculateCurrentEra())
	if not plan or plan.endTime <= now then
		return
	end

	local weather = plan.event.weather
	if plan.startTime <= now then
		self:startEvent(weather, plan.startTime, plan.endTime)
		return
	end

	self.startTimer = Timer.new(plan.startTime - now, function()
		self.startTimer = nil
		self:startEvent(weather, plan.startTime, plan.endTime)
	end)
end

function WeatherEventManager.updateEra(self: WeatherEventManager)
	local eraManager = self.eraManager :: EraManager.EraManager
	eraManager:clearTimer()

	self:planCurrentEra()

	eraManager:setTimerForNextEra(function()
		self:updateEra()
	end)
end

function WeatherEventManager.devStart(self: WeatherEventManager, weather: number)
	local event = self.eventsByWeather[weather]
	if not event then
		warn("WeatherEventManager: the weather system is off or the weather is unknown", weather)
		return
	end

	local now = workspace:GetServerTimeNow()
	self:startEvent(weather, now, now + event.durationMin)
end

function WeatherEventManager.devEnd(self: WeatherEventManager)
	self:endActive()
end

function WeatherEventManager.init(self: WeatherEventManager)
	if weatherControl.useLegacyWeather == true then
		return
	end

	local errorMessage = WeatherMath.validateConfig(weatherControl)
	if errorMessage then
		error("WeatherEventManager: Control/Weather is invalid: " .. errorMessage)
	end

	local config = weatherControl :: WeatherMath.WeatherConfig
	self.config = config
	for _, event in config.weatherEvents do
		self.eventsByWeather[event.weather] = event
		table.insert(self.clientEvents, {
			weather = event.weather,
			displayName = event.displayName,
			description = event.description,
			iconAssetId = event.iconAssetId,
			lighting = event.lighting,
			lockNight = event.lockNight == true,
		})
	end

	self.eraManager = EraManager.new(config.rollIntervalSec)
	self:updateEra()
end

function WeatherEventManager.new(): WeatherEventManager
	local self = setmetatable({} :: WeatherEventManagerFields, WeatherEventManager)

	self.config = nil
	self.eventsByWeather = {}
	self.clientEvents = {}
	self.eraManager = nil
	self.active = nil
	self.startTimer = nil
	self.endTimer = nil
	self.holder = nil

	return self
end

function WeatherEventManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = WeatherEventManager.new()

return singleton
