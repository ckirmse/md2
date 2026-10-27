--!strict

-- validation for the Studio-only GameData/Control/DealShop config; the config sent to clients has
-- the same shape plus a few server-filled display fields, so the client reuses these types

local enums = require("./Enums")

local DealShopCatalog = {}

export type GachaPrize = {
	itemName: string,
	displayName: string,
	rarity: number, -- Enums.Rarity
	odds: number, -- 0..1 fraction of the egg's hatch loot table
}

export type DealContent = {
	kind: number, -- Enums.ShopContentKind
	amount: number?, -- COINS, DIAMONDS
	objectName: string?, -- ITEM
	count: number?, -- ITEM
	displayName: string?, -- ITEM; filled server-side from ObjectDataStore
	rarity: number?, -- ITEM; filled server-side from ObjectDataStore (Enums.Rarity)
	prizes: { GachaPrize }?, -- ITEM in a GACHA deal; filled server-side from the egg's hatch loot table
}

-- a tier is priced in exactly one currency: Robux (productId, a dev product), coins (coinCost) or Diamonds (diamondCost)
-- one roll group of a deal's stock per restock: `count` rolls, each succeeding with `percent` (0 to 100) chance
export type StockEntry = {
	count: number,
	percent: number,
}

export type Tier = {
	productId: number?,
	coinCost: number?,
	diamondCost: number?,
	slashRobux: number?, -- struck-through "original" price shown next to the live price; Robux tiers only
	contents: { DealContent },
}

export type Deal = {
	dealKey: string,
	title: string,
	cardStyle: number, -- Enums.ShopCardStyle
	icon: string?,
	tooltip: string?,
	giftable: boolean?, -- false hides Gift and refuses gifts; oneTimeOnly deals are never giftable
	oneTimeOnly: boolean?, -- each player can buy it once
	startDate: string?, -- ISO 8601 UTC; hidden before this
	endDate: string?, -- ISO 8601 UTC; hidden (and counted down to) after this
	startTime: number?, -- startDate and endDate as server times, filled server-side for clients
	endTime: number?,
	stock: { StockEntry }?, -- units each player can buy per restock; the server rolls them, clients never see this list
	hasStock: boolean?, -- filled server-side for clients when the deal has stock
	tiers: { Tier },
}

export type Section = {
	sectionKey: string,
	title: string,
	deals: { Deal },
}

export type DealShopConfig = {
	SECTIONS: { Section },
	RESTOCK_SEC: number?, -- seconds between restocks; required when any deal has stock
}

local MAX_TIERS = 2
local GACHA_MAX_TIERS = 3

function DealShopCatalog.parseIsoDate(isoDate: string): number?
	local dateTime = DateTime.fromIsoDate(isoDate)
	return if dateTime then dateTime.UnixTimestamp else nil
end

local function validateContent(errors: { string }, where: string, content: DealContent)
	if not enums.isValidValue(enums.ShopContentKind, content.kind) then
		table.insert(errors, `{where}: invalid content kind {tostring(content.kind)}`)
		return
	end

	if content.kind == enums.ShopContentKind.COINS or content.kind == enums.ShopContentKind.DIAMONDS then
		if type(content.amount) ~= "number" or content.amount <= 0 or content.amount ~= math.floor(content.amount) then
			table.insert(errors, `{where}: {if content.kind == enums.ShopContentKind.COINS then "COINS" else "DIAMONDS"} content needs integer amount > 0`)
		end
	elseif content.kind == enums.ShopContentKind.ITEM then
		if type(content.objectName) ~= "string" or content.objectName == "" then
			table.insert(errors, `{where}: ITEM content needs a non-empty objectName`)
		end
		if type(content.count) ~= "number" or content.count <= 0 or content.count ~= math.floor(content.count) then
			table.insert(errors, `{where}: ITEM content needs integer count > 0`)
		end
	end
end

local function isRobuxTier(tier: Tier): boolean
	return tier.productId ~= nil
end

local function getTierCurrency(tier: Tier): string
	if tier.productId ~= nil then
		return "robux"
	end

	return if tier.diamondCost ~= nil then "diamonds" else "coins"
end

local function validateTier(errors: { string }, tierWhere: string, tier: Tier, seenProductIds: { [number]: boolean })
	local productId = tier.productId
	local coinCost = tier.coinCost
	local diamondCost = tier.diamondCost

	local priceCount = (if productId ~= nil then 1 else 0) + (if coinCost ~= nil then 1 else 0) + (if diamondCost ~= nil then 1 else 0)
	if priceCount > 1 then
		table.insert(errors, `{tierWhere}: set only one of productId, coinCost and diamondCost`)
	end

	if coinCost ~= nil or diamondCost ~= nil then
		if coinCost ~= nil and (type(coinCost) ~= "number" or coinCost <= 0 or coinCost ~= math.floor(coinCost)) then
			table.insert(errors, `{tierWhere}: coinCost must be an integer > 0`)
		end
		if diamondCost ~= nil and (type(diamondCost) ~= "number" or diamondCost <= 0 or diamondCost ~= math.floor(diamondCost)) then
			table.insert(errors, `{tierWhere}: diamondCost must be an integer > 0`)
		end
		if tier.slashRobux ~= nil then
			table.insert(errors, `{tierWhere}: slashRobux is only for Robux tiers`)
		end
	elseif type(productId) ~= "number" or productId <= 0 or productId ~= math.floor(productId) then
		table.insert(errors, `{tierWhere}: invalid productId`)
	else
		if seenProductIds[productId] then
			table.insert(errors, `{tierWhere}: duplicate productId {productId}`)
		end
		seenProductIds[productId] = true
	end

	if tier.slashRobux ~= nil
		and (type(tier.slashRobux) ~= "number" or tier.slashRobux <= 0 or tier.slashRobux ~= math.floor(tier.slashRobux))
	then
		table.insert(errors, `{tierWhere}: slashRobux must be nil or an integer > 0`)
	end

	if type(tier.contents) ~= "table" or #tier.contents == 0 then
		table.insert(errors, `{tierWhere}: needs at least one content entry`)
		return
	end
	for _, content in tier.contents do
		validateContent(errors, tierWhere, content)
	end
end

local function describeTierContents(tier: Tier, includeCounts: boolean): string
	local parts: { string } = {}
	for _, content in tier.contents do
		local counts = if includeCounts then `:{tostring(content.count)}:{tostring(content.amount)}` else ""
		table.insert(parts, `{content.kind}:{tostring(content.objectName)}{counts}`)
	end
	return table.concat(parts, ",")
end

-- a deal with two tiers is one offering sold two ways, one Robux tier and one coin tier; a single item may
-- differ in count between them (a bigger pack for Robux), a bundle must grant the same contents in both
local function validateTierPair(errors: { string }, where: string, deal: Deal)
	local first = deal.tiers[1]
	local second = deal.tiers[2]
	if isRobuxTier(first) == isRobuxTier(second) then
		table.insert(errors, `{where}: two tiers must be one Robux tier and one coin or Diamond tier`)
	end
	if type(first.contents) ~= "table" or type(second.contents) ~= "table" then
		return
	end

	local isSingleItem = deal.cardStyle == enums.ShopCardStyle.SINGLE_ITEM
	if describeTierContents(first, not isSingleItem) ~= describeTierContents(second, not isSingleItem) then
		table.insert(errors, if isSingleItem then `{where}: both tiers must sell the same item` else `{where}: both tiers must grant identical contents`)
	end
end

-- a gacha deal sells packs of one egg: a single ITEM per tier, the same egg in every tier, growing pack
-- sizes, and one currency across the tiers
local function validateGachaTiers(errors: { string }, where: string, deal: Deal)
	local firstContent: DealContent? = nil
	local previousCount = 0

	for tierIndex, tier in deal.tiers do
		if type(tier.contents) ~= "table" then
			continue
		end

		local tierWhere = `{where} tier {tierIndex}`
		local content = tier.contents[1]
		if #tier.contents ~= 1 or content.kind ~= enums.ShopContentKind.ITEM then
			table.insert(errors, `{tierWhere}: GACHA tiers need exactly 1 ITEM content entry`)
			continue
		end

		if firstContent == nil then
			firstContent = content
		elseif content.objectName ~= firstContent.objectName then
			table.insert(errors, `{tierWhere}: every GACHA tier must sell the same item as tier 1`)
		end

		if type(content.count) == "number" then
			if content.count <= previousCount then
				table.insert(errors, `{tierWhere}: GACHA pack sizes must grow from tier to tier`)
			end
			previousCount = content.count
		end

		if getTierCurrency(tier) ~= getTierCurrency(deal.tiers[1]) then
			table.insert(errors, `{tierWhere}: every GACHA tier must use the same currency`)
		end
	end
end

function DealShopCatalog.validateDeal(errors: { string }, where: string, deal: Deal, seenProductIds: { [number]: boolean })
	if type(deal.title) ~= "string" or deal.title == "" then
		table.insert(errors, `{where}: missing/empty title`)
	end
	if deal.icon ~= nil and (type(deal.icon) ~= "string" or deal.icon == "") then
		table.insert(errors, `{where}: icon must be nil or a non-empty string`)
	end
	if deal.giftable ~= nil and type(deal.giftable) ~= "boolean" then
		table.insert(errors, `{where}: giftable must be nil or a boolean`)
	end
	if deal.oneTimeOnly ~= nil and type(deal.oneTimeOnly) ~= "boolean" then
		table.insert(errors, `{where}: oneTimeOnly must be nil or a boolean`)
	end
	if deal.oneTimeOnly == true and deal.giftable == true then
		table.insert(errors, `{where}: oneTimeOnly deals cannot be giftable`)
	end
	if deal.stock ~= nil then
		if type(deal.stock) ~= "table" or #deal.stock == 0 then
			table.insert(errors, where .. ": stock must be a non-empty array of { count, percent }")
		else
			for stockIndex, stockEntry in deal.stock do
				local isCountValid = type(stockEntry.count) == "number" and stockEntry.count > 0 and stockEntry.count == math.floor(stockEntry.count)
				local isPercentValid = type(stockEntry.percent) == "number" and stockEntry.percent >= 0 and stockEntry.percent <= 100
				if not isCountValid or not isPercentValid then
					table.insert(errors, `{where} stock entry {stockIndex}: count must be an integer > 0 and percent between 0 and 100`)
				end
			end
		end
	end

	local startTime: number? = nil
	local endTime: number? = nil
	if deal.startDate ~= nil then
		startTime = if type(deal.startDate) == "string" then DealShopCatalog.parseIsoDate(deal.startDate) else nil
		if not startTime then
			table.insert(errors, `{where}: startDate must be an ISO 8601 date such as 2026-10-01T00:00:00Z`)
		end
	end
	if deal.endDate ~= nil then
		endTime = if type(deal.endDate) == "string" then DealShopCatalog.parseIsoDate(deal.endDate) else nil
		if not endTime then
			table.insert(errors, `{where}: endDate must be an ISO 8601 date such as 2026-10-15T00:00:00Z`)
		end
	end
	if startTime and endTime and startTime >= endTime then
		table.insert(errors, `{where}: startDate must be before endDate`)
	end
	if not enums.isValidValue(enums.ShopCardStyle, deal.cardStyle) then
		table.insert(errors, `{where}: invalid cardStyle {tostring(deal.cardStyle)}`)
		return
	end
	local isGacha = deal.cardStyle == enums.ShopCardStyle.GACHA
	local maxTiers = if isGacha then GACHA_MAX_TIERS else MAX_TIERS
	if type(deal.tiers) ~= "table" or #deal.tiers == 0 or #deal.tiers > maxTiers then
		table.insert(errors, `{where}: needs 1-{maxTiers} tiers`)
		return
	end

	for tierIndex, tier in deal.tiers do
		validateTier(errors, `{where} tier {tierIndex}`, tier, seenProductIds)
	end

	if isGacha then
		validateGachaTiers(errors, where, deal)
	elseif #deal.tiers == 2 then
		validateTierPair(errors, where, deal)
	end

	if deal.cardStyle == enums.ShopCardStyle.SINGLE_ITEM then
		for tierIndex, tier in deal.tiers do
			if type(tier.contents) == "table" and #tier.contents ~= 1 then
				table.insert(errors, `{where} tier {tierIndex}: SINGLE_ITEM deals need exactly 1 content entry`)
			elseif type(tier.contents) == "table" and tier.contents[1].kind ~= enums.ShopContentKind.ITEM then
				table.insert(errors, `{where} tier {tierIndex}: SINGLE_ITEM content must be an ITEM`)
			end
		end
	end
end

function DealShopCatalog.validate(config: DealShopConfig): { string }
	local errors: { string } = {}
	if type(config) ~= "table" or type(config.SECTIONS) ~= "table" then
		table.insert(errors, "config needs a SECTIONS array")
		return errors
	end

	local seenSectionKeys: { [string]: boolean } = {}
	local seenDealKeys: { [string]: boolean } = {}
	local seenProductIds: { [number]: boolean } = {}
	local hasStockDeal = false

	for sectionIndex, section in config.SECTIONS do
		if type(section.sectionKey) ~= "string" or section.sectionKey == "" then
			local hint = if (section :: any).dealKey then ` (it has a dealKey, {tostring((section :: any).dealKey)}: a deal placed directly in SECTIONS instead of inside a section's deals)` else ""
			table.insert(errors, `SECTIONS[{sectionIndex}] has a missing/empty sectionKey{hint}`)
			continue
		end
		local sectionWhere = `section {section.sectionKey}`
		if seenSectionKeys[section.sectionKey] then
			table.insert(errors, `{sectionWhere}: duplicate sectionKey`)
		end
		seenSectionKeys[section.sectionKey] = true
		if type(section.title) ~= "string" or section.title == "" then
			table.insert(errors, `{sectionWhere}: missing/empty title`)
		end
		if type(section.deals) ~= "table" or #section.deals == 0 then
			table.insert(errors, `{sectionWhere}: needs at least one deal`)
			continue
		end

		for _, deal in section.deals do
			if type(deal.dealKey) ~= "string" or deal.dealKey == "" then
				table.insert(errors, `{sectionWhere}: deal with missing/empty dealKey`)
				continue
			end
			local where = `deal {deal.dealKey}`
			if seenDealKeys[deal.dealKey] then
				table.insert(errors, `{where}: duplicate dealKey`)
			end
			seenDealKeys[deal.dealKey] = true
			DealShopCatalog.validateDeal(errors, where, deal, seenProductIds)
			if deal.stock ~= nil then
				hasStockDeal = true
			end
		end
	end

	if config.RESTOCK_SEC ~= nil and (type(config.RESTOCK_SEC) ~= "number" or config.RESTOCK_SEC <= 0) then
		table.insert(errors, "RESTOCK_SEC must be a number > 0")
	elseif hasStockDeal and config.RESTOCK_SEC == nil then
		table.insert(errors, "RESTOCK_SEC (seconds between restocks) is required when a deal has stock")
	end

	return errors
end

function DealShopCatalog.getAllProductIds(config: DealShopConfig): { number }
	local productIds: { number } = {}
	for _, section in config.SECTIONS do
		for _, deal in section.deals do
			for _, tier in deal.tiers do
				if tier.productId then
					table.insert(productIds, tier.productId)
				end
			end
		end
	end
	return productIds
end

return DealShopCatalog
