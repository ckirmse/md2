--!strict

local ClientPlayerVariables = {}
ClientPlayerVariables.__index = ClientPlayerVariables

local Constants = require("@game/ReplicatedStorage/Shared/Constants")

local player = game:GetService("Players").LocalPlayer :: Player

export type ClientPlayerVariables = typeof(setmetatable({}, ClientPlayerVariables))

-- server-pushed values are attributes of unknown-to-the-client shape, so this is genuinely dynamic
function ClientPlayerVariables.get(self: ClientPlayerVariables, attributeName: string): any
	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)

	local playerVariables = splendidDataFolder:WaitForChild(Constants.PLAYER_VARIABLES_NAME)

	return playerVariables:GetAttribute(attributeName)
end

function ClientPlayerVariables.new(): ClientPlayerVariables
	local self = setmetatable({}, ClientPlayerVariables)

	return self
end


local singleton = ClientPlayerVariables.new()

return singleton
