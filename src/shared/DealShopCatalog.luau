--!strict

-- validation for the Studio-only GameData/Control/DealShop config; the config sent to clients has
-- the same shape plus a few server-filled display fields, so the client reuses these types

local enums = require("./Enums")

local DealShopCatalog = {}

export type DealContent = {
	kind: number, -- Enums.ShopContentKind
	amount: number?, -- COINS
	objectName: string?, -- ITEM
	count: number?, -- ITEM
	displayName: string?, -- ITEM; filled server-side from ObjectDataStore
	rarity: number?, -- ITEM; filled server-side from ObjectDataStore (Enums.Rarity)
}

-- a tier is priced either in Robux (productId, a dev product) or in coins (coinCost); never both
export type Tier = {
	productId: number?,
	coinCost: number?,
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
	tiers: { Tier },
}

export type Section = {
	sectionKey: string,
	title: string,
	deals: { Deal },
}

export type DealShopConfig = {
	SECTIONS: { Section },
}

local MAX_TIERS = 2

function DealShopCatalog.parseIsoDate(isoDate: string): number?
	local dateTime = DateTime.fromIsoDate(isoDate)
	return if dateTime then dateTime.UnixTimestamp else nil
end

local function validateContent(errors: { string }, where: string, content: DealContent)
	if not enums.isValidValue(enums.ShopContentKind, content.kind) then
		table.insert(errors, `{where}: invalid content kind {tostring(content.kind)}`)
		return
	end

	if content.kind == enums.ShopContentKind.COINS then
		if type(content.amount) ~= "number" or content.amount <= 0 or content.amount ~= math.floor(content.amount) then
			table.insert(errors, `{where}: COINS content needs integer amount > 0`)
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

local function validateTier(errors: { string }, tierWhere: string, tier: Tier, seenProductIds: { [number]: boolean })
	local productId = tier.productId
	local coinCost = tier.coinCost

	if coinCost ~= nil then
		if productId ~= nil then
			table.insert(errors, `{tierWhere}: set either productId or coinCost, not both`)
		end
		if type(coinCost) ~= "number" or coinCost <= 0 or coinCost ~= math.floor(coinCost) then
			table.insert(errors, `{tierWhere}: coinCost must be an integer > 0`)
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
		table.insert(errors, `{where}: two tiers must be one Robux tier and one coin tier`)
	end
	if type(first.contents) ~= "table" or type(second.contents) ~= "table" then
		return
	end

	local isSingleItem = deal.cardStyle == enums.ShopCardStyle.SINGLE_ITEM
	if describeTierContents(first, not isSingleItem) ~= describeTierContents(second, not isSingleItem) then
		table.insert(errors, if isSingleItem then `{where}: both tiers must sell the same item` else `{where}: both tiers must grant identical contents`)
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
	if type(deal.tiers) ~= "table" or #deal.tiers == 0 or #deal.tiers > MAX_TIERS then
		table.insert(errors, `{where}: needs 1-{MAX_TIERS} tiers`)
		return
	end

	for tierIndex, tier in deal.tiers do
		validateTier(errors, `{where} tier {tierIndex}`, tier, seenProductIds)
	end

	if #deal.tiers == 2 then
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

	for _, section in config.SECTIONS do
		if type(section.sectionKey) ~= "string" or section.sectionKey == "" then
			table.insert(errors, "section with missing/empty sectionKey")
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
		end
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
