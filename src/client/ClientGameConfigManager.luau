--!strict

local ClientGameConfigManager = {}
ClientGameConfigManager.__index = ClientGameConfigManager

local GameConfigKeys = require("@game/ReplicatedStorage/Shared/GameConfigKeys")

local clientIndexManager = require("./ClientIndexManager")
local clientTradingManager = require("./ClientTradingManager")
local ScreenGuiManagerModule = require("./ScreenGuiManager")
local clientTradePlayerList = require("./ClientTradePlayerList")

local screenGuiManager = ScreenGuiManagerModule

local player = game:GetService("Players").LocalPlayer :: Player

export type ClientGameConfigManager = typeof(setmetatable({}, ClientGameConfigManager))

function ClientGameConfigManager.init(self: ClientGameConfigManager)
	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
	local gameConfigDataFolder = splendidDataFolder:WaitForChild("GameConfig")

	if gameConfigDataFolder:GetAttribute(GameConfigKeys.tradingEnabled) then
		screenGuiManager:showTradeButton("gameConfig")
	else
		screenGuiManager:hideTradeButton("gameConfig")
	end

	gameConfigDataFolder:GetAttributeChangedSignal(GameConfigKeys.tradingEnabled):Connect(
		function()
			if gameConfigDataFolder:GetAttribute(GameConfigKeys.tradingEnabled) then
				screenGuiManager:showTradeButton("gameConfig")
			else
				screenGuiManager:hideTradeButton("gameConfig")
				screenGuiManager:notifyTradingDisabled()
				clientTradePlayerList:notifyTradingDisabled()
				clientTradingManager:notifyTradingDisabled()
			end
		end
	)

	local function updateIndexFeatureState()
		local isIndexEnabled = gameConfigDataFolder:GetAttribute(GameConfigKeys.indexEnabled)
		screenGuiManager:setIndexFeatureEnabled(isIndexEnabled :: boolean)
		clientIndexManager:setEnabled(isIndexEnabled :: boolean)
	end

	updateIndexFeatureState()
	gameConfigDataFolder:GetAttributeChangedSignal(GameConfigKeys.indexEnabled):Connect(updateIndexFeatureState)
end

function ClientGameConfigManager.new(): ClientGameConfigManager
	local self = setmetatable({}, ClientGameConfigManager)


	return self
end

local singleton = ClientGameConfigManager.new()

return singleton
