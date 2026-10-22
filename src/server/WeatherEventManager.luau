--!strict

-- v1.0 weather: one at a time, planned per era from Control/Weather. Runs instead of WeatherManager unless useLegacyWeather is true.
local WeatherEventManager = {}
WeatherEventManager.__index = WeatherEventManager

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local weatherControl = require("@game/ServerScriptService/GameData/Control/Weather")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeatherMath = require("@game/ReplicatedStorage/Shared/WeatherMath")
local WeatherStrike = require("@game/ReplicatedStorage/Shared/WeatherStrike")

local dayNightManager = require("./DayNightManager")
local EraManager = require("./EraManager")
local objectDataStore = require("./ObjectDataStore")
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local scatterZoneManager: Types.ScatterZoneManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Level = workspace:WaitForChild("Level")
local ClonedWeatherElements = Level:WaitForChild("ClonedWeatherElements")

local FADE_SEC = 1
local DEFAULT_COSMIC_EGG_ANNOUNCEMENT = "A Cosmic egg is falling from the sky!"

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
	cosmicEggItemId: number?,
	isCosmicEggPending: boolean,
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

function WeatherEventManager.isWeatherActive(self: WeatherEventManager, weather: number): boolean
	local active = self.active
	return active ~= nil and active.event.weather == weather
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

local function isInWorld(item: Types.MItem): boolean
	return item:getObj().Parent == workspace
end

local function sendTraitMessage(item: Types.MItem, text: string)
	local player = Players:GetPlayerByUserId(item:getUserId())
	if player then
		gameController:sendSystemMessageToPlayer(player, text)
	end
end

local function markStruck(obj: Instance, weather: number)
	local struckAt = workspace:GetServerTimeNow()
	obj:SetAttribute(Attributes.WEATHER_STRUCK_WEATHER, weather)
	CollectionService:AddTag(obj, Tags.WEATHER_STRIKE_TARGET)
	obj:SetAttribute(Attributes.WEATHER_STRUCK_AT, struckAt)
	task.delay(WeatherStrike.CLEAR_SEC, function()
		if obj.Parent and obj:GetAttribute(Attributes.WEATHER_STRUCK_AT) == struckAt then
			obj:SetAttribute(Attributes.WEATHER_STRUCK_AT, nil)
			obj:SetAttribute(Attributes.WEATHER_STRUCK_WEATHER, nil)
			CollectionService:RemoveTag(obj, Tags.WEATHER_STRIKE_TARGET)
		end
	end)
end

-- marks the item's replicated object for the clients' cinematic; the trait lands when the visual hits
function WeatherEventManager.strike(self: WeatherEventManager, item: Types.MItem, event: WeatherMath.WeatherEvent)
	local itemId = item:getItemId()
	if not itemManager:getItemById(itemId) then
		return
	end

	if isInWorld(item) then
		markStruck(item:getObj(), event.weather)
	end

	task.delay(WeatherStrike.TRAIT_DELAY_SEC[event.weather], function()
		if not itemManager:getItemById(itemId) then
			return
		end
		if item:addTrait(event.trait) then
			sendTraitMessage(
				item,
				string.format("Your %s became %s", item:getItemName(), assert(Enums.getPublicName(Enums.Trait, event.trait)))
			)
		end
	end)
end

-- every dragon and egg in the world rolls once; a quiet event gives the trait now (owners get one message for what they
-- gained), a strike event (strikeSpreadSec set) schedules each winner's strike at a random moment in that window
function WeatherEventManager.rollTraits(self: WeatherEventManager, event: WeatherMath.WeatherEvent)
	local chance = event.traitChance / 100
	if chance <= 0 then
		return
	end

	local random = Random.new()
	local gainedByUserId: { [number]: number } = {}
	local activeAtRoll = self.active

	local function roll(item: Types.MItem)
		if not isInWorld(item) or item:hasTrait(event.trait) or random:NextNumber() >= chance then
			return
		end

		local spreadSec = event.strikeSpreadSec
		if spreadSec then
			task.delay(random:NextNumber() * spreadSec, function()
				if self.active == activeAtRoll then
					self:strike(item, event)
				end
			end)
		elseif item:addTrait(event.trait) then
			local userId = item:getUserId()
			gainedByUserId[userId] = (gainedByUserId[userId] or 0) + 1
		end
	end

	for _, dragon in itemManager:getAllDragons() do
		roll(dragon)
	end
	for _, egg in itemManager:getAllDragonEggs() do
		roll(egg)
	end

	local traitName = assert(Enums.getPublicName(Enums.Trait, event.trait))
	for userId, count in gainedByUserId do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			gameController:sendSystemMessageToPlayer(
				player,
				string.format("%d of your dragons and eggs became %s", count, traitName)
			)
		end
	end
end

-- dev only: strikes one of the player's dragons or eggs in the world now, with the running strike weather
function WeatherEventManager.devStrikeOwn(self: WeatherEventManager, player: Player)
	local active = self.active
	if not active or not active.event.strikeSpreadSec then
		warn("devStrikeOwn needs a running weather with strikeSpreadSec set")
		return
	end

	local candidates: { Types.MItem } = {}
	for _, dragon in itemManager:getDragonsOnGroundForUserId(player.UserId) do
		table.insert(candidates, dragon)
	end
	for _, egg in itemManager:getAllDragonEggs() do
		if egg:getUserId() == player.UserId and isInWorld(egg) then
			table.insert(candidates, egg)
		end
	end

	local untraited: { Types.MItem } = {}
	for _, item in candidates do
		if not item:hasTrait(active.event.trait) then
			table.insert(untraited, item)
		end
	end
	if #untraited == 0 then
		warn("devStrikeOwn: no dragon or egg of yours in the world lacks the trait")
		return
	end

	self:strike(untraited[math.random(#untraited)], active.event)
end

function WeatherEventManager.hasUncollectedCosmicEgg(self: WeatherEventManager): boolean
	if self.isCosmicEggPending then
		return true
	end

	local item = itemManager:getItemById(self.cosmicEggItemId)
	return item ~= nil
		and item:getUserId() == Constants.UNOWNED_USER_ID
		and item:getObj():GetAttribute(Attributes.CARRY_EXPIRES_TIME) == nil
end

function WeatherEventManager.dropCosmicEgg(self: WeatherEventManager, event: WeatherMath.WeatherEvent)
	local cosmicEgg = event.cosmicEgg
	if not cosmicEgg then
		return
	end

	local zoneId, position = scatterZoneManager:pickCosmicEggSite()
	if not zoneId or not position then
		warn("WeatherEventManager: no scatter zone to drop the Cosmic egg in")
		return
	end

	self.isCosmicEggPending = true
	gameController:sendSystemMessageToAllPlayers(cosmicEgg.announcement or DEFAULT_COSMIC_EGG_ANNOUNCEMENT)

	local marker = Instance.new("Part")
	marker.Name = "CosmicEggMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.one
	marker.Position = position
	marker.Parent = workspace
	markStruck(marker, event.weather)
	task.delay(WeatherStrike.CLEAR_SEC, function()
		marker:Destroy()
	end)

	task.delay(WeatherStrike.TRAIT_DELAY_SEC[event.weather], function()
		self.isCosmicEggPending = false
		self.cosmicEggItemId = scatterZoneManager:spawnCosmicEggAt(zoneId, position, cosmicEgg.eggName)
	end)
end

function WeatherEventManager.beginCosmicEggRolls(self: WeatherEventManager, event: WeatherMath.WeatherEvent)
	local cosmicEgg = event.cosmicEgg
	if not cosmicEgg then
		return
	end

	local activeAtStart = self.active
	local random = Random.new()
	task.spawn(function()
		while true do
			task.wait(cosmicEgg.rollIntervalSec)
			if self.active ~= activeAtStart then
				return
			end
			if random:NextNumber() < cosmicEgg.chance / 100 and not self:hasUncollectedCosmicEgg() then
				self:dropCosmicEgg(event)
			end
		end
	end)
end

function WeatherEventManager.devDropCosmicEgg(self: WeatherEventManager)
	local active = self.active
	if not active or not active.event.cosmicEgg then
		warn("devDropCosmicEgg needs a running weather with cosmicEgg set")
		return
	end

	self:dropCosmicEgg(active.event)
end

-- a wild egg that appears while a weather runs rolls like the ones already in the world
function WeatherEventManager.notifyEggSpawned(self: WeatherEventManager, egg: Types.DragonEgg)
	local active = self.active
	if not active then
		return
	end

	local event = active.event
	if event.traitChance > 0 and Random.new():NextNumber() < event.traitChance / 100 then
		egg:addTrait(event.trait)
	end
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
	self:rollTraits(event)
	self:beginCosmicEggRolls(event)
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
	for _, event in config.weatherEvents do
		local cosmicEgg = event.cosmicEgg
		if cosmicEgg then
			local eggData = objectDataStore:getObjectDataByName(cosmicEgg.eggName)
			if not eggData then
				error("WeatherEventManager: no object named '" .. cosmicEgg.eggName .. "' (its `name` field must match, and check the earlier ObjectDataStore warnings)")
			end
			if eggData.type ~= "dragonEgg" then
				error("WeatherEventManager: cosmicEgg.eggName '" .. cosmicEgg.eggName .. "' has type '" .. tostring(eggData.type) .. "', not 'dragonEgg'")
			end
		end
	end

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
	self.cosmicEggItemId = nil
	self.isCosmicEggPending = false

	return self
end

function WeatherEventManager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
	scatterZoneManager = deps.scatterZoneManager
end

local singleton = WeatherEventManager.new()

return singleton
