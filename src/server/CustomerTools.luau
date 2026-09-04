--!strict

local CustomerTools = {}
CustomerTools.__index = CustomerTools

local playersService = game:GetService("Players")
local teleportService = game:GetService("TeleportService")

local devTools = require("./DevTools")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local playerAttributesManager = require("./PlayerAttributesManager")
local storageManager = require("./StorageManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")



type CustomerToolsFields = {}

export type CustomerTools = typeof(setmetatable({} :: CustomerToolsFields, CustomerTools))

function CustomerTools.lookupUser(self: CustomerTools, player: Player, username: string, userId: number)
	-- see if they're in the game or not with TeleporterService GetPlayerPlaceInstanceAsync
	-- get latest save game
	--

	if username == "" and userId <= 0 then
		RemoteEvents.NotifyCustomerToolData:FireClient(player, "Need either a username or user id")
		return
	end

	if userId > 0 then
		-- lookup user by id
	end

	if username ~= "" then
		-- lookup user by name
		local success, resultUserId = pcall(
			function()
				return playersService:GetUserIdFromNameAsync(username)
			end
		)
		if not success then
			RemoteEvents.NotifyCustomerToolData:FireClient(player, string.format("No user id found for player name %s", username))
			return
		end

		userId = resultUserId
	end

	do
		local success, resultUsername = pcall(
			function()
				return playersService:GetNameFromUserIdAsync(userId)
			end
		)
		if not success then
			RemoteEvents.NotifyCustomerToolData:FireClient(player, string.format("No username found for user id %s", tostring(userId)))
			return
		end

		username = resultUsername
	end

	local customerData: any = {}
	do
		local success, _currentInstance, placeId, _jobIdOrErr = pcall(
			function()
				return teleportService:GetPlayerPlaceInstanceAsync(userId)
			end
		)
		-- fyi this does not work in studio
		--print("results", success, currentInstance, placeId, jobIdOrErr)
		if success then
			customerData.isInGame = (placeId ~= nil)
		end

	end

	RemoteEvents.NotifyCustomerToolData:FireClient(player, "", userId, username, customerData)
end

function CustomerTools.loadUserSaveData(self: CustomerTools, player: Player, userId: number)
	devTools:resetCoins(player)
	devTools:resetPrimaryElementProgress(player)
	devTools:resetPurchasedSlotUnlocks(player)
	devTools:resetAllItems(player)
	devTools:resetFtueProgress(player)
	devTools:resetFirstSessionOfferState(player)

	local playerData = gameController:getPlayerData(player)

	-- loading from another player, so by default don't save
	playerData:setIfSaveOnExit(false)

	local isSuccess, profile = storageManager:loadProfileForUserId(userId)
	if not isSuccess then
		print("unsuccessful loading game", player, userId)
		return
	end
	if not profile then
		print("no save game found for user", userId)
		return
	end

	print("load got", isSuccess, profile)
	local saveData = profile.Data.standardSave

	playerData:loadSaveData(saveData)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())
end

function CustomerTools.saveDataToUser(self: CustomerTools, player: Player, userId: number)
	print("cs tool", player, "wants to save their current state to user", userId)

	local playerData = gameController:getPlayerData(player)
	local saveData = playerData:getSaveData()

	-- steal their session, save with our state, and then bail on it

	local profile = gameController:tryStartProfileSession(userId,
		{
			Steal = true,
		}
	)
	if not profile then
		print("initiating session of user", userId, "failed")
		return
	end

	profile.OnSave:Connect(
		function()
			profile.Data = {
				standardSave = saveData,
			}
		end
	)

	profile:EndSession()

	print("successfully saved out our game state to user", userId)
end

function CustomerTools.new(): CustomerTools
	local self: CustomerTools = setmetatable({} :: CustomerToolsFields, CustomerTools)

	return self
end

function CustomerTools.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = CustomerTools.new()

return singleton
