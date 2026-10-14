--!strict

-- Shared low-frequency ticker: one Heartbeat connection serving every manager that needs periodic UI refreshes,
-- instead of per-manager while-true loops or per-frame label updates.
local ClientTicker = {}

local RunService = game:GetService("RunService")

export type Disconnect = () -> ()

type Subscription = {
	intervalSec: number,
	elapsedSec: number,
	callback: () -> (),
}

local subscriptions: { [Subscription]: boolean } = {}
local connection: RBXScriptConnection? = nil

local function disconnectIfIdle()
	if next(subscriptions) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureConnected()
	if connection then
		return
	end

	local heartbeatConnection: RBXScriptConnection = RunService.Heartbeat:Connect(function(dt: number)
		for subscription in subscriptions do
			subscription.elapsedSec += dt
			if subscription.elapsedSec < subscription.intervalSec then
				continue
			end
			subscription.elapsedSec = 0
			subscription.callback()
		end
	end)
	connection = heartbeatConnection
end

-- runs callback every intervalSec until the returned function is called
function ClientTicker.every(intervalSec: number, callback: () -> ()): Disconnect
	local subscription: Subscription = {
		intervalSec = intervalSec,
		elapsedSec = 0,
		callback = callback,
	}
	subscriptions[subscription] = true
	ensureConnected()

	return function()
		subscriptions[subscription] = nil
		disconnectIfIdle()
	end
end

return ClientTicker
