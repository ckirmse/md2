--!strict

-- HUD featured-deal rotation. The config lives in Studio-only GameData/Control/FeaturedDeals (an ordered array of
-- single-tier Robux deals plus a rotation period) and is sent to clients in the same shape (see DealShopManager), so this
-- module serves validation on the server and rotation math on both sides. The featured index is a pure function of
-- server time so every player sees the same deal at the same moment.
local DealShopCatalog = require("./DealShopCatalog")
local enums = require("./Enums")

local FeaturedDealCatalog = {}

-- a featured deal is promoted by the HUD button alone: one Robux tier, no card, never gifted and never one-time
export type FeaturedTier = {
	productId: number,
	contents: { DealShopCatalog.DealContent },
}

export type FeaturedDeal = {
	dealKey: string,
	title: string,
	icon: string,
	startDate: string?, -- ISO 8601 UTC, as in the Deal Shop; hidden before this
	endDate: string?, -- ISO 8601 UTC; skipped after this
	startTime: number?, -- startDate and endDate as server times, filled server-side for clients
	endTime: number?,
	tiers: { FeaturedTier },
}

export type FeaturedDealsConfig = {
	rotationSec: number,
	deals: { FeaturedDeal },
}

function FeaturedDealCatalog.validate(config: FeaturedDealsConfig): { string }
	local errors: { string } = {}
	if type(config) ~= "table" or type(config.deals) ~= "table" then
		table.insert(errors, "config needs a deals array")
		return errors
	end
	if type(config.rotationSec) ~= "number" or config.rotationSec <= 0 then
		table.insert(errors, "rotationSec must be a number > 0")
	end

	local seenDealKeys: { [string]: boolean } = {}
	local seenProductIds: { [number]: boolean } = {}
	for dealIndex, deal in config.deals do
		if type(deal.dealKey) ~= "string" or deal.dealKey == "" then
			table.insert(errors, `featured deal number {dealIndex} has a missing/empty dealKey`)
			continue
		end
		local where = `featured deal {deal.dealKey}`
		if seenDealKeys[deal.dealKey] then
			table.insert(errors, `{where}: duplicate dealKey`)
		end
		seenDealKeys[deal.dealKey] = true

		if type(deal.icon) ~= "string" or deal.icon == "" then
			table.insert(errors, `{where}: needs a non-empty icon`)
		end

		-- a promo that repeats must be buyable repeatedly, and the HUD button cannot start a gift
		local looseDeal = deal :: any
		if looseDeal.oneTimeOnly ~= nil then
			table.insert(errors, `{where}: a featured deal cannot set oneTimeOnly`)
		end
		if looseDeal.giftable ~= nil then
			table.insert(errors, `{where}: a featured deal cannot set giftable (it is never gifted)`)
		end
		if looseDeal.stock ~= nil then
			table.insert(errors, `{where}: a featured deal cannot set stock`)
		end

		if type(deal.tiers) ~= "table" or #deal.tiers ~= 1 then
			table.insert(errors, `{where}: needs exactly 1 tier`)
			continue
		end
		if (deal.tiers[1] :: any).coinCost ~= nil or (deal.tiers[1] :: any).diamondCost ~= nil then
			table.insert(errors, `{where}: the tier must be a Robux tier (productId), not coinCost or diamondCost`)
		end

		-- the rest of the rules are the Deal Shop's; a featured deal has no card, so it is checked as a bundle
		local checkedDeal = table.clone(deal) :: any
		checkedDeal.cardStyle = enums.ShopCardStyle.BUNDLE
		DealShopCatalog.validateDeal(errors, where, checkedDeal, seenProductIds)
	end

	return errors
end

export type EligibilityPredicate = (deal: FeaturedDeal) -> boolean

-- the deals that can be featured right now. isEligible lets a client drop deals the local player can't buy before the
-- rotation slot is picked (nothing uses it yet: this game has no per-player featured filter)
function FeaturedDealCatalog.getActiveDeals(config: FeaturedDealsConfig, now: number, isEligible: EligibilityPredicate?): { FeaturedDeal }
	local active: { FeaturedDeal } = {}
	for _, deal in config.deals do
		if deal.startTime ~= nil and deal.startTime > now then
			continue
		end
		if deal.endTime ~= nil and deal.endTime <= now then
			continue
		end
		if isEligible and not isEligible(deal) then
			continue
		end
		table.insert(active, deal)
	end
	return active
end

function FeaturedDealCatalog.getFeaturedDeal(config: FeaturedDealsConfig, now: number, isEligible: EligibilityPredicate?): FeaturedDeal?
	local active = FeaturedDealCatalog.getActiveDeals(config, now, isEligible)
	if #active == 0 then
		return nil
	end
	local slot = math.floor(now / config.rotationSec)
	return active[(slot % #active) + 1]
end

function FeaturedDealCatalog.getNextRotationTime(config: FeaturedDealsConfig, now: number): number
	return (math.floor(now / config.rotationSec) + 1) * config.rotationSec
end

return FeaturedDealCatalog
