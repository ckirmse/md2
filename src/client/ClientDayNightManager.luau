--!strict

-- Day and night as a quick lighting fade at each flip. The phase comes from server time (DayNightMath), so every client
-- and the server agree with no remote. Eggs in the world get a point light at night.
local ClientDayNightManager = {}
ClientDayNightManager.__index = ClientDayNightManager

local collectionService = game:GetService("CollectionService")
local lighting = game:GetService("Lighting")
local tweenService = game:GetService("TweenService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local DayNightMath = require("@game/ReplicatedStorage/Shared/DayNightMath")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local ClientTicker = require("./ClientTicker")

local player = game:GetService("Players").LocalPlayer :: Player

-- the HUD's shape only exists in Studio, so its instances are untyped here
type ClientDayNightManagerFields = {
	config: DayNightMath.DayNightConfig?,
	isNight: boolean?,
	clockTween: Tween?,
	hudFrame: any?,
	phaseLabel: any?,
	timerLabel: any?,
	dayIcon: any?,
	nightIcon: any?,
	shownRemainingSec: number?,
}

export type ClientDayNightManager = typeof(setmetatable({} :: ClientDayNightManagerFields, ClientDayNightManager))

local CHECK_INTERVAL_SEC = 0.25
local EGG_LIGHT_NAME = "NightUnderlight"

local function getEggLightPart(egg: any): BasePart?
	if egg:IsA("BasePart") then
		return egg
	end
	if egg:IsA("Model") then
		return egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function ClientDayNightManager.syncEggLights(self: ClientDayNightManager)
	local config = self.config
	if not config then
		return
	end

	for _, egg in collectionService:GetTagged(Tags.DRAGON_EGG) :: { any } do
		local part = getEggLightPart(egg)
		if not part then
			continue
		end

		local light = part:FindFirstChild(EGG_LIGHT_NAME)
		local doWantLight = self.isNight == true and egg:IsDescendantOf(workspace)
		if doWantLight and not light then
			local newLight = Instance.new("PointLight")
			newLight.Name = EGG_LIGHT_NAME
			newLight.Brightness = config.eggLight.brightness
			newLight.Range = config.eggLight.range
			newLight.Color = config.eggLight.color
			newLight.Shadows = false
			newLight.Parent = part
		elseif not doWantLight and light then
			light:Destroy()
		end
	end
end

function ClientDayNightManager.applyLook(self: ClientDayNightManager, look: DayNightMath.LightLook, isInstant: boolean)
	local config = self.config :: DayNightMath.DayNightConfig

	local previousClockTween = self.clockTween
	if previousClockTween then
		previousClockTween:Cancel()
		self.clockTween = nil
	end

	if isInstant or config.fadeSec <= 0 then
		lighting.ClockTime = look.clockTime
		lighting.Brightness = look.brightness
		lighting.OutdoorAmbient = look.outdoorAmbient
		return
	end

	local tweenInfo = TweenInfo.new(config.fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local lightingGoal: { [string]: any } = {
		ClockTime = look.clockTime,
		Brightness = look.brightness,
		OutdoorAmbient = look.outdoorAmbient,
	}
	local tween = tweenService:Create(lighting, tweenInfo, lightingGoal)
	self.clockTween = tween
	tween:Play()
end

function ClientDayNightManager.updateHud(self: ClientDayNightManager, remainingSec: number)
	local hudFrame = self.hudFrame
	local config = self.config
	if not hudFrame or not config then
		return
	end

	hudFrame.Visible = config.isEnabled
	if not config.isEnabled then
		return
	end

	local isNight = self.isNight == true
	local phaseLabel = self.phaseLabel
	if phaseLabel then
		phaseLabel.Text = if isNight then "Night" else "Day"
	end
	if self.dayIcon then
		self.dayIcon.Visible = not isNight
	end
	if self.nightIcon then
		self.nightIcon.Visible = isNight
	end

	local timerLabel = self.timerLabel
	local wholeSec = math.ceil(remainingSec)
	if timerLabel and wholeSec ~= self.shownRemainingSec then
		self.shownRemainingSec = wholeSec
		timerLabel.Text = string.format("%d:%02d", wholeSec // 60, wholeSec % 60)
	end
end

-- the HUD lives in the main HUD ScreenGui; a missing piece only warns
function ClientDayNightManager.bindHud(self: ClientDayNightManager)
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui: any = playerGui:WaitForChild("ScreenGui")
	local hudFrame: any = screenGui:WaitForChild("DayNightFrame", 10)
	if not hudFrame then
		warn("ClientDayNightManager: no DayNightFrame in the HUD ScreenGui; no day/night timer")
		return
	end

	self.phaseLabel = utils.findFirstDescendant(hudFrame, "PhaseLabel")
	self.timerLabel = utils.findFirstDescendant(hudFrame, "TimerLabel")
	self.dayIcon = utils.findFirstDescendant(hudFrame, "DayIcon")
	self.nightIcon = utils.findFirstDescendant(hudFrame, "NightIcon")
	if not self.timerLabel then
		warn("ClientDayNightManager: DayNightFrame has no TimerLabel; the time remaining is not shown")
	end

	self.hudFrame = hudFrame
	self.shownRemainingSec = nil
	self:update()
end

function ClientDayNightManager.update(self: ClientDayNightManager)
	local config = self.config
	if not config then
		return
	end

	local offsetSec = (workspace:GetAttribute(Attributes.DAY_NIGHT_OFFSET_SEC) :: number?) or 0
	local state = DayNightMath.getState(config, workspace:GetServerTimeNow(), offsetSec)
	local isNight = state.isNight

	if isNight ~= self.isNight then
		local isFirst = self.isNight == nil
		self.isNight = isNight
		self:applyLook(if isNight then config.night else config.day, isFirst)
	end

	self:syncEggLights()
	self:updateHud(state.remainingSec)
end

-- the config from the server: in the init data
function ClientDayNightManager.setConfig(self: ClientDayNightManager, config: any)
	local errorMessage = DayNightMath.validateConfig(config)
	if errorMessage then
		warn("ClientDayNightManager: day/night config invalid; no day/night cycle:", errorMessage)
		return
	end

	self.config = config :: DayNightMath.DayNightConfig
	self.isNight = nil

	self:update()
end

function ClientDayNightManager.init(self: ClientDayNightManager)
	task.spawn(function()
		self:bindHud()
	end)

	ClientTicker.every(CHECK_INTERVAL_SEC, function()
		self:update()
	end)
end

function ClientDayNightManager.new(): ClientDayNightManager
	local self = setmetatable({} :: ClientDayNightManagerFields, ClientDayNightManager)

	self.config = nil
	self.isNight = nil
	self.clockTween = nil
	self.hudFrame = nil
	self.phaseLabel = nil
	self.timerLabel = nil
	self.dayIcon = nil
	self.nightIcon = nil
	self.shownRemainingSec = nil

	return self
end

local singleton = ClientDayNightManager.new()

return singleton
