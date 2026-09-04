--!strict

local Timer = {}
Timer.__index = Timer

local Types = require("./Types")

type TimerFields = Types.TimerFields

export type Timer = Types.Timer

function Timer.new(duration: number, func: () -> ()): Timer
	local self = (setmetatable({
		--self._finishedEvent = Instance.new("BindableEvent")
		--self.finished = self._finishedEvent.Event

		_running = false,
		func = func,
	} :: TimerFields, Timer) :: any) :: Timer

	self:start(duration)
	return self
end

function Timer.start(self: Timer, duration: number)
	if self._running then
		warn("Warning: timer could not start again as it is already running.")
		return
	end

	self._task = task.defer(
		function()
			self._running = true
			self._duration = duration
			local startTime = tick()
			self._startTime = startTime
			while self._running and tick() - startTime < duration do
				local remaining = duration - (tick() - startTime)
				if remaining > 10 then
					task.wait(remaining - 2)
				elseif remaining > 2 then
					task.wait(1)
				else
					task.wait()
				end
			end
			if not self._running then
				return
			end
			self._running = false
			self._startTime = nil
			self._duration = nil
			self._task = nil

			self.func()
		end
	)
end

function Timer.getTimeLeft(self: Timer): number?
	if self._running then
		local now = tick()
		-- _startTime and _duration are always set while running, so the asserts cannot fire
		local timeLeft = assert(self._startTime) + assert(self._duration) - now
		if timeLeft < 0 then
			timeLeft = 0
		end
		return timeLeft
	end

	warn("Warning: could not get remaining time, timer is not running.")
	return nil
end

function Timer.isRunning(self: Timer): boolean
	return self._running
end

function Timer.stop(self: Timer)
	self._running = false
end

function Timer.cancel(self: Timer)
	self:stop()
	if self._task then
		task.cancel(self._task)
	end
end

return Timer
