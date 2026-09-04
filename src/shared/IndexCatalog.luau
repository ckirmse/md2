--!strict

local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local IndexCatalog = {}

IndexCatalog.Category = {
	DRAGONS = "dragons",
	PLANTS = "plants",
	CRYSTALS = "crystals",
	BLUEPRINTS = "blueprints",
	ABILITIES = "abilities",
	MUTATIONS = "mutations",
}

IndexCatalog.CategoryDisplay = {
	[IndexCatalog.Category.DRAGONS] = { name = "Dragons", order = 1 },
	[IndexCatalog.Category.PLANTS] = { name = "Plants", order = 2 },
	[IndexCatalog.Category.CRYSTALS] = { name = "Crystals", order = 3 },
	[IndexCatalog.Category.BLUEPRINTS] = { name = "Blueprints", order = 4 },
	[IndexCatalog.Category.ABILITIES] = { name = "Skills", order = 5 },
	[IndexCatalog.Category.MUTATIONS] = { name = "Mutations", order = 6 },
}

IndexCatalog.CategoryAxes = {
	[IndexCatalog.Category.DRAGONS] = { element = true, rarity = true, chainKeyHasRarity = true, section = false },
	[IndexCatalog.Category.PLANTS] = { element = true, rarity = true, chainKeyHasRarity = true, section = false },
	[IndexCatalog.Category.CRYSTALS] = { element = true, rarity = false, chainKeyHasRarity = true, section = false },
	[IndexCatalog.Category.BLUEPRINTS] = { element = false, rarity = true, chainKeyHasRarity = false, section = true },
	[IndexCatalog.Category.ABILITIES] = { element = true, rarity = false, chainKeyHasRarity = false, section = false },
	[IndexCatalog.Category.MUTATIONS] = { element = false, rarity = false, chainKeyHasRarity = false, section = false },
}

local RARITY_ORDER: { number } = { enums.Rarity.COMMON, enums.Rarity.UNCOMMON, enums.Rarity.RARE, enums.Rarity.EPIC }

function IndexCatalog.getCategoriesSorted(): { string }
	local categories: { string } = {}
	for _, category in IndexCatalog.Category :: { [string]: string } do
		table.insert(categories, category)
	end

	table.sort(categories, function(a: string, b: string): boolean
		return IndexCatalog.CategoryDisplay[a].order < IndexCatalog.CategoryDisplay[b].order
	end)

	return categories
end

function IndexCatalog.validateCategory(category: string?): boolean
	for _, validCategory in IndexCatalog.Category :: { [string]: string } do
		if validCategory == category then
			return true
		end
	end

	return false
end

function IndexCatalog.getCandidateChainKeysForCategory(category: string): { string }
	local categoryAxes = IndexCatalog.CategoryAxes[category]
	if not categoryAxes or not categoryAxes.element then
		return {}
	end

	local hasRarityInKey = categoryAxes.chainKeyHasRarity == true

	local chainKeys: { string } = {}
	for _, primaryElement in Elements.getPrimaryElementsSorted() do
		-- every primary element and rarity has a public name, so the asserts cannot fire
		local elementName = assert(enums.getPublicName(enums.PrimaryElements, primaryElement))
		if hasRarityInKey then
			for _, rarity in RARITY_ORDER do
				local rarityName = assert(enums.getPublicName(enums.Rarity, rarity))
				table.insert(chainKeys, elementName .. "_" .. rarityName)
			end
		else
			table.insert(chainKeys, elementName)
		end
	end

	return chainKeys
end

return IndexCatalog
