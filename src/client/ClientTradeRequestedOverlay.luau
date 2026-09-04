--!strict

local ClientTradeRequestedOverlay = {}
ClientTradeRequestedOverlay.__index = ClientTradeRequestedOverlay

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")

local clientOptionsManager = require("./ClientOptionsManager")
local clientTradingManager = require("./ClientTradingManager")
local clientRideController = require("./ClientRideController")
local screenGuiManager = require("./ScreenGuiManager")

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance

type ClientTradeRequestedOverlayFields = {
	partnerPlayerName: string?,
	acceptConnect: RBXScriptConnection?,
	declineConnect: RBXScriptConnection?,
	receiveTradeRequestsTurnOnConnect: RBXScriptConnection?,
	receiveTradeRequestsTurnOffConnect: RBXScriptConnection?,
}

export type ClientTradeRequestedOverlay = typeof(setmetatable({} :: ClientTradeRequestedOverlayFields, ClientTradeRequestedOverlay))

function ClientTradeRequestedOverlay.updateReceiveTradeRequestStateVisuals(self: ClientTradeRequestedOverlay)
	-- the gui's shape only exists in Studio, so it is untyped here
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradeRequestedFrame = ScreenGui:FindFirstChild("TradeRequestedFrame")
	local TradeRequestStateOff = TradeRequestedFrame:FindFirstChild("TradeRequestToggleStateOff")
	local TradeRequestStateOn = TradeRequestedFrame:FindFirstChild("TradeRequestToggleStateOn")

	if clientOptionsManager:getOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED) then
		TradeRequestStateOff.Visible = false
		TradeRequestStateOn.Visible = true
	else
		TradeRequestStateOff.Visible = true
		TradeRequestStateOn.Visible = false
	end

end

function ClientTradeRequestedOverlay.beginTradeRequestedOverlay(self: ClientTradeRequestedOverlay)
	-- the gui's shape only exists in Studio, so it is untyped here
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradeRequestedFrame = ScreenGui:FindFirstChild("TradeRequestedFrame")

	screenGuiManager:hideTradeButton("tradeRequested")

	TradeRequestedFrame:FindFirstChild("TextLabel").Text = string.format("%s wants to trade with you", self.partnerPlayerName :: string)

	self.acceptConnect = TradeRequestedFrame:FindFirstChild("AcceptButton").Activated:Connect(
		function()
			--print("accepted")
			local partnerPlayerName = self.partnerPlayerName :: string

			if clientRideController:isRiding() then
				screenGuiManager:showSystemMessage("You must focus on riding your dragon! Jump off if you want to trade.")
				return
			end

			-- close us out and do the modal trade dialog
			self:cleanupTradeRequestedOverlay()

			RemoteEvents.TryRespondBeginTrade:FireServer(partnerPlayerName, true)
			clientTradingManager:beginTradingAcceptRequest(partnerPlayerName)
		end
	) :: RBXScriptConnection

	self.declineConnect = TradeRequestedFrame:FindFirstChild("DeclineButton").Activated:Connect(
		function()
			RemoteEvents.TryRespondBeginTrade:FireServer(self.partnerPlayerName, false)
			self:cleanupTradeRequestedOverlay()
		end
	) :: RBXScriptConnection

	local TradeRequestStateOff = TradeRequestedFrame:FindFirstChild("TradeRequestToggleStateOff")
	local TradeRequestStateOn = TradeRequestedFrame:FindFirstChild("TradeRequestToggleStateOn")

	self.receiveTradeRequestsTurnOnConnect = TradeRequestStateOff.Activated:Connect(
		function()
			clientOptionsManager:setOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED, true)

			self:updateReceiveTradeRequestStateVisuals()
		end
	) :: RBXScriptConnection

	self.receiveTradeRequestsTurnOffConnect = TradeRequestStateOn.Activated:Connect(
		function()
			clientOptionsManager:setOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED, false)

			self:updateReceiveTradeRequestStateVisuals()
		end
	) :: RBXScriptConnection

	self:updateReceiveTradeRequestStateVisuals()

	TradeRequestedFrame.Visible = true
end

function ClientTradeRequestedOverlay.cleanupTradeRequestedOverlay(self: ClientTradeRequestedOverlay)
	-- cleanup

	local acceptConnect = self.acceptConnect
	if acceptConnect then
		acceptConnect:Disconnect()
		self.acceptConnect = nil
	end

	local declineConnect = self.declineConnect
	if declineConnect then
		declineConnect:Disconnect()
		self.declineConnect = nil
	end


	-- the gui's shape only exists in Studio, so it is untyped here
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradeRequestedFrame = ScreenGui:FindFirstChild("TradeRequestedFrame")

	TradeRequestedFrame.Visible = false

	self.partnerPlayerName = nil

	screenGuiManager:showTradeButton("tradeRequested")
end

function ClientTradeRequestedOverlay.notifyBeginTradeRequested(self: ClientTradeRequestedOverlay, partnerPlayerName: string)
	self.partnerPlayerName = partnerPlayerName

	self:beginTradeRequestedOverlay()
end

function ClientTradeRequestedOverlay.notifyCancelTrade(self: ClientTradeRequestedOverlay, partnerPlayerName: string)
	if self.partnerPlayerName ~= partnerPlayerName then
		return
	end

	self:cleanupTradeRequestedOverlay()
end

function ClientTradeRequestedOverlay.init(self: ClientTradeRequestedOverlay)
	self:cleanupTradeRequestedOverlay()

end

function ClientTradeRequestedOverlay.new(): ClientTradeRequestedOverlay
	local self = setmetatable({} :: ClientTradeRequestedOverlayFields, ClientTradeRequestedOverlay)

	return self
end


local singleton = ClientTradeRequestedOverlay.new()

return singleton
