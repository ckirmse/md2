--!strict

local ClientAnalyticsManager = {}
ClientAnalyticsManager.__index = ClientAnalyticsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

ClientAnalyticsManager.Events = {
	FtueOpenBuyStore = "FtueOpenBuyStore",
	RecreateShadowCaster = "RecreateShadowCaster",
}

export type ClientAnalyticsManager = typeof(setmetatable({}, ClientAnalyticsManager))

function ClientAnalyticsManager.logEvent(self: ClientAnalyticsManager, eventName: string?, properties: { [string]: any }?)
	if not eventName then
		warn("nil event name to logEvent", debug.traceback())
		return
	end

	RemoteEvents.TryLogAnalyticsEvent:FireServer(eventName, properties)
end

function ClientAnalyticsManager.init(self: ClientAnalyticsManager)

end

function ClientAnalyticsManager.new(): ClientAnalyticsManager
	local self = setmetatable({}, ClientAnalyticsManager)

	return self
end

local singleton = ClientAnalyticsManager.new()

return singleton
