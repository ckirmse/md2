--!strict

local TradeManager = {}
TradeManager.__index = TradeManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local analyticsManager = require("./AnalyticsManager")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager = require("./ItemManager")
local storageManager = require("./StorageManager")
local Timer = require("./Timer")
local Validate = require("./Validate")

-- trade records hold Players, Timers, offers and flags and get built up incrementally, so they stay untyped
type TradeManagerFields = {
	possibleTrades: { any },
	requestedTrades: { any },
}

export type TradeManager = typeof(setmetatable({} :: TradeManagerFields, TradeManager))

-- states we support
--[[
	BOTH_OPENED = 3,
	BOTH_ACCEPTED = 9,
	EXECUTING = 12,
]]

function TradeManager.dumpState(self: TradeManager)
	print("Possible trades")
	for _, possibleTrade in self.possibleTrades do
		print("players:", possibleTrade.player1, possibleTrade.player2, "state", enums.getName(enums.TradingState, possibleTrade.state))
		print("player1 offer", possibleTrade.player1Offer)
		print("player2 offer", possibleTrade.player2Offer)
		print("accepted:", possibleTrade.player1Accepted, possibleTrade.player2Accepted)
		print("confirmed:", possibleTrade.player1Confirmed, possibleTrade.player2Confirmed)
	end

	print("Requested trades")
	for _, requestedTrade in self.requestedTrades do
		print("player", requestedTrade.sendPlayer, "requested trade with", requestedTrade.receivePlayer)
	end

end

function TradeManager.getMaxItemCount(self: TradeManager): number
	return 4
end

function TradeManager.getSortedPlayers(self: TradeManager, player1: Player, player2: Player): (Player, Player)
	if player1.UserId < player2.UserId then
		return player1, player2
	end

	return player2, player1
end

-- returns true if player is in a trade OR trade request
function TradeManager.isPlayerTrading(self: TradeManager, player: Player): boolean
	for _, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer == player or requestedTrade.receivePlayer == player then
			return true
		end
	end

	for _, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 == player or possibleTrade.player2 == player then
			return true
		end
	end

	return false
end

-- returns true if players have accepted a trade request and are in a possible trade
function TradeManager.arePlayersInTrade(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player): boolean
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)

	for _, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		return true
	end
	return false
end

function TradeManager.arePlayersInRequestTrade(self: TradeManager, sendPlayer: Player, receivePlayer: Player): boolean
	for index, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer ~= sendPlayer or requestedTrade.receivePlayer ~= receivePlayer then
			continue
		end

		return true
	end
	return false
end


function TradeManager.getRecreateItemDescriptors(self: TradeManager, itemDescriptors: any): { any }
	local recreateItemDescriptors: { any } = {}
	for _, itemDescriptor in itemDescriptors do
		local item = itemManager:getItemById(itemDescriptor.itemId)
		if not item then
			continue
		end
		local mutation: number? = nil
		local modifications: { number }? = nil
		if itemManager:isMutationCapableType(item:getType()) then
			local mitem = item :: Types.MItem
			mutation = mitem:getMutation()
			modifications = mitem:getModifications()
		end
		table.insert(recreateItemDescriptors,
			{
				displayName = item:getDisplayName(),
				rarity = item:getItemData().rarity,
				count = itemDescriptor.count,
				itemName = item:getItemName(),
				mutation = mutation,
				modifications = modifications,
			}
		)
	end

	return recreateItemDescriptors
end

function TradeManager.beginTradeRequest(self: TradeManager, sendPlayer: Player, receivePlayer: Player)
	local requestedTrade: any = {
		sendPlayer = sendPlayer,
		receivePlayer = receivePlayer,
	}

	requestedTrade.timeoutTimer = Timer.new(Constants.TRADE_REQUEST_MAX_SEC,
		function()
			RemoteEvents.NotifyCancelTrade:FireClient(sendPlayer, receivePlayer.Name)
			RemoteEvents.NotifyCancelTrade:FireClient(receivePlayer, sendPlayer.Name)

			for index, requestedTrade in self.requestedTrades do
				if requestedTrade.sendPlayer ~= sendPlayer or requestedTrade.receivePlayer ~= receivePlayer then
					continue
				end

				requestedTrade.timeoutTimer:cancel()
				table.remove(self.requestedTrades, index)
				break
			end
		end
	)

	table.insert(self.requestedTrades, requestedTrade)
end

function TradeManager.haveTradeRequest(self: TradeManager, sendPlayer: Player, receivePlayer: Player): boolean
	for _, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer ~= sendPlayer or requestedTrade.receivePlayer ~= receivePlayer then
			continue
		end

		return true
	end

	return false
end

function TradeManager.canModifyOffer(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player): boolean
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)
	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		if possibleTrade.state ~= enums.TradingState.BOTH_OPENED then
			return false
		end

		return true
	end

	return false
end

function TradeManager.canAccept(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player): boolean
	return self:canModifyOffer(rawPlayer1, rawPlayer2)
end

function TradeManager.canConfirm(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player): boolean
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)
	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		if possibleTrade.state ~= enums.TradingState.BOTH_ACCEPTED then
			return false
		end

		return true
	end

	return false
end

function TradeManager.setOffer(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player, rawPlayer1Offer: any)
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)
	if not self:canModifyOffer(player1, player2) then
		warn("trying to set offer when offers may not be modified", rawPlayer1)
		self:dumpState()
		return
	end

	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		if player1 == rawPlayer1 then
			possibleTrade.player1Offer = rawPlayer1Offer
		else
			possibleTrade.player2Offer = rawPlayer1Offer
		end
		possibleTrade.player1Accepted = false
		possibleTrade.player2Accepted = false
		break
	end
end

function TradeManager.accept(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player)
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)
	if not self:canAccept(player1, player2) then
		warn("trying to accept when not in that state", rawPlayer1)
		self:dumpState()
		return
	end

	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		if player1 == rawPlayer1 then
			possibleTrade.player1Accepted = true
		else
			possibleTrade.player2Accepted = true
		end

		if possibleTrade.player1Accepted and possibleTrade.player2Accepted then
			possibleTrade.state = enums.TradingState.BOTH_ACCEPTED
		end

		break
	end
end

function TradeManager.confirm(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player)
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)
	if not self:canConfirm(player1, player2) then
		warn("trying to confirm when not in that state", rawPlayer1)
		self:dumpState()
		return
	end

	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		if player1 == rawPlayer1 then
			possibleTrade.player1Confirmed = true
		else
			possibleTrade.player2Confirmed = true
		end

		if possibleTrade.player1Confirmed and possibleTrade.player2Confirmed then
			possibleTrade.state = enums.TradingState.EXECUTING

			task.defer(
				function()
					self:execute(player1, player2)
				end
			)

		end

		break
	end
end

function TradeManager.validateOffer(self: TradeManager, player: Player, playerOffer: any): boolean
	for _, itemDescriptor in playerOffer.itemDescriptors do
		local itemId = itemDescriptor.itemId
		local count = itemDescriptor.count
		if not Validate.isItemIdForPlayer(player, itemId) then
			return false
		end
		-- isItemIdForPlayer above guarantees the item exists
		local item = itemManager:getItemById(itemId) :: Types.Item
		if item:getCount() < count then
			return false
		end
	end

	return true
end

function TradeManager.copyItems(self: TradeManager, playerOffer: any, destPlayer: Player): { any }
	local copiedItems: { any } = {}

	for _, itemDescriptor in playerOffer.itemDescriptors do
		local itemId = itemDescriptor.itemId
		local count = itemDescriptor.count

		-- offers are validated just before items are copied, so the item exists
		local item = itemManager:getItemById(itemId) :: Types.Item
		local copiedItem = item:copyToPlayer(count, destPlayer)
		table.insert(copiedItems, copiedItem)
	end

	return copiedItems
end

function TradeManager.removeOfferItems(self: TradeManager, player: Player, playerOffer: any)
	for _, itemDescriptor in playerOffer.itemDescriptors do
		local itemId = itemDescriptor.itemId
		local count = itemDescriptor.count

		-- offers are validated just before items are removed, so the item exists
		local item = itemManager:getItemById(itemId) :: Types.Item
		item:reduceCount(count)
	end
end

function TradeManager.execute(self: TradeManager, player1: Player, player2: Player)
	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		-- confirm players still here
		local playerData1 = gameController:getPlayerData(player1)
		local playerData2 = gameController:getPlayerData(player2)
		if not playerData1 or not playerData2 then
			self:cancelTradeAndNotify(player1, player2)
			return
		end

		if not self:validateOffer(player1, possibleTrade.player1Offer) then
			warn("execute stage of trade invalid offer from", player1)
			self:cancelTradeAndNotify(player1, player2)
			return
		end

		if not self:validateOffer(player2, possibleTrade.player2Offer) then
			warn("execute stage of trade invalid offer from", player2)
			self:cancelTradeAndNotify(player1, player2)
			return
		end

		print("executing trade", player1, player2)

		-- prepare to log the data of the trade
		local tradeData = {
			player1 = player1.Name,
			player2 = player2.Name,
			player1Offer = {
				itemDescriptors = self:getRecreateItemDescriptors(possibleTrade.player1Offer.itemDescriptors),
			},
			player2Offer = {
				itemDescriptors = self:getRecreateItemDescriptors(possibleTrade.player2Offer.itemDescriptors),
			},

		}

		-- make the items
		local itemsFromPlayer1 = self:copyItems(possibleTrade.player1Offer, player2)
		local itemsFromPlayer2 = self:copyItems(possibleTrade.player2Offer, player1)

		-- remove items from player 1, give items to player 1
		self:removeOfferItems(player1, possibleTrade.player1Offer)
		for _, item in itemsFromPlayer2 do
			item:putInBackpack()

			playerData1:notifyItemReceived(item)
		end

		-- remove items from player 2, give items to player 2
		self:removeOfferItems(player2, possibleTrade.player2Offer)
		for _, item in itemsFromPlayer1 do
			item:putInBackpack()

			playerData2:notifyItemReceived(item)
		end

		possibleTrade.timeoutTimer:cancel()
		table.remove(self.possibleTrades, index)

		-- tell players it successfully executed
		RemoteEvents.NotifyTradeComplete:FireClient(player1, player2.Name)
		RemoteEvents.NotifyTradeComplete:FireClient(player2, player1.Name)

		storageManager:logTrade(player1, player2, tradeData)

		analyticsManager:logEvent(player1, analyticsManager.Events.ExecuteTrade, {})
		analyticsManager:logEvent(player2, analyticsManager.Events.ExecuteTrade, {})

		return
	end
end

function TradeManager.acceptTradeRequest(self: TradeManager, sendPlayer: Player, receivePlayer: Player): boolean?
	for index, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer ~= sendPlayer or requestedTrade.receivePlayer ~= receivePlayer then
			continue
		end

		requestedTrade.timeoutTimer:cancel()
		table.remove(self.requestedTrades, index)

		local player1, player2 = self:getSortedPlayers(sendPlayer, receivePlayer)

		local possibleTrade: any = {
			player1 = player1,
			player2 = player2,
			state = enums.TradingState.BOTH_OPENED,
			player1Offer = nil,
			player2Offer = nil,
			player1Accepted = false,
			player2Accepted = false,
			player1Confirmed = false,
			player2Confirmed = false,
		}

		possibleTrade.timeoutTimer = Timer.new(Constants.TRADE_NEGOTIATION_MAX_SEC,
			function()
				self:cancelTradeAndNotify(player1, player2)

				-- this used to call self:sendSystemMessageToPlayer, which does not exist (it crashed the timeout callback)
				gameController:sendSystemMessageToPlayer(player1, string.format("Potential trade took too long and was canceled"))
				gameController:sendSystemMessageToPlayer(player2, string.format("Potential trade took too long and was canceled"))
			end
		)

		table.insert(self.possibleTrades, possibleTrade)
		return nil
	end

	return false
end

function TradeManager.declineTradeRequest(self: TradeManager, sendPlayer: Player, receivePlayer: Player): boolean?
	for index, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer ~= sendPlayer or requestedTrade.receivePlayer ~= receivePlayer then
			continue
		end

		requestedTrade.timeoutTimer:cancel()
		table.remove(self.requestedTrades, index)

		-- message to the initial requester handled elsewhere

		return nil
	end

	return false
end

function TradeManager.cancelTrade(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player)
	for index, requestedTrade in self.requestedTrades do
		if requestedTrade.sendPlayer ~= rawPlayer1 then
			continue
		end

		requestedTrade.timeoutTimer:cancel()
		table.remove(self.requestedTrades, index)

		-- message to the initial requester handled elsewhere (GameController tryCancelTrade)
	end

	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)

	for index, possibleTrade in self.possibleTrades do
		if possibleTrade.player1 ~= player1 or possibleTrade.player2 ~= player2 then
			continue
		end

		possibleTrade.timeoutTimer:cancel()
		table.remove(self.possibleTrades, index)
	end

end

function TradeManager.cancelTradeAndNotify(self: TradeManager, rawPlayer1: Player, rawPlayer2: Player)
	local player1, player2 = self:getSortedPlayers(rawPlayer1, rawPlayer2)

	self:cancelTrade(player1, player2)

	RemoteEvents.NotifyCancelTrade:FireClient(player1, player2.Name)
	RemoteEvents.NotifyCancelTrade:FireClient(player2, player1.Name)
end

-- cancel any outstanding requestedTrade and possibleTrade situations involving the player who is gone
function TradeManager.notifyRemovePlayer(self: TradeManager, player: Player)
	for index, requestedTrade in self.requestedTrades do
		local found = false
		if player == requestedTrade.sendPlayer then
			found = true
			RemoteEvents.NotifyCancelTrade:FireClient(requestedTrade.receivePlayer, requestedTrade.sendPlayer.Name)
		end
		if player == requestedTrade.receivePlayer then
			found = true
			RemoteEvents.NotifyCancelTrade:FireClient(requestedTrade.sendPlayer, requestedTrade.receivePlayer.Name)
		end

		if found then
			requestedTrade.timeoutTimer:cancel()
			table.remove(self.requestedTrades, index)
		end
	end

	for index, possibleTrade in self.possibleTrades do
		local found = false
		if player == possibleTrade.player1 then
			found = true
			RemoteEvents.NotifyCancelTrade:FireClient(possibleTrade.player2, possibleTrade.player1.Name)
		end
		if player == possibleTrade.player2 then
			found = true
			RemoteEvents.NotifyCancelTrade:FireClient(possibleTrade.player1, possibleTrade.player2.Name)
		end

		if found then
			possibleTrade.timeoutTimer:cancel()
			table.remove(self.possibleTrades, index)
		end

	end
end

function TradeManager.init(self: TradeManager)

end

function TradeManager.new(): TradeManager
	local self: TradeManager = setmetatable({
		possibleTrades = {},

		requestedTrades = {},
	} :: TradeManagerFields, TradeManager)

	return self
end

function TradeManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = TradeManager.new()

return singleton
