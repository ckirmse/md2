--!strict

local DragonFlightManager = {}
DragonFlightManager.__index = DragonFlightManager

local ServerScriptService = game:GetService("ServerScriptService")

local DragonFlightSettings = require("@game/ReplicatedStorage/Shared/DragonFlightSettings")

type DragonFlightManagerFields = {
	config: DragonFlightSettings.DragonFlightConfig,
}

export type DragonFlightManager = typeof(setmetatable({} :: DragonFlightManagerFields, DragonFlightManager))

-- Control/DragonFlight is Studio-only and optional: a switch must not stop boot, so a missing module is the legacy flight
local function tryLoadControlData(): any?
	local gameData = ServerScriptService:FindFirstChild("GameData")
	local control = gameData and gameData:FindFirstChild("Control")
	local controlModule = control and control:FindFirstChild("DragonFlight")
	if not controlModule or not controlModule:IsA("ModuleScript") then
		return nil
	end

	-- the module is found by name at runtime, which the static require resolver cannot follow
	local requireModule: any = require
	local isSuccess, result = pcall(function(): any
		return requireModule(controlModule)
	end)
	if not isSuccess then
		warn("DragonFlightManager: Control/DragonFlight failed to load; using the legacy flight", result)
		return nil
	end

	return result
end

function DragonFlightManager.isLegacyFlight(self: DragonFlightManager): boolean
	return self.config.useLegacyFlight
end

-- sent to every client in initData; the client builds its trail from it
function DragonFlightManager.getClientConfig(self: DragonFlightManager): DragonFlightSettings.DragonFlightConfig
	return self.config
end

function DragonFlightManager.init(self: DragonFlightManager)
	local controlData = tryLoadControlData()
	if controlData == nil then
		print("DragonFlightManager: no Control/DragonFlight, dragons use the legacy flight")
		return
	end

	local errorMessage = DragonFlightSettings.validate(controlData)
	if errorMessage then
		warn("DragonFlightManager: Control/DragonFlight is invalid, using the legacy flight:", errorMessage)
		return
	end

	self.config = DragonFlightSettings.normalize(controlData)
	print("DragonFlightManager: dragon flight is", if self.config.useLegacyFlight then "legacy" else "procedural body trail")
end

function DragonFlightManager.new(): DragonFlightManager
	local self = setmetatable({} :: DragonFlightManagerFields, DragonFlightManager)
	self.config = DragonFlightSettings.normalize(nil)
	return self
end

local singleton = DragonFlightManager.new()

return singleton
