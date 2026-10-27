--!strict

-- Shared grant logic for reward systems (playtime rewards, daily login): takes an already-resolved reward and
-- delivers it. Returns the text for the "You received ...!" message, or nil plus a message for the player when
-- nothing was delivered, so a failed grant never counts as a claim.
local RewardGranter = {}

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlaytimeRewardMath = require("@game/ReplicatedStorage/Shared/PlaytimeRewardMath")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local CurrencyGranter = require("./CurrencyGranter")
local incomeManager = require("./IncomeManager")
local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local kinds = enums.PlaytimeRewardKind

-- what a reward needs to be granted: COINS use coinAmount, TIME_SKIP uses skipSec (and minCoins, the least it pays),
-- and any other kind is an item given by itemName
export type GrantableReward = {
	kind: number,
	coinAmount: number?,
	diamondAmount: number?,
	skipSec: number?,
	minCoins: number?,
	itemName: string?,
}

-- the part of a reward every dialog shows (see RewardTileUi.RewardContent on the client)
export type RewardEntry = {
	kind: number,
	coinAmount: number?,
	diamondAmount: number?,
	skipSec: number?,
	itemName: string?,
	displayName: string?,
	rarity: number?,
}

local NO_INCOME_MESSAGE = "A time skip pays nothing without income. Place a dragon first!"
local DELIVERY_FAILED_MESSAGE = "Could not deliver your reward. Make room in your backpack and try again."

-- what a time skip pays right now: income x seconds, but never less than minCoins
function RewardGranter.getTimeSkipCoins(playerData: Types.PlayerData, skipSec: number, minCoins: number?): number
	local earned = PlaytimeRewardMath.computeTimeSkipCoins(incomeManager:getIncomePerSec(playerData), skipSec)
	return math.max(earned, minCoins or 0)
end

-- builds the client-facing record of a reward (the item's display data is looked up here)
function RewardGranter.buildRewardEntry(reward: GrantableReward): RewardEntry
	local entry: RewardEntry = {
		kind = reward.kind,
		coinAmount = reward.coinAmount,
		diamondAmount = reward.diamondAmount,
		skipSec = reward.skipSec,
		itemName = nil,
		displayName = nil,
		rarity = nil,
	}

	if reward.itemName then
		entry.itemName = reward.itemName
		local itemData = objectDataStore:getObjectDataByName(reward.itemName)
		if itemData then
			entry.displayName = itemData.displayName
			entry.rarity = itemData.rarity or enums.Rarity.COMMON
		end
	end

	return entry
end

-- returns (messageText, nil) on success and (nil, failureMessage) when nothing was delivered
function RewardGranter.grant(
	player: Player,
	playerData: Types.PlayerData,
	reward: GrantableReward,
	acquisitionSource: string
): (string?, string?)
	if reward.kind == kinds.COINS then
		local amount = reward.coinAmount :: number
		CurrencyGranter.grantCoins(player, amount, acquisitionSource)
		return `{utils.formatLargePositiveInteger(amount)} Coins`, nil
	elseif reward.kind == kinds.DIAMONDS then
		local amount = reward.diamondAmount :: number
		CurrencyGranter.grantDiamonds(player, amount, acquisitionSource)
		return `{utils.formatLargePositiveInteger(amount)} Diamonds`, nil
	elseif reward.kind == kinds.TIME_SKIP then
		local amount = RewardGranter.getTimeSkipCoins(playerData, reward.skipSec :: number, reward.minCoins)
		if amount < 1 then
			return nil, NO_INCOME_MESSAGE
		end
		CurrencyGranter.grantCoins(player, amount, acquisitionSource)
		return `a {utils.formatLargePositiveInteger(amount)} Coin Time Skip`, nil
	end

	local itemName = reward.itemName :: string
	if not gameController:tryDeliverPurchasedItemToPlayer(player, itemName, 1) then
		warn("RewardGranter: failed to grant", itemName, "to", player)
		return nil, DELIVERY_FAILED_MESSAGE
	end

	local itemData = objectDataStore:getObjectDataByName(itemName)
	analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
		objectName = itemName,
		rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
		itemType = itemData.type,
		acquisitionSource = acquisitionSource,
		quantity = 1,
	})

	return utils.getColoredTextForRarity(itemData.displayName or itemName, itemData.rarity), nil
end

function RewardGranter.initClass(deps: any)
	gameController = deps.gameController
end

return RewardGranter
