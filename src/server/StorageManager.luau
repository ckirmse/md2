--!strict

local StorageManager = {}
StorageManager.__index = StorageManager

local dataStoreService = game:GetService("DataStoreService")

local PROFILE_DATASTORE_NAME = "playerProfiles"

type StorageManagerFields = {}

export type StorageManager = typeof(setmetatable({} :: StorageManagerFields, StorageManager))

function StorageManager.getProfileDataStoreName(self: StorageManager): string
	return PROFILE_DATASTORE_NAME
end

function StorageManager.getProfileKeyForUserId(self: StorageManager, userId: number): string
	local key
	key = string.format("%i", userId)
	return key
end

function StorageManager.getGameKeyForUserId(self: StorageManager, userId: number, slot: string | number): string
	local key
	key = string.format("g%i_%s", userId, tostring(slot))
	return key
end

function StorageManager.getPlayerGameKey(self: StorageManager, player: Player, slot: string | number): string
	return self:getGameKeyForUserId(player.UserId, slot)
end

function StorageManager.getPlayerOptionsKey(self: StorageManager, player: Player): string
	local key
	key = string.format("s_%i", player.UserId)
	return key
end

function StorageManager.getPlayerPurchasesKey(self: StorageManager, player: Player): string
	local key
	key = string.format("p_%i", player.UserId)
	return key
end

function StorageManager.getPlayerLogTradeKey(self: StorageManager, player: Player, time: number): string
	local key
	key = string.format("t_%i_%.3f", player.UserId, time)
	return key
end

function StorageManager.loadEntry(self: StorageManager, dataStoreName: string, key: string): (boolean, any)
	--print("load entry called", dataStoreName, key)
	local isSuccess, dataStore = pcall(
		function()
			return dataStoreService:GetDataStore(dataStoreName)
		end
	)
	if not isSuccess then
		warn("unable to access datastore", dataStoreName)
		return false, nil
	end

	local value
	isSuccess, value = pcall(
		function ()
			return dataStore:GetAsync(key)
		end
	)
	if not isSuccess then
		warn("error loading entry", key)
		return false, nil
	end

	return true, value
end

function StorageManager.saveEntry(self: StorageManager, dataStoreName: string, key: string, value: any): (boolean, any)
	local isSuccess, dataStore = pcall(
		function()
			return dataStoreService:GetDataStore(dataStoreName)
		end
	)
	if not isSuccess then
		return false, nil
	end

	local error
	isSuccess, error = pcall(
		function ()
			dataStore:SetAsync(key, value)
		end
	)
	if not isSuccess then
		warn("error saving data", dataStoreName, key, value, error)
		return false, nil
	end

	return true, value
end

function StorageManager.updateEntry(self: StorageManager, dataStoreName: string, key: string, func: (any) -> ...any): boolean
	local isSuccess, dataStore = pcall(
		function()
			return dataStoreService:GetDataStore(dataStoreName)
		end
	)
	if not isSuccess then
		return false
	end

	local error
	isSuccess, error = pcall(
		function ()
			dataStore:UpdateAsync(key,
				function(currentValue, _dataStoreKeyInfo)
					return func(currentValue)
				end
			)
		end
	)
	if not isSuccess then
		warn("error updating data", dataStoreName, key, error)
		return false
	end

	return true
end

function StorageManager.eraseEntry(self: StorageManager, dataStoreName: string, key: string)
	local isSuccess, dataStore = pcall(
		function()
			return dataStoreService:GetDataStore(dataStoreName)
		end
	)
	if not isSuccess then
		return
	end

	local error
	isSuccess, error = pcall(
		function ()
			dataStore:RemoveAsync(key)
		end
	)
	if isSuccess then
		print("erased entry", dataStoreName, key)
	else
		warn("error removing entry", dataStoreName, key, error)
	end
end

function StorageManager.loadGameForUserId(self: StorageManager, userId: number, slot: string | number): (boolean, any)
	local dataStoreName = "main"
	local key = self:getGameKeyForUserId(userId, slot)

	return self:loadEntry(dataStoreName, key)
end

-- this isn't the normayl way to load save data (you should use ProfileStore)
-- but for dev/customer tool purposes, this lets us access the data without making a session
function StorageManager.loadProfileForUserId(self: StorageManager, userId: number): (boolean, any)
	local dataStoreName = self:getProfileDataStoreName()
	local key = self:getProfileKeyForUserId(userId)

	return self:loadEntry(dataStoreName, key)
end

function StorageManager.loadPlayerGame(self: StorageManager, player: Player, slot: string | number): (boolean, any)
	local dataStoreName = "main"
	local key = self:getPlayerGameKey(player, slot)

	return self:loadEntry(dataStoreName, key)
end

function StorageManager.saveGameForUserId(self: StorageManager, userId: number, saveData: any, slot: string | number): (boolean, any)
	local dataStoreName = "main"
	local key = self:getGameKeyForUserId(userId, slot)

	return self:saveEntry(dataStoreName, key, saveData)
end

function StorageManager.savePlayerGame(self: StorageManager, player: Player, saveData: any, slot: string | number): (boolean, any)
	local dataStoreName = "main"
	local key = self:getPlayerGameKey(player, slot)

	return self:saveEntry(dataStoreName, key, saveData)
end

function StorageManager.backupPlayerGame(self: StorageManager, player: Player, saveData: any, slot: string | number): (boolean, any)
	local dataStoreName = "preProfileBackupSaves"
	local key = self:getPlayerGameKey(player, slot)

	return self:saveEntry(dataStoreName, key, saveData)
end

function StorageManager.savePlayerGameGlobal(self: StorageManager, player: Player, saveData: any, globalName: string): (boolean, any)
	local dataStoreName = "devGlobal"
	local key = globalName

	return self:saveEntry(dataStoreName, key, saveData)
end

function StorageManager.loadPlayerGameGlobal(self: StorageManager, player: Player, globalName: string): (boolean, any)
	local dataStoreName = "devGlobal"
	local key = globalName

	return self:loadEntry(dataStoreName, key)
end

function StorageManager.erasePlayerGame(self: StorageManager, player: Player, slot: string | number)
	local dataStoreName = "main"
	local key = self:getPlayerGameKey(player, slot)

	return self:eraseEntry(dataStoreName, key)
end

function StorageManager.loadPlayerOptions(self: StorageManager, player: Player): (boolean, any)
	local dataStoreName = "main"
	local key = self:getPlayerOptionsKey(player)

	return self:loadEntry(dataStoreName, key)
end

function StorageManager.savePlayerOptions(self: StorageManager, player: Player, options: any): (boolean, any)
	local dataStoreName = "main"
	local key = self:getPlayerOptionsKey(player)
	return self:saveEntry(dataStoreName, key, options)
end

function StorageManager.recordPurchase(self: StorageManager, player: Player, receiptInfo: { CurrencySpent: number, ProductId: number, PurchaseId: string })
	local dataStoreName = "playerPurchases"
	local key = self:getPlayerPurchasesKey(player)

	self:updateEntry(dataStoreName, key,
		function(currentValue: any)
			--print("currentValue", currentValue)
			if not currentValue then
				currentValue = {}
			end
			if typeof(currentValue) ~= "table" then
				warn("trying to record purchase for a player, do not know how they don't have an array; resetting it", player, currentValue)
				currentValue = {}
			end
			table.insert(currentValue,
				{
					CurrencySpent = receiptInfo.CurrencySpent,
					ProductId = receiptInfo.ProductId,
					PurchaseId = receiptInfo.PurchaseId,
				}
			)
			--print("trying to store", currentValue)
			return currentValue, {player.UserId}
		end
	)
end

function StorageManager.logTrade(self: StorageManager, player1: Player, player2: Player, tradeData: any)
	local now = workspace:GetServerTimeNow()

	local dataStoreName = "playerTrades"
	local key

	-- going to save it twice, with both user id prefixes so it's easy to look up all trades by a player

	key = self:getPlayerLogTradeKey(player1, now)
	self:saveEntry(dataStoreName, key, tradeData)

	key = self:getPlayerLogTradeKey(player2, now)
	self:saveEntry(dataStoreName, key, tradeData)

end

function StorageManager.new(): StorageManager
	local self: StorageManager = setmetatable({} :: StorageManagerFields, StorageManager)

	return self
end

local singleton = StorageManager.new()

return singleton
