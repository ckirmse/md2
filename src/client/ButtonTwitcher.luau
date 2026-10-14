--!strict

-- Attention twitch for HUD alert buttons: a gentle rotation wiggle played at most once per interval (a short
-- interval makes it effectively constant). Managers construct one per button and call updateIfNeeded() from their
-- update paths while the alert condition holds.
local ButtonTwitcher = {}
ButtonTwitcher.__index = ButtonTwitcher

local TweenService = game:GetService("TweenService")

local DEFAULT_TWITCH_INTERVAL_SEC = 15
local TWITCH_ANGLE = 20
local TWITCH_CYCLE_COUNT = 5
local TWITCH_STEP_SEC = 0.16

type ButtonTwitcherFields = {
	button: GuiObject,
	intervalSec: number,
	lastTwitchTime: number,
	isTwitching: boolean,
}

export type ButtonTwitcher = typeof(setmetatable({} :: ButtonTwitcherFields, ButtonTwitcher))

function ButtonTwitcher.twitch(self: ButtonTwitcher)
	if self.isTwitching then
		return
	end
	self.isTwitching = true

	task.spawn(function()
		local function step(rotation: number)
			local tween = TweenService:Create(self.button, TweenInfo.new(TWITCH_STEP_SEC, Enum.EasingStyle.Linear), { Rotation = rotation })
			tween:Play()
			tween.Completed:Wait()
		end

		for _ = 1, TWITCH_CYCLE_COUNT do
			step(TWITCH_ANGLE)
			step(-TWITCH_ANGLE)
		end
		step(0)
		self.isTwitching = false
	end)
end

function ButtonTwitcher.updateIfNeeded(self: ButtonTwitcher)
	local now = workspace:GetServerTimeNow()
	if now - self.lastTwitchTime < self.intervalSec then
		return
	end

	self.lastTwitchTime = now
	self:twitch()
end

function ButtonTwitcher.new(button: GuiObject, intervalSec: number?): ButtonTwitcher
	local self = setmetatable({} :: ButtonTwitcherFields, ButtonTwitcher)

	self.button = button
	self.intervalSec = intervalSec or DEFAULT_TWITCH_INTERVAL_SEC
	self.lastTwitchTime = 0
	self.isTwitching = false

	return self
end

return ButtonTwitcher
