--!strict

local BuyStoreManager = {}
BuyStoreManager.__index = BuyStoreManager

local EraManager = require("./EraManager")
local Types = require("./Types")
local ftueManager = require("./FtueManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local objectDataStore = require("./ObjectDataStore")
local playerAttributesManager = require("./PlayerAttributesManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local analyticsManager = require("./AnalyticsManager")

-- 5 minutes per refresh
local ERA_DURATION_SEC = 5 * 60

type BuyStoreManagerFields = {
	currentEra: number,
	eraManager: EraManager.EraManager,
	globalInventoryDatas: { any },
}

export type BuyStoreManager = typeof(setmetatable({} :: BuyStoreManagerFields, BuyStoreManager))

local function storeHash(str: string): number
	local hash = 2166136261

	for i = 1, #str do
		local c = str:sub(i, i)
		local byte = string.byte(c)
		hash = bit32.bxor(hash, byte)
		hash = (hash * 16777619) % 2 ^ 32
	end

	return hash
end


function BuyStoreManager.calculateInventory(self: BuyStoreManager, time: any): { any }
	-- we use a hash here so that people can't easily predict the store items by looking at timestamps
	local random = Random.new(storeHash(`PrivateFunKeySplendidYeah!{time}`))

	local inventoryDatas: { any } = {}

	local itemNames = gameController:getAllBuyableItemNames()
	for _, itemName in itemNames do
		local itemData = objectDataStore:getObjectDataByName(itemName)

		local count = 0
		local buyData = itemData.buy

		local stockDatas = buyData.stock
		if not stockDatas then
			warn("invalid stock for", itemName)
			continue
		end
		for _, stockData in stockDatas do
			for i = 1, stockData.count do
				local roll = random:NextNumber(0, 100)
				if roll > stockData.percent then
					continue
				end
				count += 1
			end
		end

		--print("item", itemName, "count", count, "camera", buyData.cameraPosition)

		local unlockElement = buyData.unlockElement or itemData.primaryElement

		local inventoryData = {
			itemName = itemName,
			templatePath = itemData.casterPath or itemData.templatePath,
			buyName = itemData.displayName,
			description = buyData.description,
			primaryElement = itemData.primaryElement,
			unlockElement = unlockElement,
			category = buyData.category,
			minElementLevel = buyData.minElementLevel,
			rarity = itemData.rarity,
			coins = buyData.coins,
			count = count,
			cameraPosition = buyData.cameraPosition,
			playerAttributeKeyIsUnlocked = unlockElement == enums.PrimaryElements.NONE and "" or Elements.getIsUnlockedKeyForPrimaryElement(unlockElement),
			playerAttributeKeyLevel = unlockElement == enums.PrimaryElements.NONE and "" or Elements.getLevelKeyForPrimaryElement(unlockElement),
			robuxProductId = buyData.robuxProductId,
			robuxCount = buyData.robuxCount,
		}

		table.insert(inventoryDatas, inventoryData)
	end

	-- now sort our inventoryDatas based on several criteria

	table.sort(inventoryDatas,
		function (a, b)
			local itemDataA = objectDataStore:getObjectDataByName(a.itemName)
			local itemDataB = objectDataStore:getObjectDataByName(b.itemName)
			if Elements.getSortIndexForPrimaryElement(itemDataA.primaryElement) < Elements.getSortIndexForPrimaryElement(itemDataB.primaryElement) then
				return true
			end
			if Elements.getSortIndexForPrimaryElement(itemDataA.primaryElement) > Elements.getSortIndexForPrimaryElement(itemDataB.primaryElement) then
				return false
			end

			-- same primary element, so sort by sortPriority
			if itemDataA.sortPriority < itemDataB.sortPriority then
				return true
			end
			if itemDataA.sortPriority > itemDataB.sortPriority then
				return false
			end

			-- same sort priority, so sort by plant vs dragon
			if itemDataA.type == "crop" and itemDataB.type ~= "crop" then
				return true
			end
			if itemDataA.type ~= "crop" and itemDataB.type == "crop" then
				return false
			end

			-- last gasp to distinguish them
			return a.itemName < b.itemName
		end
	)

	return inventoryDatas
end

function BuyStoreManager.updateInventory(self: BuyStoreManager)
	--print("updating inventory for era", self.currentEra)

	self.globalInventoryDatas = self:calculateInventory(self.currentEra)
end

function BuyStoreManager.updateCurrentEraAndInventory(self: BuyStoreManager)
	self.currentEra = self.eraManager:calculateCurrentEra()
	self:updateInventory()
end

function BuyStoreManager.restockNow(self: BuyStoreManager)
	self.eraManager:clearTimer()

	self:updateCurrentEraAndInventory()

	local showUser = true
	RemoteEvents.NotifyBuyStoreUpdate:FireAllClients(self:getGlobalBuyStoreDataWithPurchases({}), showUser)

	self:setTimerForNextEra()
end

function BuyStoreManager.restockRandom(self: BuyStoreManager)
	self.eraManager:clearTimer()

	local random = Random.new()
	self.currentEra = random:NextInteger(1, 1000000)
	self:updateInventory()

	local showUser = true
	RemoteEvents.NotifyBuyStoreUpdate:FireAllClients(self:getGlobalBuyStoreDataWithPurchases({}), showUser)

	self:setTimerForNextEra()
end

function BuyStoreManager.setTimerForNextEra(self: BuyStoreManager)
	self.eraManager:setTimerForNextEra(
		function()
			self:restockNow()
		end
	)
end

-- map from itemName -> count purchased in the current era; the returned table is live, so
-- incrementing it records a purchase (persisted via PlayerData on ProfileStore's normal cadence)
function BuyStoreManager.getPurchasesForPlayer(self: BuyStoreManager, player: Player): any
	return gameController:getPlayerData(player):getBuyStorePurchaseCountsForEra(self.currentEra)
end


function BuyStoreManager.tryBuyItem(self: BuyStoreManager, player: Player, itemName: string): boolean
	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		return false
	end
	if not itemData.buy then
		return false
	end

	local inventoryDatas = self.globalInventoryDatas
	-- once we have per-player purchasing of restocking, it can override inventoryDatas here

	local entry: any
	for _, inventoryData in inventoryDatas do
		if inventoryData.itemName == itemName then
			entry = inventoryData
			break
		end
	end

	if not entry then
		return false
	end

	local unlockElement = itemData.buy.unlockElement or itemData.primaryElement
	if unlockElement ~= enums.PrimaryElements.NONE then
		local playerAttributeKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(unlockElement)
		if not playerAttributesManager:get(player, playerAttributeKeyIsUnlocked) then
			print("player has not unlocked element, cannot buy", unlockElement, itemName)
			return false
		end

		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(unlockElement)
		local playerElementLevel = playerAttributesManager:get(player, playerAttributeKeyLevel)
		if playerElementLevel < entry.minElementLevel then
			print("player not high enough level to buy", playerElementLevel, entry.minElementLevel, itemName)
			return false
		end
	end

	if playerAttributesManager:get(player, PlayerAttributeKeys.COINS) < itemData.buy.coins then
		print("player doesn't have enough coins to buy", itemName)
		return false
	end

	local purchases = self:getPurchasesForPlayer(player)
	local alreadyBought = purchases[itemName] or 0
	if alreadyBought >= entry.count then
		-- client trying to buy more than allowed this era (possibly hacked?)
		print("player", player, "not allowed to purchase", itemName)
		return false
	end

	-- no yields between the checks above and this commit, so check-and-commit is atomic
	purchases[itemName] = alreadyBought + 1
	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.COINS, itemData.buy.coins)

	if not gameController:tryDeliverPurchasedItemToPlayer(player, itemName, 1) then
		print("player", player, "failed to add item to backpack", itemName)

		-- roll back the commit
		purchases[itemName] = alreadyBought
		playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, itemData.buy.coins)

		return false
	end

	-- buy.unlockElement can gate an item behind a different element than its own primaryElement, so a purchase
	-- can otherwise leave the player owning an item without unlocking the element itself
	gameController:getPlayerData(player):unlockPrimaryElementIfNeeded(itemData.primaryElement)

	analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
		objectName = itemName,
		primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
		itemType = itemData.type,
		acquisitionSource = "buyCoins",
		purchaseType = "single",
	})

	ftueManager:notifyBuyItemForPlayer(player)

	return true
end

function BuyStoreManager.tryBuyMaxItem(self: BuyStoreManager, player: Player, itemName: string): boolean | number
	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		print("bad parameter to buy max, item does not exist", itemName)
		return false
	end
	if not itemData.buy then
		print("bad parameter to buy max, item is not buyable", itemName)
		return false
	end

	local inventoryDatas = self.globalInventoryDatas

	local entry: any
	for _, inventoryData in inventoryDatas do
		if inventoryData.itemName == itemName then
			entry = inventoryData
			break
		end
	end

	if not entry then
		print("bad parameter to buy max, item not in store inventory", itemName)
		return false
	end

	local unlockElement = itemData.buy.unlockElement or itemData.primaryElement
	if unlockElement ~= enums.PrimaryElements.NONE then
		local playerAttributeKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(unlockElement)
		if not playerAttributesManager:get(player, playerAttributeKeyIsUnlocked) then
			print("player has not unlocked element, cannot buy max", unlockElement, itemName)
			return false
		end

		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(unlockElement)
		local playerElementLevel = playerAttributesManager:get(player, playerAttributeKeyLevel)
		if playerElementLevel < entry.minElementLevel then
			print("player not high enough level to buy max", playerElementLevel, entry.minElementLevel, itemName)
			return false
		end
	end

	local coins = playerAttributesManager:get(player, PlayerAttributeKeys.COINS)
	if coins < itemData.buy.coins then
		print("player doesn't have enough coins to buy max even one", itemName)
		return false
	end

	local maxAffordable = math.floor(coins / itemData.buy.coins)
	local purchases = self:getPurchasesForPlayer(player)
	local alreadyBought = purchases[itemName] or 0
	local remainingStock = entry.count - alreadyBought
	local actualQuantity = math.min(remainingStock, maxAffordable)

	if actualQuantity <= 0 then
		print("player", player, "cannot buy max, out of stock or cannot afford any", itemName)
		return false
	end

	-- no yields between the checks above and this commit, so check-and-commit is atomic
	purchases[itemName] = alreadyBought + actualQuantity
	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.COINS, itemData.buy.coins * actualQuantity)

	if not gameController:tryDeliverPurchasedItemToPlayer(player, itemName, actualQuantity) then
		print("player", player, "failed to deliver buy max items", itemName, actualQuantity)
		-- roll back the commit
		purchases[itemName] = alreadyBought
		playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, itemData.buy.coins * actualQuantity)
		return false
	end

	-- buy.unlockElement can gate an item behind a different element than its own primaryElement, so a purchase
	-- can otherwise leave the player owning an item without unlocking the element itself
	gameController:getPlayerData(player):unlockPrimaryElementIfNeeded(itemData.primaryElement)

	analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
		objectName = itemName,
		primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
		itemType = itemData.type,
		acquisitionSource = "buyCoins",
		purchaseType = "max",
		quantity = actualQuantity,
	})

	ftueManager:notifyBuyItemForPlayer(player)

	return actualQuantity
end

function BuyStoreManager.getGlobalBuyStoreDataWithPurchases(self: BuyStoreManager, purchases: any): any
	local inventoryDatas = self.globalInventoryDatas
	local buyStoreData = {
		nextEra = self.eraManager:calculateNextEra(),
		inventoryDatas = inventoryDatas,
		purchases = purchases,
	}
	return buyStoreData
end

function BuyStoreManager.getPlayerBuyStoreDataWithPurchases(self: BuyStoreManager, player: Player, purchases: any): any
	local inventoryDatas = self.globalInventoryDatas
	-- can override inventoryDatas if player did a premium restock, once that exists

	local buyStoreData = {
		nextEra = self.eraManager:calculateNextEra(),
		inventoryDatas = inventoryDatas,
		purchases = purchases,
	}
	return buyStoreData
end

function BuyStoreManager.getBuyStoreDataForPlayer(self: BuyStoreManager, player: Player): any
	return self:getPlayerBuyStoreDataWithPurchases(player, self:getPurchasesForPlayer(player))
end

-- this stuff can't go in new() because it depends on gameController being set
function BuyStoreManager.init(self: BuyStoreManager)
	self:restockNow()
end

function BuyStoreManager.new(): BuyStoreManager
	local self: BuyStoreManager = setmetatable({
		currentEra = 0,
		eraManager = EraManager.new(ERA_DURATION_SEC),
		globalInventoryDatas = {},
	} :: BuyStoreManagerFields, BuyStoreManager)

	return self
end

function BuyStoreManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = BuyStoreManager.new()

return singleton
