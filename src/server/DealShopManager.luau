--!strict

local DealShopManager = {}
DealShopManager.__index = DealShopManager

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local DealShopCatalog = require("@game/ReplicatedStorage/Shared/DealShopCatalog")
local dealShopData: DealShopCatalog.DealShopConfig = require("@game/ServerScriptService/GameData/Control/DealShop")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local analyticsManager = require("./AnalyticsManager")
local ftueManager = require("./FtueManager")
local objectDataStore = require("./ObjectDataStore")
local playerAttributesManager = require("./PlayerAttributesManager")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

type TierEntry = {
	deal: DealShopCatalog.Deal,
	tier: DealShopCatalog.Tier,
}

type PendingGift = {
	productId: number,
	recipientUserId: number,
	expireTime: number,
}

type DealShopManagerFields = {
	tiersByProductId: { [number]: TierEntry },
	tiersByDealKey: { [string]: { TierEntry } },
	pendingGiftsByPlayer: { [Player]: PendingGift },
	clientConfig: DealShopCatalog.DealShopConfig?,
}

export type DealShopManager = typeof(setmetatable({} :: DealShopManagerFields, DealShopManager))

-- a purchase prompt should resolve within seconds; the expiry only guards against an abandoned
-- prompt hijacking a much later purchase of the same product
local PENDING_GIFT_LIFETIME_SEC = 300

local function isWholeNumber(value: any): boolean
	return type(value) == "number" and value == math.floor(value)
end

local function isDeliverableItemData(itemData: any): boolean
	return itemData.type == "shadowDragon" or (itemData.mixins ~= nil and itemData.mixins.pickup ~= nil)
end

function DealShopManager.validateTierContents(self: DealShopManager, dealKey: string, tier: DealShopCatalog.Tier)
	for _, content in tier.contents do
		if content.kind ~= enums.ShopContentKind.ITEM then
			continue
		end

		local objectName = content.objectName :: string
		local itemData = objectDataStore:getObjectDataByName(objectName)
		if not itemData then
			error(`DealShopManager: deal {dealKey} references unknown object {objectName}`)
		end
		if not isDeliverableItemData(itemData) then
			error(`DealShopManager: deal {dealKey} sells {objectName}, which cannot be delivered as a purchase`)
		end
	end
end

function DealShopManager.validateConfig(self: DealShopManager)
	local errors = DealShopCatalog.validate(dealShopData)
	if #errors > 0 then
		error("DealShopManager: invalid DealShop config: " .. table.concat(errors, "; "))
	end

	for _, section in dealShopData.SECTIONS do
		for _, deal in section.deals do
			local dealTiers: { TierEntry } = {}
			self.tiersByDealKey[deal.dealKey] = dealTiers

			for _, tier in deal.tiers do
				local entry: TierEntry = { deal = deal, tier = tier }
				table.insert(dealTiers, entry)

				local productId = tier.productId
				if productId then
					-- delivery is first-match, so a shared product id would be granted by the wrong system
					if gameController:isProductIdReserved(productId) then
						error(`DealShopManager: deal {deal.dealKey} reuses product id {productId} already delivered by another system`)
					end
					self.tiersByProductId[productId] = entry
				end

				self:validateTierContents(deal.dealKey, tier)
			end
		end
	end
end

-- clients can't read GameData, so they get a display copy, built once and sent in every player's init data
function DealShopManager.buildClientConfig(self: DealShopManager)
	local enriched = { SECTIONS = {} :: { any } }

	for sectionIndex, section in dealShopData.SECTIONS do
		local enrichedSection = table.clone(section) :: any
		enrichedSection.deals = {}

		for dealIndex, deal in section.deals do
			local enrichedDeal = table.clone(deal) :: any
			enrichedDeal.tiers = {}

			for tierIndex, tier in deal.tiers do
				local enrichedTier = table.clone(tier) :: any
				enrichedTier.contents = {}

				for contentIndex, content in tier.contents do
					local enrichedContent = table.clone(content) :: any
					if content.kind == enums.ShopContentKind.ITEM then
						local itemData = objectDataStore:getObjectDataByName(content.objectName :: string)
						enrichedContent.displayName = itemData.displayName
						enrichedContent.rarity = itemData.rarity
					end
					enrichedTier.contents[contentIndex] = enrichedContent
				end

				enrichedDeal.tiers[tierIndex] = enrichedTier
			end

			enrichedSection.deals[dealIndex] = enrichedDeal
		end

		enriched.SECTIONS[sectionIndex] = enrichedSection
	end

	self.clientConfig = enriched :: any
end

function DealShopManager.getClientConfig(self: DealShopManager): DealShopCatalog.DealShopConfig?
	return self.clientConfig
end

function DealShopManager.isProductId(self: DealShopManager, productId: number): boolean
	return self.tiersByProductId[productId] ~= nil
end

-- the purchase is already paid for, so every content entry is attempted and one landing counts as granted;
-- retrying after a partial failure would duplicate items, so only a total failure reports false
function DealShopManager.grantTier(
	self: DealShopManager,
	player: Player,
	deal: DealShopCatalog.Deal,
	tier: DealShopCatalog.Tier,
	acquisitionSource: string
): boolean
	local grantedCount = 0

	for _, content in tier.contents do
		if content.kind == enums.ShopContentKind.ITEM then
			local objectName = content.objectName :: string
			local count = content.count :: number

			if gameController:tryDeliverPurchasedItemToPlayer(player, objectName, count) then
				grantedCount += 1

				local itemData = objectDataStore:getObjectDataByName(objectName)
				analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
					objectName = objectName,
					primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
					rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
					itemType = itemData.type,
					acquisitionSource = acquisitionSource,
					quantity = count,
				})
			else
				warn("DealShopManager: failed to grant", objectName, "for deal", deal.dealKey)
			end
		elseif content.kind == enums.ShopContentKind.COINS then
			local amount = content.amount :: number

			playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, amount)
			analyticsManager:logGainCurrency(
				player,
				amount,
				playerAttributesManager:get(player, PlayerAttributeKeys.COINS),
				deal.dealKey
			)
			grantedCount += 1
		end
	end

	return grantedCount > 0
end

function DealShopManager.notifyDealPurchaseResult(self: DealShopManager, player: Player, dealKey: string, tierIndex: number, isSuccess: boolean)
	RemoteEvents.NotifyDealPurchaseResult:FireClient(player, dealKey, tierIndex, isSuccess)
end

function DealShopManager.tryBuyDeal(self: DealShopManager, player: Player, dealKey: any, tierIndex: any)
	if type(dealKey) ~= "string" or not isWholeNumber(tierIndex) then
		warn("DealShopManager: bad TryBuyDeal parameters from", player.Name)
		return
	end

	local dealTiers = self.tiersByDealKey[dealKey]
	local entry = dealTiers and dealTiers[tierIndex :: number]
	if not entry or entry.tier.coinCost == nil then
		warn("DealShopManager: TryBuyDeal for unknown or non-coin tier", dealKey, tierIndex, "from", player.Name)
		return
	end

	local deal = entry.deal
	local cost = entry.tier.coinCost :: number

	if deal.endTime ~= nil and deal.endTime <= workspace:GetServerTimeNow() then
		gameController:sendSystemMessageToPlayer(player, "That deal has ended")
		self:notifyDealPurchaseResult(player, dealKey, tierIndex, false)
		return
	end

	if playerAttributesManager:get(player, PlayerAttributeKeys.COINS) < cost then
		gameController:sendSystemMessageToPlayer(player, "You do not have enough coins")
		self:notifyDealPurchaseResult(player, dealKey, tierIndex, false)
		return
	end

	-- no yields between the check above and this commit, so check-and-commit is atomic
	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.COINS, cost)

	if not self:grantTier(player, deal, entry.tier, "buyCoins") then
		playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, cost)
		self:notifyDealPurchaseResult(player, dealKey, tierIndex, false)
		return
	end

	analyticsManager:logSpendCurrency(
		player,
		cost,
		playerAttributesManager:get(player, PlayerAttributeKeys.COINS),
		deal.dealKey
	)
	ftueManager:notifyBuyItemForPlayer(player)

	gameController:sendSystemMessageToPlayer(player, string.format("%s purchased!", deal.title))
	self:notifyDealPurchaseResult(player, dealKey, tierIndex, true)
end

function DealShopManager.tryBeginGift(self: DealShopManager, player: Player, productId: any, recipientUserId: any)
	if not isWholeNumber(productId) or not isWholeNumber(recipientUserId) then
		warn("DealShopManager: bad TryBeginGift parameters from", player.Name)
		return
	end

	if not self.tiersByProductId[productId :: number] then
		warn("DealShopManager: TryBeginGift for unknown product", productId, "from", player.Name)
		return
	end
	if recipientUserId == player.UserId then
		warn("DealShopManager: self-gift attempt from", player.Name)
		return
	end

	local recipient = Players:GetPlayerByUserId(recipientUserId :: number)
	if not recipient or not gameController:getPlayerData(recipient) then
		gameController:sendSystemMessageToPlayer(player, "That player is no longer here")
		return
	end

	self.pendingGiftsByPlayer[player] = {
		productId = productId :: number,
		recipientUserId = recipientUserId :: number,
		expireTime = workspace:GetServerTimeNow() + PENDING_GIFT_LIFETIME_SEC,
	}
end

function DealShopManager.tryClearGift(self: DealShopManager, player: Player)
	self.pendingGiftsByPlayer[player] = nil
end

function DealShopManager.notifyRemovePlayer(self: DealShopManager, player: Player)
	self.pendingGiftsByPlayer[player] = nil
end

function DealShopManager.takeGiftRecipient(self: DealShopManager, player: Player, productId: number): Player?
	local pendingGift = self.pendingGiftsByPlayer[player]
	if not pendingGift or pendingGift.productId ~= productId then
		return nil
	end
	self.pendingGiftsByPlayer[player] = nil

	if pendingGift.expireTime < workspace:GetServerTimeNow() then
		return nil
	end

	local recipient = Players:GetPlayerByUserId(pendingGift.recipientUserId)
	if not recipient or not gameController:getPlayerData(recipient) then
		gameController:sendSystemMessageToPlayer(player, "Gift recipient left; the purchase is yours")
		return nil
	end

	return recipient
end

function DealShopManager.grantGift(self: DealShopManager, buyer: Player, recipient: Player, entry: TierEntry): boolean
	if not self:grantTier(recipient, entry.deal, entry.tier, "buyRobuxGift") then
		return false
	end

	RemoteEvents.NotifyGiftReceived:FireClient(recipient, buyer.DisplayName, entry.deal.title)
	gameController:sendSystemMessageToPlayer(buyer, string.format("Gift sent to %s!", recipient.DisplayName))

	return true
end

-- false makes ProcessReceipt retry later
function DealShopManager.tryDeliverToPlayer(self: DealShopManager, player: Player, productId: number): boolean
	local entry = self.tiersByProductId[productId]
	if not entry then
		warn("could not find deal shop product id, should not be possible", player, productId)
		return false
	end

	local recipient = self:takeGiftRecipient(player, productId)
	if recipient then
		return self:grantGift(player, recipient, entry)
	end

	if not self:grantTier(player, entry.deal, entry.tier, "buyRobux") then
		return false
	end

	-- in case a player does a robux purchase during ftue
	task.defer(function()
		ftueManager:notifyBuyItemForPlayer(player)
	end)

	gameController:sendSystemMessageToPlayer(player, string.format("%s purchased!", entry.deal.title))

	return true
end

function DealShopManager.init(self: DealShopManager)
	self:validateConfig()
	self:buildClientConfig()
end

function DealShopManager.new(): DealShopManager
	local self = setmetatable({} :: DealShopManagerFields, DealShopManager)

	self.tiersByProductId = {}
	self.tiersByDealKey = {}
	self.pendingGiftsByPlayer = {}
	self.clientConfig = nil

	return self
end

function DealShopManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = DealShopManager.new()

return singleton
