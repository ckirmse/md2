--!strict

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local Abilities = {}

export type AbilityData = {
	ability: number,
	-- the ability this one is an upgrade of; only present on tier 2/3 abilities
	replaceAbility: number?,
	upgradeBadgeText: string?,
	primaryElement: number,
	displayName: string,
	description: string,
	unlockLevel: number,
	storeImageAssetId: number,
	equipGemCount: number,
}

export type AttributeAbilityData = {
	key: string,
	abilities: { number },
	isClient: boolean,
}

local AbilityDatas: { AbilityData } = {
	-- beginning of green abilities
	{
		ability = enums.Abilities.MERGE_CIRCLE_SIZE_1,
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Fuse Master",
		description = "Extends your fuse range",
		unlockLevel = 5,
		storeImageAssetId = 113613676930076,
		equipGemCount = 25,
	},
	{
		ability = enums.Abilities.MERGE_CIRCLE_SIZE_2,
		replaceAbility = enums.Abilities.MERGE_CIRCLE_SIZE_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Fuse Master 2",
		description = "Extends your fuse range much more",
		unlockLevel = 25,
		storeImageAssetId = 113613676930076,
		equipGemCount = 150,
	},
	{
		ability = enums.Abilities.MERGE_CIRCLE_SIZE_3,
		replaceAbility = enums.Abilities.MERGE_CIRCLE_SIZE_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Fuse Master 3",
		description = "Extends your fuse range way more",
		unlockLevel = 70,
		storeImageAssetId = 113613676930076,
		equipGemCount = 2400,
	},
	{
		ability = enums.Abilities.MERGE_CROP_GET_SEED_1,
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Master Planter",
		description = "Chance for a bonus seed when fusing plants",
		unlockLevel = 75,
		storeImageAssetId = 80265249209557,
		equipGemCount = 3000,
	},
	{
		ability = enums.Abilities.MERGE_CROP_GET_SEED_2,
		replaceAbility = enums.Abilities.MERGE_CROP_GET_SEED_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Master Planter 2",
		description = "Improved chance for a bonus seed when fusing plants",
		unlockLevel = 90,
		storeImageAssetId = 80265249209557,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.MERGE_CROP_GET_SEED_3,
		replaceAbility = enums.Abilities.MERGE_CROP_GET_SEED_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Master Planter 3",
		description = "Greatly improved chance for a bonus seed when fusing plants",
		unlockLevel = 100,
		storeImageAssetId = 80265249209557,
		equipGemCount = 5250,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_SEED_1,
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Green Thumb",
		description = "Chance for a bonus seed when harvesting",
		unlockLevel = 55,
		storeImageAssetId = 90416195015728,
		equipGemCount = 650,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_SEED_2,
		replaceAbility = enums.Abilities.HARVEST_CROP_GET_SEED_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Green Thumb 2",
		description = "Improved chance for a bonus seed when harvesting",
		unlockLevel = 80,
		storeImageAssetId = 90416195015728,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_SEED_3,
		replaceAbility = enums.Abilities.HARVEST_CROP_GET_SEED_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Green Thumb 3",
		description = "Greatly improved chance for a bonus seed when harvesting",
		unlockLevel = 95,
		storeImageAssetId = 90416195015728,
		equipGemCount = 6000,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_GEMS_1,
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Gemsmith",
		description = "Get more gems when you harvest",
		unlockLevel = 30,
		storeImageAssetId = 78463784967163,
		equipGemCount = 425,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_GEMS_2,
		replaceAbility = enums.Abilities.HARVEST_CROP_MORE_GEMS_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Gemsmith 2",
		description = "Get many more gems when you harvest",
		unlockLevel = 60,
		storeImageAssetId = 78463784967163,
		equipGemCount = 1300,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_GEMS_3,
		replaceAbility = enums.Abilities.HARVEST_CROP_MORE_GEMS_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Gemsmith 3",
		description = "Get way more gems when you harvest",
		unlockLevel = 85,
		storeImageAssetId = 78463784967163,
		equipGemCount = 3750,
	},
	{
		ability = enums.Abilities.LONGER_OFFLINE_HARVESTING_1,
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Offline Dragon Training",
		description = "Dragons harvest longer while you're offline",
		unlockLevel = 15,
		storeImageAssetId = 135450419919313,
		equipGemCount = 100,
	},
	{
		ability = enums.Abilities.LONGER_OFFLINE_HARVESTING_2,
		replaceAbility = enums.Abilities.LONGER_OFFLINE_HARVESTING_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Offline Dragon Training 2",
		description = "Dragons harvest much longer while you're offline",
		unlockLevel = 40,
		storeImageAssetId = 135450419919313,
		equipGemCount = 450,
	},
	{
		ability = enums.Abilities.LONGER_OFFLINE_HARVESTING_3,
		replaceAbility = enums.Abilities.LONGER_OFFLINE_HARVESTING_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.NATURE,
		displayName = "Offline Dragon Training 3",
		description = "Dragons harvest way longer while you're offline",
		unlockLevel = 65,
		storeImageAssetId = 135450419919313,
		equipGemCount = 1200,
	},
	-- end of green abilities

	-- beginning of blue abilities
	{
		ability = enums.Abilities.FLY_FAST_1,
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Flight Master",
		description = "Fly at double speed for 3 seconds",
		unlockLevel = 5,
		storeImageAssetId = 126341677872824,
		equipGemCount = 25,
	},
	{
		ability = enums.Abilities.FLY_FAST_2,
		replaceAbility = enums.Abilities.FLY_FAST_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Flight Master 2",
		description = "Fly at double speed for 6 seconds",
		unlockLevel = 25,
		storeImageAssetId = 126341677872824,
		equipGemCount = 150,
	},
	{
		ability = enums.Abilities.FLY_FAST_3,
		replaceAbility = enums.Abilities.FLY_FAST_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Flight Master 3",
		description = "Fly at double speed for 9 seconds",
		unlockLevel = 70,
		storeImageAssetId = 126341677872824,
		equipGemCount = 2400,
	},
	{
		ability = enums.Abilities.FASTER_CROP_GROWTH_1,
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Fruitsmith",
		description = "Plants regrow fruit faster",
		unlockLevel = 55,
		storeImageAssetId = 76275532702967,
		equipGemCount = 650,
	},
	{
		ability = enums.Abilities.FASTER_CROP_GROWTH_2,
		replaceAbility = enums.Abilities.FASTER_CROP_GROWTH_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Fruitsmith 2",
		description = "Plants regrow fruit much faster",
		unlockLevel = 80,
		storeImageAssetId = 76275532702967,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.FASTER_CROP_GROWTH_3,
		replaceAbility = enums.Abilities.FASTER_CROP_GROWTH_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Fruitsmith 3",
		description = "Plants regrow fruit way faster",
		unlockLevel = 95,
		storeImageAssetId = 76275532702967,
		equipGemCount = 6000,
	},
	{
		ability = enums.Abilities.FASTER_CRYSTAL_OPENING_1,
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Breaker",
		description = "Break crystals faster",
		unlockLevel = 30,
		storeImageAssetId = 106988481023434,
		equipGemCount = 425,
	},
	{
		ability = enums.Abilities.FASTER_CRYSTAL_OPENING_2,
		replaceAbility = enums.Abilities.FASTER_CRYSTAL_OPENING_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Breaker 2",
		description = "Break crystals much faster",
		unlockLevel = 60,
		storeImageAssetId = 106988481023434,
		equipGemCount = 1300,
	},
	{
		ability = enums.Abilities.FASTER_CRYSTAL_OPENING_3,
		replaceAbility = enums.Abilities.FASTER_CRYSTAL_OPENING_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Breaker 3",
		description = "Break crystals way faster",
		unlockLevel = 85,
		storeImageAssetId = 106988481023434,
		equipGemCount = 3750,
	},
	{
		ability = enums.Abilities.REFUND_CRYSTAL_1,
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Master",
		description = "Chance for a bonus crystal when breaking one",
		unlockLevel = 75,
		storeImageAssetId = 90189375577585,
		equipGemCount = 3000,
	},
	{
		ability = enums.Abilities.REFUND_CRYSTAL_2,
		replaceAbility = enums.Abilities.REFUND_CRYSTAL_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Master 2",
		description = "Improved chance for a bonus crystal when breaking one",
		unlockLevel = 90,
		storeImageAssetId = 90189375577585,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.REFUND_CRYSTAL_3,
		replaceAbility = enums.Abilities.REFUND_CRYSTAL_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Crystal Master 3",
		description = "Greatly improved chance for a bonus crystal when breaking one",
		unlockLevel = 100,
		storeImageAssetId = 90189375577585,
		equipGemCount = 5250,
	},
	{
		ability = enums.Abilities.MORE_NODE_ITEMS_1,
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Mining Expert",
		description = "Collect more shards from mining crystals",
		unlockLevel = 15,
		storeImageAssetId = 106668419557988,
		equipGemCount = 100,
	},
	{
		ability = enums.Abilities.MORE_NODE_ITEMS_2,
		replaceAbility = enums.Abilities.MORE_NODE_ITEMS_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Mining Expert 2",
		description = "Collect many more shards from mining crystals",
		unlockLevel = 40,
		storeImageAssetId = 106668419557988,
		equipGemCount = 450,
	},
	{
		ability = enums.Abilities.MORE_NODE_ITEMS_3,
		replaceAbility = enums.Abilities.MORE_NODE_ITEMS_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.WATER,
		displayName = "Mining Expert 3",
		description = "Collect way more shards from mining crystals",
		unlockLevel = 65,
		storeImageAssetId = 106668419557988,
		equipGemCount = 1200,
	},

	-- beginning of red abilities
	{
		ability = enums.Abilities.LONGER_FIREBALL_RANGE_1,
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Fire Range",
		description = "Fire breath reaches farther",
		unlockLevel = 5,
		storeImageAssetId = 108557553332151,
		equipGemCount = 25,
	},
	{
		ability = enums.Abilities.LONGER_FIREBALL_RANGE_2,
		replaceAbility = enums.Abilities.LONGER_FIREBALL_RANGE_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Fire Range 2",
		description = "Fire breath reaches much farther",
		unlockLevel = 25,
		storeImageAssetId = 108557553332151,
		equipGemCount = 150,
	},
	{
		ability = enums.Abilities.LONGER_FIREBALL_RANGE_3,
		replaceAbility = enums.Abilities.LONGER_FIREBALL_RANGE_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Fire Range 3",
		description = "Fire breath reaches the farthest",
		unlockLevel = 70,
		storeImageAssetId = 108557553332151,
		equipGemCount = 2400,
	},
	{
		ability = enums.Abilities.MERGE_DRAGON_GET_EGG_1,
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Breeder",
		description = "Chance for a bonus egg when fusing dragons",
		unlockLevel = 75,
		storeImageAssetId = 89811817293788,
		equipGemCount = 3000,
	},
	{
		ability = enums.Abilities.MERGE_DRAGON_GET_EGG_2,
		replaceAbility = enums.Abilities.MERGE_DRAGON_GET_EGG_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Breeder 2",
		description = "Improved chance for a bonus egg when fusing dragons",
		unlockLevel = 90,
		storeImageAssetId = 89811817293788,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.MERGE_DRAGON_GET_EGG_3,
		replaceAbility = enums.Abilities.MERGE_DRAGON_GET_EGG_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Breeder 3",
		description = "Greatly improved chance for a bonus egg when fusing dragons",
		unlockLevel = 100,
		storeImageAssetId = 89811817293788,
		equipGemCount = 5250,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_EGG_1,
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Feeder",
		description = "Chance for a bonus egg when harvesting",
		unlockLevel = 55,
		storeImageAssetId = 138005184222829,
		equipGemCount = 650,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_EGG_2,
		replaceAbility = enums.Abilities.HARVEST_CROP_GET_EGG_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Feeder 2",
		description = "Improved chance for a bonus egg when harvesting",
		unlockLevel = 80,
		storeImageAssetId = 138005184222829,
		equipGemCount = 3500,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_GET_EGG_3,
		replaceAbility = enums.Abilities.HARVEST_CROP_GET_EGG_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Dragon Feeder 3",
		description = "Greatly improved chance for a bonus egg when harvesting",
		unlockLevel = 95,
		storeImageAssetId = 138005184222829,
		equipGemCount = 6000,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_XP_1,
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "XP Mastery",
		description = "Earn more XP from harvesting",
		unlockLevel = 15,
		storeImageAssetId = 123851542351530,
		equipGemCount = 425,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_XP_2,
		replaceAbility = enums.Abilities.HARVEST_CROP_MORE_XP_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "XP Mastery 2",
		description = "Earn much more XP from harvesting",
		unlockLevel = 40,
		storeImageAssetId = 123851542351530,
		equipGemCount = 1300,
	},
	{
		ability = enums.Abilities.HARVEST_CROP_MORE_XP_3,
		replaceAbility = enums.Abilities.HARVEST_CROP_MORE_XP_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "XP Mastery 3",
		description = "Earn way more XP from harvesting",
		unlockLevel = 65,
		storeImageAssetId = 123851542351530,
		equipGemCount = 3750,
	},
	{
		ability = enums.Abilities.WIDER_FIREBALL_ANGLE_1,
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Targeting Master",
		description = "Wider aim for fire breath",
		unlockLevel = 30,
		storeImageAssetId = 138465821909736,
		equipGemCount = 100,
	},
	{
		ability = enums.Abilities.WIDER_FIREBALL_ANGLE_2,
		replaceAbility = enums.Abilities.WIDER_FIREBALL_ANGLE_1,
		upgradeBadgeText = "2",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Targeting Master 2",
		description = "Much wider aim for fire breath",
		unlockLevel = 60,
		storeImageAssetId = 138465821909736,
		equipGemCount = 450,
	},
	{
		ability = enums.Abilities.WIDER_FIREBALL_ANGLE_3,
		replaceAbility = enums.Abilities.WIDER_FIREBALL_ANGLE_2,
		upgradeBadgeText = "3",
		primaryElement = enums.PrimaryElements.FIRE,
		displayName = "Targeting Master 3",
		description = "Way wider aim for fire breath",
		unlockLevel = 85,
		storeImageAssetId = 138465821909736,
		equipGemCount = 120,
	},
	-- end of red abilities
}

local attributeAbilityDatas: { AttributeAbilityData } = {
	{
		key = Attributes.MERGE_CIRCLE_RADIUS,
		abilities = {
			enums.Abilities.MERGE_CIRCLE_SIZE_1,
			enums.Abilities.MERGE_CIRCLE_SIZE_2,
			enums.Abilities.MERGE_CIRCLE_SIZE_3,
		},
		isClient = true,
	},
	{
		key = Attributes.MERGE_CROP_GET_SEED_FRAC,
		abilities = {
			enums.Abilities.MERGE_CROP_GET_SEED_1,
			enums.Abilities.MERGE_CROP_GET_SEED_2,
			enums.Abilities.MERGE_CROP_GET_SEED_3,
		},
		isClient = false,
	},
	{
		key = Attributes.HARVEST_CROP_GET_SEED_FRAC,
		abilities = {
			enums.Abilities.HARVEST_CROP_GET_SEED_1,
			enums.Abilities.HARVEST_CROP_GET_SEED_2,
			enums.Abilities.HARVEST_CROP_GET_SEED_3,
		},
		isClient = false,
	},
	{
		key = Attributes.HARVEST_CROP_MORE_GEMS_FRAC,
		abilities = {
			enums.Abilities.HARVEST_CROP_MORE_GEMS_1,
			enums.Abilities.HARVEST_CROP_MORE_GEMS_2,
			enums.Abilities.HARVEST_CROP_MORE_GEMS_3,
		},
		isClient = false,
	},
	{
		key = Attributes.OFFLINE_HARVESTING_MAX_DURATION,
		abilities = {
			enums.Abilities.LONGER_OFFLINE_HARVESTING_1,
			enums.Abilities.LONGER_OFFLINE_HARVESTING_2,
			enums.Abilities.LONGER_OFFLINE_HARVESTING_3,
		},
		isClient = false,
	},

	{
		key = Attributes.FLY_FAST_DURATION,
		abilities = {
			enums.Abilities.FLY_FAST_1,
			enums.Abilities.FLY_FAST_2,
			enums.Abilities.FLY_FAST_3,
		},
		isClient = true,
	},
	{
		key = Attributes.CROPS_GROW_FASTER_FRAC,
		abilities = {
			enums.Abilities.FASTER_CROP_GROWTH_1,
			enums.Abilities.FASTER_CROP_GROWTH_2,
			enums.Abilities.FASTER_CROP_GROWTH_3,
		},
		isClient = false,
	},
	{
		key = Attributes.CRYSTALS_OPEN_FASTER_FRAC,
		abilities = {
			enums.Abilities.FASTER_CRYSTAL_OPENING_1,
			enums.Abilities.FASTER_CRYSTAL_OPENING_2,
			enums.Abilities.FASTER_CRYSTAL_OPENING_3,
		},
		isClient = false,
	},
	{
		key = Attributes.REFUND_CRYSTAL_FRAC,
		abilities = {
			enums.Abilities.REFUND_CRYSTAL_1,
			enums.Abilities.REFUND_CRYSTAL_2,
			enums.Abilities.REFUND_CRYSTAL_3,
		},
		isClient = false,
	},
	{
		key = Attributes.EXTRA_NODE_LOOT_PREFIX,
		abilities = {
			enums.Abilities.MORE_NODE_ITEMS_1,
			enums.Abilities.MORE_NODE_ITEMS_2,
			enums.Abilities.MORE_NODE_ITEMS_3,
		},
		isClient = false,
	},

	{
		key = Attributes.FIREBALL_RANGE,
		abilities = {
			enums.Abilities.LONGER_FIREBALL_RANGE_1,
			enums.Abilities.LONGER_FIREBALL_RANGE_2,
			enums.Abilities.LONGER_FIREBALL_RANGE_3,
		},
		isClient = true,
	},
	{
		key = Attributes.MERGE_DRAGON_GET_EGG_FRAC,
		abilities = {
			enums.Abilities.MERGE_DRAGON_GET_EGG_1,
			enums.Abilities.MERGE_DRAGON_GET_EGG_2,
			enums.Abilities.MERGE_DRAGON_GET_EGG_3,
		},
		isClient = true,
	},
	{
		key = Attributes.HARVEST_CROP_GET_EGG_FRAC,
		abilities = {
			enums.Abilities.HARVEST_CROP_GET_EGG_1,
			enums.Abilities.HARVEST_CROP_GET_EGG_2,
			enums.Abilities.HARVEST_CROP_GET_EGG_3,
		},
		isClient = false,
	},
	{
		key = Attributes.HARVEST_CROP_MORE_XP_FRAC,
		abilities = {
			enums.Abilities.HARVEST_CROP_MORE_XP_1,
			enums.Abilities.HARVEST_CROP_MORE_XP_2,
			enums.Abilities.HARVEST_CROP_MORE_XP_3,
		},
		isClient = false,
	},
	{
		key = Attributes.FIREBALL_ANGLE,
		abilities = {
			enums.Abilities.WIDER_FIREBALL_ANGLE_1,
			enums.Abilities.WIDER_FIREBALL_ANGLE_2,
			enums.Abilities.WIDER_FIREBALL_ANGLE_3,
		},
		isClient = true,
	},

}

local attributeAbilityMap: { [string]: AttributeAbilityData }? -- prevent circular reference by not initializing here
--[[= {
	[Attributes.MERGE_CIRCLE_RADIUS] =
		{
			enums.Abilities.MERGE_CIRCLE_SIZE_1,
			enums.Abilities.MERGE_CIRCLE_SIZE_2,
			enums.Abilities.MERGE_CIRCLE_SIZE_3,
		},
}
]]

local attributeNames: { string }?

function Abilities.getAttributeNames(): { string }
	if attributeNames then
		return attributeNames
	end

	local names: { string } = {}
	for _, attributeAbilityData in attributeAbilityDatas do
		table.insert(names, attributeAbilityData.key)
	end
	attributeNames = names

	return names
end

local function initAttributeAbilityMapIfNeeded(): { [string]: AttributeAbilityData }
	if attributeAbilityMap then
		return attributeAbilityMap
	end

	local map: { [string]: AttributeAbilityData } = {}
	for _, attributeAbilityData in attributeAbilityDatas do
		map[attributeAbilityData.key] = attributeAbilityData
	end
	attributeAbilityMap = map

	return map
end

function Abilities.doAbilitiesControlAttributeName(attributeName: string): boolean
	local map = initAttributeAbilityMapIfNeeded()

	return map[attributeName] ~= nil
end

function Abilities.getAbilitiesForAttributeName(attributeName: string): { number }
	local map = initAttributeAbilityMapIfNeeded()

	local attributeAbilityData = assert(map[attributeName], "no ability data for attribute " .. attributeName)
	return attributeAbilityData.abilities
end

function Abilities.getIsClientForAttributeName(attributeName: string): boolean
	local map = initAttributeAbilityMapIfNeeded()

	local attributeAbilityData = assert(map[attributeName], "no ability data for attribute " .. attributeName)
	return attributeAbilityData.isClient
end

local function getAbilityDatasByPrimaryElement(primaryElement: number): { AbilityData }
	local abilityDatas: { AbilityData } = {}
	for _, abilityData in AbilityDatas do
		if abilityData.primaryElement ~= primaryElement then
			continue
		end

		table.insert(abilityDatas, abilityData)
	end

	return abilityDatas
end

function Abilities.getAbilitiesSortedByPrimaryElement(primaryElement: number): { number }
	local abilityDatas = getAbilityDatasByPrimaryElement(primaryElement)
	table.sort(abilityDatas,
		function(a: AbilityData, b: AbilityData): boolean
			return a.unlockLevel < b.unlockLevel
		end
	)
	local abilities: { number } = {}
	for _, abilityData in abilityDatas do
		table.insert(abilities, abilityData.ability)
	end

	return abilities
end

function Abilities.getDataForAbility(ability: number?): AbilityData?
	for _, abilityData in AbilityDatas do
		if abilityData.ability ~= ability then
			continue
		end
		return abilityData
	end

	warn("ability not found", ability)

	return nil
end

function Abilities.validateAbility(ability: number?): boolean
	for _, abilityData in AbilityDatas do
		if abilityData.ability ~= ability then
			continue
		end
		return true
	end

	return false
end



function Abilities.getReplaceAbilityForAbility(ability: number): number?
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.replaceAbility
end

function Abilities.getUpgradeBadgeTextForAbility(ability: number): string?
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.upgradeBadgeText
end

function Abilities.getPrimaryElementForAbility(ability: number): number
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.primaryElement
end

function Abilities.getDisplayNameForAbility(ability: number): string
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.displayName
end

function Abilities.getDescriptionForAbility(ability: number): string
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.description
end

function Abilities.getUnlockLevelForAbility(ability: number): number
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.unlockLevel
end

function Abilities.getStoreImageAssetIdForAbility(ability: number): number
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.storeImageAssetId
end

-- legacy (2026-august-20): abilities used to cost per-element gems; see getEquipCoinCostForAbility
-- function Abilities.getEquipGemCountForAbility(ability: number): number
-- 	local abilityData = assert(Abilities.getDataForAbility(ability))
-- 	return abilityData.equipGemCount
-- end

-- abilities now cost coins instead of gems; equipGemCount is kept as the underlying data field
-- (unrenamed to avoid touching all 46 ability entries) and simply multiplied by 10 for coins.
function Abilities.getEquipCoinCostForAbility(ability: number): number
	local abilityData = assert(Abilities.getDataForAbility(ability))
	return abilityData.equipGemCount * 10
end

return Abilities
