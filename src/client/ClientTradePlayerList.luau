--!strict

local ClientTradePlayerList = {}
ClientTradePlayerList.__index = ClientTradePlayerList

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientOptionsManager = require("./ClientOptionsManager")
local clientTradingManager = require("./ClientTradingManager")
local screenGuiManager = require("./ScreenGuiManager")

local SEND_TRADE_REQUEST_TAB_NAME = "SendTradeRequestTab"

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance

type ClientTradePlayerListFields = {
	nextLayoutOrder: number,
	pendingRequestBeginTradeStatus: boolean,
	newPlayerConnect: RBXScriptConnection?,
	exitButtonConnect: RBXScriptConnection?,
	receiveTradeRequestsTurnOnConnect: RBXScriptConnection?,
	receiveTradeRequestsTurnOffConnect: RBXScriptConnection?,
}

export type ClientTradePlayerList = typeof(setmetatable({} :: ClientTradePlayerListFields, ClientTradePlayerList))

function ClientTradePlayerList.createTradeRequestTab(self: ClientTradePlayerList, playerName: string)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	local playerRow = PlayersList:FindFirstChild(playerName)
	if not playerRow then
		warn("can't create trade request tab with player not in list", playerName)
		return
	end

	local SendTradeRequestTabTemplate = List:FindFirstChild("SendTradeRequestTabTemplate")
	local sendTradeRequestTab = SendTradeRequestTabTemplate:Clone()
	sendTradeRequestTab.Name = SEND_TRADE_REQUEST_TAB_NAME
	sendTradeRequestTab:FindFirstChild("TextLabel").Text = playerName

	sendTradeRequestTab:FindFirstChild("TradeButton").Activated:Connect(
		function()
			self.pendingRequestBeginTradeStatus = true
			RemoteEvents.TryRequestBeginTrade:FireServer(playerName)

			sendTradeRequestTab:Destroy()
		end
	)
	sendTradeRequestTab.Parent = playerRow
	--local TradeButton = SendTradeRequestTab:FindFirstChild("TradeButton")
	--local tradeButtonOffset = TradeButton.AbsolutePosition - SendTradeRequestTab.AbsolutePosition

	sendTradeRequestTab.Visible = true
end

function ClientTradePlayerList.toggleTradeRequestTab(self: ClientTradePlayerList, playerName: string)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	local playerRow = PlayersList:FindFirstChild(playerName)
	if not playerRow then
		warn("can't toggle trade request tab with player not in list", playerName)
		return
	end

	local sendTradeRequestTab = playerRow:FindFirstChild(SEND_TRADE_REQUEST_TAB_NAME)
	if sendTradeRequestTab then
		sendTradeRequestTab:Destroy()
	else
		self:createTradeRequestTab(playerName)
	end
end

function ClientTradePlayerList.destroyAllTradeRequestTabsExceptPlayerName(self: ClientTradePlayerList, playerName: string)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	local sendTradeRequestTabs = utils.getAllDescendantsByName(PlayersList, SEND_TRADE_REQUEST_TAB_NAME) :: { any }
	for _, inst in sendTradeRequestTabs do
		if inst.Parent.Name == playerName then
			continue
		end

		inst:Destroy()
	end
end

function ClientTradePlayerList.removePlayerFromList(self: ClientTradePlayerList, playerName: string)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	local playerRow = PlayersList:FindFirstChild(playerName)
	if not playerRow then
		return
	end

	playerRow:Destroy()
end

function ClientTradePlayerList.addOrUpdatePlayerToList(self: ClientTradePlayerList, playerName: string)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	local PlayerRowTemplate = PlayersList:FindFirstChild("PlayerRowTemplate")
	local PlayerRowDisabledTemplate = PlayersList:FindFirstChild("PlayerRowDisabledTemplate")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local playersDataFolder = splendidDataFolder:WaitForChild("Players")

	local inst = playersDataFolder:FindFirstChild(playerName)
	if not inst then
		warn("missing player list data", playerName)
		return
	end

	local redLevel = inst:GetAttribute(enums.getPublicName(enums.PrimaryElements, enums.PrimaryElements.FIRE) :: string)
	local blueLevel = inst:GetAttribute(enums.getPublicName(enums.PrimaryElements, enums.PrimaryElements.WATER) :: string)
	local greenLevel = inst:GetAttribute(enums.getPublicName(enums.PrimaryElements, enums.PrimaryElements.NATURE) :: string)

	-- person isn't tradeable if they have the option off or it's yourself
	local isTradeable = inst:GetAttribute(Constants.RECEIVE_TRADE_REQUESTS_ENABLED_NAME) and playerName ~= player.Name

	--print("adding or updating player", playerName)

	-- we maintain layoutOrder even if we have to recreate the row so the replacement will be in the same order
	local layoutOrder: number?

	-- create entry for this player
	local playerRow: any = PlayersList:FindFirstChild(playerName)
	if playerRow then
		layoutOrder = playerRow.LayoutOrder

		if isTradeable and not playerRow:GetAttribute(Constants.RECEIVE_TRADE_REQUESTS_ENABLED_NAME) then
			playerRow:Destroy()
			playerRow = nil
		end
		if not isTradeable and playerRow:GetAttribute(Constants.RECEIVE_TRADE_REQUESTS_ENABLED_NAME) then
			playerRow:Destroy()
			playerRow = nil
		end
	end

	if not playerRow then
		if isTradeable then
			playerRow = PlayerRowTemplate:Clone()
		else
			playerRow = PlayerRowDisabledTemplate:Clone()
		end
		playerRow.Name = playerName
		if not layoutOrder then
			layoutOrder = self.nextLayoutOrder
			self.nextLayoutOrder += 1
		end

		playerRow.LayoutOrder = layoutOrder

		inst.Destroying:Connect(
			function()
				--print("removing player from list", playerName)
				self:removePlayerFromList(playerName)
			end
		)
		for _, primaryElement in Elements.getPrimaryElementsSorted() do
				local name = enums.getPublicName(enums.PrimaryElements, primaryElement) :: string
				inst:GetAttributeChangedSignal(name):Connect(
					function()
						self:addOrUpdatePlayerToList(playerName)
					end
				)
			end
			inst:GetAttributeChangedSignal(Constants.RECEIVE_TRADE_REQUESTS_ENABLED_NAME):Connect(
				function()
					self:addOrUpdatePlayerToList(playerName)
				end
			)

		if isTradeable then
			playerRow.Activated:Connect(
				function()
					if self.pendingRequestBeginTradeStatus then
						return
					end

					--print("player row activated", playerName)
					self:destroyAllTradeRequestTabsExceptPlayerName(playerName)
					self:toggleTradeRequestTab(playerName)
				end
			)
		end
	end

	playerRow:FindFirstChild("PlayerName").Text = playerName
	local levelsFrame = playerRow:FindFirstChild("Levels")
	levelsFrame:FindFirstChild("RedElementalLevel").Text = tostring(redLevel)
	levelsFrame:FindFirstChild("GreenElementalLevel").Text = tostring(greenLevel)
	levelsFrame:FindFirstChild("BlueElementalLevel").Text = tostring(blueLevel)

	playerRow.Visible = true
	playerRow.Parent = PlayersList
end

function ClientTradePlayerList.updateReceiveTradeRequestStateVisuals(self: ClientTradePlayerList)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")
	local TradeRequestStateOff = TradePlayerList:FindFirstChild("TradeRequestToggleStateOff")
	local TradeRequestStateOn = TradePlayerList:FindFirstChild("TradeRequestToggleStateOn")

	if clientOptionsManager:getOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED) then
		TradeRequestStateOff.Visible = false
		TradeRequestStateOn.Visible = true
	else
		TradeRequestStateOff.Visible = true
		TradeRequestStateOn.Visible = false
	end

end

function ClientTradePlayerList.beginTradePlayerList(self: ClientTradePlayerList)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")
	local List = TradePlayerList:FindFirstChild("List")

	-- hide everything

	screenGuiManager:hideTradeButton("tradePlayerList")

	local SendTradeRequestTabTemplate = List:FindFirstChild("SendTradeRequestTabTemplate")
	SendTradeRequestTabTemplate.Visible = false

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local playersDataFolder = splendidDataFolder:WaitForChild("Players")

	-- listen to new players as they are added
	self.newPlayerConnect = playersDataFolder.ChildAdded:Connect(
		function(inst: Instance)
			local playerName = inst.Name
			self:addOrUpdatePlayerToList(playerName)
		end
	) :: RBXScriptConnection

	-- get existing players and their data

	for _, inst in playersDataFolder:GetChildren() do
		local playerName = inst.Name
		self:addOrUpdatePlayerToList(playerName)
	end

	-- list for trade request on/off toggle xxx

	-- listen for close event
	self.exitButtonConnect = (TradePlayerList:FindFirstChild("List"):FindFirstChild("ExitButton").Activated:Connect(
		function()
			self:cleanupTradePlayerList()
		end
	)) :: RBXScriptConnection

	local TradeRequestStateOff = TradePlayerList:FindFirstChild("TradeRequestToggleStateOff")
	local TradeRequestStateOn = TradePlayerList:FindFirstChild("TradeRequestToggleStateOn")

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

	-- show dialog
	TradePlayerList.Visible = true
end

function ClientTradePlayerList.notifyTradingDisabled(self: ClientTradePlayerList)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")

	if not TradePlayerList.Visible then
		return
	end

	self:cleanupTradePlayerList()
end

function ClientTradePlayerList.cleanupTradePlayerList(self: ClientTradePlayerList)
	-- cleanup

	local newPlayerConnect = self.newPlayerConnect
	if newPlayerConnect then
		newPlayerConnect:Disconnect()
		self.newPlayerConnect = nil
	end

	local exitButtonConnect = self.exitButtonConnect
	if exitButtonConnect then
		exitButtonConnect:Disconnect()
		self.exitButtonConnect = nil
	end

	local receiveTradeRequestsTurnOnConnect = self.receiveTradeRequestsTurnOnConnect
	if receiveTradeRequestsTurnOnConnect then
		receiveTradeRequestsTurnOnConnect:Disconnect()
		self.receiveTradeRequestsTurnOnConnect = nil
	end

	local receiveTradeRequestsTurnOffConnect = self.receiveTradeRequestsTurnOffConnect
	if receiveTradeRequestsTurnOffConnect then
		receiveTradeRequestsTurnOffConnect:Disconnect()
		self.receiveTradeRequestsTurnOffConnect = nil
	end


	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradePlayerList = ScreenGui:FindFirstChild("TradePlayerList")
	local List = TradePlayerList:FindFirstChild("List")
	local PlayersList = List:FindFirstChild("PlayersList")

	for _, inst in (PlayersList :: Instance):GetChildren() :: { any } do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst.Visible = false
		if inst.Name == "PlayerRowTemplate" then
			continue
		end
		if inst.Name == "PlayerRowDisabledTemplate" then
			continue
		end

		inst:Destroy()
	end

	-- hide dialog
	TradePlayerList.Visible = false

	screenGuiManager:showTradeButton("tradePlayerList")
end

function ClientTradePlayerList.notifyBeginTradeRequested(self: ClientTradePlayerList)
	-- someone else sent us a request while this is up, so bail
	self:cleanupTradePlayerList()
end

function ClientTradePlayerList.notifyRequestBeginTradeStatus(self: ClientTradePlayerList, playerName: string, isSuccess: boolean)
	self.pendingRequestBeginTradeStatus = false

	if not isSuccess then
		return
	end

	-- close us out and do the modal trade dialog
	self:cleanupTradePlayerList()

	clientTradingManager:beginTradingRequest(playerName)
end

function ClientTradePlayerList.init(self: ClientTradePlayerList)
	self:cleanupTradePlayerList()

end

function ClientTradePlayerList.new(): ClientTradePlayerList
	local self = setmetatable({} :: ClientTradePlayerListFields, ClientTradePlayerList)

	self.nextLayoutOrder = 1

	self.pendingRequestBeginTradeStatus = false

	return self
end


local singleton = ClientTradePlayerList.new()

return singleton
