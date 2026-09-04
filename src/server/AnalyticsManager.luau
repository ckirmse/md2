--!strict

local AnalyticsManager = {}
AnalyticsManager.__index = AnalyticsManager

local analyticsService = game:GetService("AnalyticsService")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local Trail = require("./Libs/Trail")

local Types = require("./Types")
local gameController: Types.GameController

type AnalyticsManagerFields = {}

export type AnalyticsManager = typeof(setmetatable({} :: AnalyticsManagerFields, AnalyticsManager))

AnalyticsManager.Events = {
	FirstPlay = "FirstPlay",
	GainLevel = "GainLevel",
	Merge = "Merge",
	SellGems = "SellGems",
	BuyItem = "BuyItem",
	MineNode = "MineNode",
	Harvest = "Harvest",
	RideDragon = "RideDragon",
	StartOpenCrystal = "StartOpenCrystal",
	ClaimCrystal = "ClaimCrystal",
	ApplyFlame = "ApplyFlame",
	EquipAbility = "EquipAbility",
	UnequipAbility = "UnequipAbility",
	--- Ftue* (suffix is the ftue step name)
	FtueBuyItem = "FtueBuyItem",
	FtueComplete = "FtueComplete",
	GainItem = "GainItem",
	LoseItem = "LoseItem",
	GainMutation = "GainMutation",
	FirstSessionOfferStarted = "FirstSessionOfferStarted",
	FirstSessionOfferRedeemable = "FirstSessionOfferRedeemable",
	FirstSessionOfferRedeemed = "FirstSessionOfferRedeemed",
	CodeRedeemed = "CodeRedeemed",
	CodeUnknown = "CodeUnknown",
	CodeExpired = "CodeExpired",
	CodeDuplicate = "CodeDuplicate",
	SendTradeRequest = "SendTradeRequest",
	AcceptTradeRequest = "AcceptTradeRequest",
	DeclineTradeRequest = "DeclineTradeRequest",
	ExecuteTrade = "ExecuteTrade",
	MigratePreProfileSaveData = "MigratePreProfileSaveData",
	OfflineGems = "OfflineGems",
	OpenChest = "OpenChest",
	UnlockVanityComponent = "UnlockVanityComponent",
	UnlockVanityArea = "UnlockVanityArea",
	PromptGroup = "PromptGroup",
}

AnalyticsManager.ClientEvents = {
	FtueOpenBuyStore = "FtueOpenBuyStore",
	RecreateShadowCaster = "RecreateShadowCaster",
}

AnalyticsManager.CurrencyEvents = {
	GainCurrency = "GainCurrency",
	SpendCurrency = "SpendCurrency",
}

-- amount is amount of coins gained
-- totalBalance is amount of coins when done
-- object name is what was sold to gain the coins
function AnalyticsManager.logGainCurrency(self: AnalyticsManager, player: Player, amount: number, totalBalance: number, objectName: string?)
	analyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Coins", amount, totalBalance, Enum.AnalyticsEconomyTransactionType.Shop.Name)
	Trail:PlayerEvent(player, AnalyticsManager.CurrencyEvents.GainCurrency, {amount = amount, totalBalance = totalBalance, objectName = objectName})
end

function AnalyticsManager.logSpendCurrency(self: AnalyticsManager, player: Player, amount: number, totalBalance: number, objectName: string?)
	analyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Coins", amount, totalBalance, Enum.AnalyticsEconomyTransactionType.Shop.Name, objectName)
	Trail:PlayerEvent(player, AnalyticsManager.CurrencyEvents.SpendCurrency, {amount = amount, totalBalance = totalBalance, objectName = objectName})
end

function AnalyticsManager.getFtueAnalyticsEventName(self: AnalyticsManager, stepName: string): string
	return "Ftue" .. utils.capitalize(stepName)
end

function AnalyticsManager.tryLogClientEvent(self: AnalyticsManager, player: Player, eventName: string, properties: { [string]: any })
	if not AnalyticsManager.ClientEvents[eventName] then
		print("invalid client analytics event name", eventName)
		return
	end

	properties.fromClient = true

	self:logEvent(player, eventName, properties)
end

function AnalyticsManager.logEvent(self: AnalyticsManager, player: Player?, eventName: string?, properties: { [string]: any })
	if not eventName then
		warn("nil event name to logEvent")
		return
	end

	if not AnalyticsManager.Events[eventName] and not AnalyticsManager.ClientEvents[eventName] and string.sub(eventName, 1, 4) ~= "Ftue" then
		warn("unknown analytics event name", eventName)
		return
	end

	if eventName == AnalyticsManager.Events.GainItem or eventName == AnalyticsManager.Events.LoseItem then
		-- not sending them as of 2026-may-7
		return
	end

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local creationTime = playerData:getCreationTime()
	local joinDateStr: string
	if creationTime then
		joinDateStr = DateTime.fromUnixTimestamp(creationTime):FormatUniversalTime("YYYY-MM-DD", "en-us")
	else
		joinDateStr = ""
	end

	-- we modify properties rather than copy it, because caller just makes a new static one every time anyway
	properties.joinDate = joinDateStr

	if player then
		Trail:PlayerEvent(player, eventName, properties)
	else
		Trail:Event(eventName, properties)
	end

	--[[
	-- send to roblox

	if not properties or not next(properties) then
		-- no properties, send blank
		analyticsService:LogCustomEvent(player, eventName)
	else
		local custom1 = nil
		local custom2 = nil
		local custom3 = nil

		if properties.objectName then
			custom1 = properties.objectName
		end

		local customFields = {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = custom1,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = custom2,
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = custom3
		}
		analyticsService:LogCustomEvent(player, eventName, 0, customFields)
		end
	]]
end

function AnalyticsManager.logPurchase(self: AnalyticsManager, player: Player, receiptInfo: any)
	Trail:ReceiptEvent(receiptInfo, Enum.ProductPurchaseDecision.PurchaseGranted)
end

function AnalyticsManager.init(self: AnalyticsManager)
	Trail:Start()
end

function AnalyticsManager.new(): AnalyticsManager
	local self: AnalyticsManager = setmetatable({} :: AnalyticsManagerFields, AnalyticsManager)
	return self
end

function AnalyticsManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = AnalyticsManager.new()

return singleton
