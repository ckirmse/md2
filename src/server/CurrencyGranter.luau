--!strict

local CurrencyGranter = {}

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local analyticsManager = require("./AnalyticsManager")
local playerAttributesManager = require("./PlayerAttributesManager")

local DIAMONDS_CURRENCY_NAME = "Diamonds"

function CurrencyGranter.grantCoins(player: Player, amount: number, acquisitionSource: string)
	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, amount)
	analyticsManager:logGainCurrency(player, amount, playerAttributesManager:get(player, PlayerAttributeKeys.COINS), acquisitionSource)
end

function CurrencyGranter.getDiamonds(player: Player): number
	return playerAttributesManager:get(player, PlayerAttributeKeys.DIAMONDS) or 0
end

function CurrencyGranter.grantDiamonds(player: Player, amount: number, acquisitionSource: string)
	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.DIAMONDS, amount)
	analyticsManager:logGainCurrency(
		player,
		amount,
		CurrencyGranter.getDiamonds(player),
		acquisitionSource,
		DIAMONDS_CURRENCY_NAME
	)
end

-- returns false and spends nothing when the amount is not a positive whole number or the player cannot afford it
function CurrencyGranter.trySpendDiamonds(player: Player, amount: number, spendReason: string): boolean
	if amount < 1 or amount ~= math.floor(amount) then
		warn("CurrencyGranter: invalid diamond amount to spend", amount, spendReason)
		return false
	end

	if CurrencyGranter.getDiamonds(player) < amount then
		return false
	end

	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.DIAMONDS, amount)
	analyticsManager:logSpendCurrency(player, amount, CurrencyGranter.getDiamonds(player), spendReason, DIAMONDS_CURRENCY_NAME)
	return true
end

return CurrencyGranter
