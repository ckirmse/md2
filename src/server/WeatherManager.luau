--!strict

local WeatherManager = {}
WeatherManager.__index = WeatherManager

local tweenService = game:GetService("TweenService")

local EraManager = require("./EraManager")
local itemManager = require("./ItemManager")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")
local weatherDataStore = require("./WeatherDataStore")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local Level = workspace:WaitForChild("Level")
local ClonedWeatherElements = Level:WaitForChild("ClonedWeatherElements")

-- 5 minutes per refresh
local ERA_DURATION_SEC = 5 * 60

type RunningWeather = {
	endTimer: Timer.Timer,
	effectTime: Timer.Timer,
}

type WeatherManagerFields = {
	currentEra: number,
	eraManager: EraManager.EraManager,
	activeWeathers: { [string]: RunningWeather },
}

export type WeatherManager = typeof(setmetatable({} :: WeatherManagerFields, WeatherManager))

function WeatherManager.beginWeatherName(self: WeatherManager, weatherName: string, duration: number)
	if self.activeWeathers[weatherName] then
		print("cannot begin weather already active", weatherName)
		return
	end

	--print("activating weather", weatherName)

	-- an unknown weather name crashed here before typing too
	local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any

	local runningData = {
		endTimer = Timer.new(duration,
			function()
				self:endWeatherName(weatherName)
				self:sendWeatherAllPlayers()
			end
		),
		effectTime = Timer.new(weatherData.effect.sec,
			function()
				self:applyEffectToItems(weatherName)
			end
		),
	}
	self.activeWeathers[weatherName] = runningData

	self:activateWeatherInWorld(weatherName)
end

function WeatherManager.endWeatherName(self: WeatherManager, weatherName: string)
	if not self.activeWeathers[weatherName] then
		print("cannot end weather that is not active", weatherName)
		return
	end

	--print("ending weather", weatherName)

	local runningData = self.activeWeathers[weatherName]
	runningData.endTimer:cancel()
	runningData.effectTime:cancel()

	self.activeWeathers[weatherName] = nil

	self:deactivateWeatherInWorld(weatherName)

end

function WeatherManager.setFadeInInstance(self: WeatherManager, inst: any)
	local goalTransparency = inst.Transparency

	inst.Transparency = 1
	local duration = 1
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	local goal = {}
	goal.Transparency = goalTransparency

	local tween = tweenService:Create(inst, tweenInfo, goal)
	tween:Play()
end

function WeatherManager.setFadeOutInstance(self: WeatherManager, inst: any)
	local duration = 1
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	local goal = {}
	goal.Transparency = 1

	local tween = tweenService:Create(inst, tweenInfo, goal)
	tween.Completed:Connect(
		function ()
			inst:Destroy()
		end
	)
	tween:Play()
end

function WeatherManager.activateWeatherInWorld(self: WeatherManager, weatherName: string)
	local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any

	local baseFolder = weatherData.template

	-- this can have various subfolders to do things with

	local holder = ClonedWeatherElements:FindFirstChild(weatherName)
	if not holder then
		holder = Instance.new("Folder")
		holder.Name = weatherName
		holder.Parent = ClonedWeatherElements
	end

	local MergePlot = baseFolder:FindFirstChild("MergePlot")
	if MergePlot then
		for plotIndex = 1, plotsManager:getNumPlots() do
			for _, inst in MergePlot:GetChildren() do
				local newInst = inst:Clone()
				newInst:SetAttribute(Attributes.INDEX, plotIndex)
				local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(newInst:GetPivot(), 1)
				newInst:PivotTo(PlotHelpers.translateCFramePlotToWorld(plotCFrame, plotIndex))
				newInst.Parent = holder
				self:setFadeInInstance(newInst)
			end

		end

	end

	local Main = baseFolder:FindFirstChild("Main")
	if Main then
		-- global stuff to clone
		for _, inst in Main:GetChildren() do
			local newInst = inst:Clone()
			self:setFadeInInstance(newInst)
			newInst.Parent = holder
		end
	end

	if weatherData.worldLighting then
		for propertyName, value in weatherData.worldLighting do
			--game:GetService("Lighting")[propertyName] = value
			local duration = 1
			local tweenInfo = TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			)
			local goal: any = {}
			goal[propertyName] = value

			local tween = tweenService:Create(game:GetService("Lighting"), tweenInfo, goal)
			tween:Play()

		end
	end
end

function WeatherManager.deactivateWeatherInWorld(self: WeatherManager, weatherName: string)
	local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any

	local holder = ClonedWeatherElements:FindFirstChild(weatherName)

	-- a missing holder crashed here before typing too
	for _, holderInst in (holder :: Instance):GetChildren() do
		self:setFadeOutInstance(holderInst)
	end

	if weatherData.worldLighting then
		for propertyName, value in weatherData.worldLighting do
			local duration = 1
			local tweenInfo = TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut
			)
			local goal: any = {}
			goal[propertyName] = (weatherDataStore:getDefaultWorldLightingData() :: any)[propertyName]

			local tween = tweenService:Create(game:GetService("Lighting"), tweenInfo, goal)
			tween:Play()
		end
	end

end

function WeatherManager.applyEffectToItems(self: WeatherManager, weatherName: string)
	local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any

	--print("should apply effect for", weatherName)

	-- pick random crop and apply effect
	local crops = itemManager:getCropsOnGround()

	local items = {}
	utils.arrayAppend(items, crops)

	if #items == 0 then
		return
	end

	local modification = weatherData.effect.apply.modification

	local random = Random.new()
	for i = 1, weatherData.effect.apply.count do
		local index = random:NextInteger(1, #items)

		local item = items[index]
		if item:doesHaveModification(modification) then
			--print("skipping weather modification, item already has it", modification, item)
			continue
		end

		--print("applying", modification, "to", item)
		item:addModification(modification)
	end

end

function WeatherManager.addRandomWeather(self: WeatherManager)
	local random = Random.new(self.currentEra)

	local weatherNames = weatherDataStore:getAllWeatherNames()
	for _, weatherName in weatherNames do
		local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any
		local roll = random:NextNumber(0, 100)
		if roll > weatherData.percent then
			continue
		end

		local duration = random:NextNumber(weatherData.duration.min, weatherData.duration.max)
		if self.currentEra + duration < workspace:GetServerTimeNow() then
			--print("skipping weather, it is over; should only be possible on server start", weatherName)
			continue
		end


		self:beginWeatherName(weatherName, duration)
	end
end

function WeatherManager.sendWeatherAllPlayers(self: WeatherManager)
	--print("sending weather to all players")
	RemoteEvents.NotifyWeatherUpdate:FireAllClients(self:getClientWeatherDatas())
end

function WeatherManager.updateWeather(self: WeatherManager)
	self.eraManager:clearTimer()

	self.currentEra = self.eraManager:calculateCurrentEra()
	self:addRandomWeather()

	self:sendWeatherAllPlayers()

	self:setTimerForNextEra()
end

function WeatherManager.setTimerForNextEra(self: WeatherManager)
	self.eraManager:setTimerForNextEra(
		function()
			self:updateWeather()
		end
	)
end

function WeatherManager.getClientWeatherDatas(self: WeatherManager): { any }
	local clientWeatherDatas: { any } = {}
	for weatherName, runningData in self.activeWeathers do
		local clientWeatherData = {
			name = weatherName
		}
		table.insert(clientWeatherDatas, clientWeatherData)
	end
	return clientWeatherDatas
end

function WeatherManager.new(): WeatherManager
	local self: WeatherManager = setmetatable({
		currentEra = 0,
		eraManager = EraManager.new(ERA_DURATION_SEC),

		activeWeathers = {},
	} :: WeatherManagerFields, WeatherManager)

	self:updateWeather()

	return self
end

local singleton = WeatherManager.new()

return singleton
