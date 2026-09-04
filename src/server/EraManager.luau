--!strict

local EraManager = {}
EraManager.__index = EraManager

local Timer = require("./Timer")

type EraManagerFields = {
	eraDurationSec: number,
	nextEraTimer: Timer.Timer?,
}

export type EraManager = typeof(setmetatable({} :: EraManagerFields, EraManager))

function EraManager.calculateCurrentEra(self: EraManager): number
	local epochSec = workspace:GetServerTimeNow()

	local era = epochSec - (epochSec % self.eraDurationSec)

	return era
end

function EraManager.calculateNextEra(self: EraManager): number
	-- calculate current era rather than stored data in case dev tools mucked with it
	local currentEra = self:calculateCurrentEra()
	local nextEra = currentEra + self.eraDurationSec

	return nextEra
end

function EraManager.calculateTimeToNextEraSec(self: EraManager): number
	local nextEra = self:calculateNextEra()

	local timeToNextEraSec = math.max(0, nextEra - workspace:GetServerTimeNow())

	return timeToNextEraSec
end

function EraManager.setTimerForNextEra(self: EraManager, func: () -> ())
	self:clearTimer()

	local timeToNextEraSec = self:calculateTimeToNextEraSec()
	self.nextEraTimer = Timer.new(timeToNextEraSec,
		function ()
			self.nextEraTimer = nil
			func()
		end
	)
end

function EraManager.clearTimer(self: EraManager)
	if self.nextEraTimer then
		self.nextEraTimer:cancel()
		self.nextEraTimer = nil
	end

end

function EraManager.new(eraDurationSec: number): EraManager
	local self: EraManager = setmetatable({
		eraDurationSec = eraDurationSec,

		nextEraTimer = nil,
	} :: EraManagerFields, EraManager)

	return self
end

return EraManager
