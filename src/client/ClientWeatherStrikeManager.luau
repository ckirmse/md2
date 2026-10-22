--!strict

-- Watches the dragons and eggs the server marked as struck by a weather (Attributes.WEATHER_STRUCK_AT, tag
-- WEATHER_STRIKE_TARGET) and plays that weather's strike cinematic over them. A stamp older than the replay window is
-- ignored, so a late join or stream-in never replays a strike.
local ClientWeatherStrikeManager = {}
ClientWeatherStrikeManager.__index = ClientWeatherStrikeManager

local CollectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local WeatherStrike = require("@game/ReplicatedStorage/Shared/WeatherStrike")

local clientShadowManager = require("./ClientShadowManager")
local clientThunderstormEffects = require("./ClientThunderstormEffects")

type StrikeHandler = {
	playStrike: (self: any, targetPart: BasePart) -> (),
}

local HANDLERS: { [number]: StrikeHandler } = {
	[Enums.Weather.THUNDERSTORM] = clientThunderstormEffects :: any,
}

type ClientWeatherStrikeManagerFields = {
	connections: { [Instance]: RBXScriptConnection },
}

export type ClientWeatherStrikeManager = typeof(setmetatable({} :: ClientWeatherStrikeManagerFields, ClientWeatherStrikeManager))

-- the part the player sees: a dragon's ghost model, or the egg itself
local function resolveTargetPart(inst: any): BasePart?
	local visual: any = inst
	if inst:HasTag(Tags.SHADOW_DRAGON) then
		visual = clientShadowManager:getCaster(inst:GetAttribute(Attributes.ITEM_ID))
	end
	if not visual then
		return nil
	end
	if visual:IsA("BasePart") then
		return visual
	end
	return visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
end

function ClientWeatherStrikeManager.onStruck(self: ClientWeatherStrikeManager, inst: Instance)
	local struckAt = inst:GetAttribute(Attributes.WEATHER_STRUCK_AT)
	if type(struckAt) ~= "number" then
		return
	end
	if workspace:GetServerTimeNow() - struckAt > WeatherStrike.REPLAY_WINDOW_SEC then
		return
	end

	local handler = HANDLERS[inst:GetAttribute(Attributes.WEATHER_STRUCK_WEATHER) :: number]
	if not handler then
		return
	end

	local targetPart = resolveTargetPart(inst)
	if not targetPart then
		warn("ClientWeatherStrikeManager: no visible part for the struck object", inst:GetFullName())
		return
	end

	handler:playStrike(targetPart)
end

function ClientWeatherStrikeManager.watch(self: ClientWeatherStrikeManager, inst: Instance)
	if self.connections[inst] then
		return
	end

	self.connections[inst] = inst:GetAttributeChangedSignal(Attributes.WEATHER_STRUCK_AT):Connect(function()
		self:onStruck(inst)
	end)
	-- the tag and the attribute usually arrive in the same frame
	self:onStruck(inst)
end

function ClientWeatherStrikeManager.unwatch(self: ClientWeatherStrikeManager, inst: Instance)
	local connection = self.connections[inst]
	if connection then
		connection:Disconnect()
		self.connections[inst] = nil
	end
end

function ClientWeatherStrikeManager.init(self: ClientWeatherStrikeManager)
	CollectionService:GetInstanceAddedSignal(Tags.WEATHER_STRIKE_TARGET):Connect(function(inst: Instance)
		self:watch(inst)
	end)
	CollectionService:GetInstanceRemovedSignal(Tags.WEATHER_STRIKE_TARGET):Connect(function(inst: Instance)
		self:unwatch(inst)
	end)
	for _, inst in CollectionService:GetTagged(Tags.WEATHER_STRIKE_TARGET) do
		self:watch(inst)
	end
end

function ClientWeatherStrikeManager.new(): ClientWeatherStrikeManager
	return setmetatable({ connections = {} } :: ClientWeatherStrikeManagerFields, ClientWeatherStrikeManager)
end

local singleton = ClientWeatherStrikeManager.new()

return singleton
