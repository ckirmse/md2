--!strict

-- An enum table maps SCREAMING_SNAKE key names to unique numeric values, and may also carry a
-- PublicNames sub-table holding the player-facing string for some or all of those keys. Keys with
-- no player-facing name are simply absent from PublicNames, so lookups into it are optional.
--
-- EnumTable is the parameter type for the helpers below. It has to be `any` rather than a table
-- type like `{ [string]: number | PublicNames }`: table indexers are invariant in Luau, so the
-- precise inferred type of a literal like Rarity (COMMON: number, ..., PublicNames: {...}) is not
-- assignable to an indexer whose value type is that union — and under the new type solver the
-- mixed-shape enum tables are not assignable to `{ [string]: any }` either. The helpers recover
-- the real types with typeof() guards instead.
export type PublicNames = { [string]: string? }
export type EnumTable = any

local module

module = {
	Venues = {
		WORKSPACE_AVAILABLE = 1,
		PLAYER = 2,
		WORKSPACE_SETTLING = 3,
		WORKSPACE_BUSY = 4,
	},
	DragonState = {
		IDLE = 1,
		EATING = 2,
		MOVING_TO_EAT = 3,
		MOVING_TO_IDLE = 4,
		MERGING = 5,
		MOVING_TO_OPEN = 6,
		OPENING = 7,
		MOVING_TO_MINE = 8,
		OUTSIDE = 9,
		MOVING_TO_OUTSIDE = 10,
		SETTLING = 11,
	},
	CropState = {
		IDLE = 1,
		GETTING_EATEN = 2,
		GROWING = 3,
		MERGING = 4,
	},
	CrystalState = {
		IDLE = 1,
		MERGING = 2,
		OPENING = 3,
		OPENED = 4,
	},
	PackState = {
		IDLE = 1,
	},
	CrateState = {
		IDLE = 1,
	},

	NodeState = {
		IDLE = 1,
		GETTING_MINED = 2,
		EMPTY = 3,
	},
	ChestState = {
		IDLE = 1,
		OPENED = 2,
		OPENING = 3,
	},
	CritterState = {
		IDLE = 1,
		OPENED = 2,
	},

	-- if you add more of these you must also update the table in GameController
	PrimaryElements = {
		NONE = 0,
		FIRE = 1,
		NATURE = 2,
		WATER = 3,

		PublicNames = {
			FIRE = "Fire",
			NATURE = "Nature",
			WATER = "Water",
		},
	},
	Elements = {
		FIRE = 1,
		NATURE = 2,
		WATER = 3,

		SMOKE = 100,
		STEAM = 101,
		MARSH = 102,
		DARK = 103,
		WIND = 104,
		MIST = 105,
	},
	Rarity = {
		COMMON = 1,
		UNCOMMON = 2,
		RARE = 3,
		EPIC = 4,

		PublicNames = {
			COMMON = "Common",
			UNCOMMON = "Uncommon",
			RARE = "Rare",
			EPIC = "Epic",
		},
	},
	ShopCategory = {
		DRAGONS = 1,
		PLANTS = 2,

		PublicNames = {
			DRAGONS = "Dragons",
			PLANTS = "Plants",
		},
	},
	Mutations = {
		-- if these are changed to not be strictly better in increasing values, then you must update MItem.compareMutations (as of 2026-january-23)
		NORMAL = 1,
		BRONZE = 2,
		SILVER = 3,
		GOLD = 4,
		RAINBOW = 5,
		CELESTIAL = 6,
		VERDANT = 7,
		AZURE = 8,
		CRIMSON = 9,

		PublicNames = {
			NORMAL = nil,
			BRONZE = "Bronze",
			SILVER = "Silver",
			GOLD = "Gold",
			RAINBOW = "Rainbow",
			CELESTIAL = "Celestial",
			VERDANT = "Verdant",
			AZURE = "Azure",
			CRIMSON = "Crimson",
		},
	},
	Modifications = {
		WET = 1,
		BLOOM = 2,
		WINDY = 3,
		HOT = 4,
		GREEN_FLAME = 5,
		BLUE_FLAME = 6,
		RED_FLAME = 7,

		PublicNames = {
			WET = "Wet",
			BLOOM = "Bloom",
			WINDY = "Windy",
			HOT = "Hot",
			GREEN_FLAME = "Green Flame",
			BLUE_FLAME = "Blue Flame",
			RED_FLAME = "Red Flame",
		},
	},
	CollideInWorkspace = {
		ALWAYS = 1,
		NEVER = 2,
		FROM_TEMPLATE = 3,
	},
	ShadowAnimation = {
		NONE = 1,
		DRAGON_EATING = 2,
	},
	Abilities = {
		MERGE_CIRCLE_SIZE_1 = 101,
		MERGE_CIRCLE_SIZE_2 = 102,
		MERGE_CIRCLE_SIZE_3 = 103,
		MERGE_CROP_GET_SEED_1 = 201,
		MERGE_CROP_GET_SEED_2 = 202,
		MERGE_CROP_GET_SEED_3 = 203,
		HARVEST_CROP_GET_SEED_1 = 301,
		HARVEST_CROP_GET_SEED_2 = 302,
		HARVEST_CROP_GET_SEED_3 = 303,
		HARVEST_CROP_MORE_GEMS_1 = 401,
		HARVEST_CROP_MORE_GEMS_2 = 402,
		HARVEST_CROP_MORE_GEMS_3 = 403,
		LONGER_OFFLINE_HARVESTING_1 = 501,
		LONGER_OFFLINE_HARVESTING_2 = 502,
		LONGER_OFFLINE_HARVESTING_3 = 503,

		FLY_FAST_1 = 1101,
		FLY_FAST_2 = 1102,
		FLY_FAST_3 = 1103,
		FASTER_CROP_GROWTH_1 = 1201,
		FASTER_CROP_GROWTH_2 = 1202,
		FASTER_CROP_GROWTH_3 = 1203,
		FASTER_CRYSTAL_OPENING_1 = 1301,
		FASTER_CRYSTAL_OPENING_2 = 1302,
		FASTER_CRYSTAL_OPENING_3 = 1303,
		REFUND_CRYSTAL_1 = 1401,
		REFUND_CRYSTAL_2 = 1402,
		REFUND_CRYSTAL_3 = 1403,
		MORE_NODE_ITEMS_1 = 1501,
		MORE_NODE_ITEMS_2 = 1502,
		MORE_NODE_ITEMS_3 = 1503,

		LONGER_FIREBALL_RANGE_1 = 2101,
		LONGER_FIREBALL_RANGE_2 = 2102,
		LONGER_FIREBALL_RANGE_3 = 2103,
		MERGE_DRAGON_GET_EGG_1 = 2201,
		MERGE_DRAGON_GET_EGG_2 = 2202,
		MERGE_DRAGON_GET_EGG_3 = 2203,
		HARVEST_CROP_GET_EGG_1 = 2301,
		HARVEST_CROP_GET_EGG_2 = 2302,
		HARVEST_CROP_GET_EGG_3 = 2303,
		HARVEST_CROP_MORE_XP_1 = 2401,
		HARVEST_CROP_MORE_XP_2 = 2402,
		HARVEST_CROP_MORE_XP_3 = 2403,
		WIDER_FIREBALL_ANGLE_1 = 2501,
		WIDER_FIREBALL_ANGLE_2 = 2502,
		WIDER_FIREBALL_ANGLE_3 = 2503,

		PublicNames = {
			MERGE_CIRCLE_SIZE_1 = "MergeCircleSize1",
			MERGE_CIRCLE_SIZE_2 = "MergeCircleSize2",
			MERGE_CIRCLE_SIZE_3 = "MergeCircleSize3",
			MERGE_CROP_GET_SEED_1 = "MergeCropGetSeed1",
			MERGE_CROP_GET_SEED_2 = "MergeCropGetSeed2",
			MERGE_CROP_GET_SEED_3 = "MergeCropGetSeed3",
			HARVEST_CROP_GET_SEED_1 = "HarvestCropGetSeed1",
			HARVEST_CROP_GET_SEED_2 = "HarvestCropGetSeed2",
			HARVEST_CROP_GET_SEED_3 = "HarvestCropGetSeed3",
			HARVEST_CROP_MORE_GEMS_1 = "HarvestCropMoreGems1",
			HARVEST_CROP_MORE_GEMS_2 = "HarvestCropMoreGems2",
			HARVEST_CROP_MORE_GEMS_3 = "HarvestCropMoreGems3",
			LONGER_OFFLINE_HARVESTING_1 = "LongerOfflineHarvesting1",
			LONGER_OFFLINE_HARVESTING_2 = "LongerOfflineHarvesting2",
			LONGER_OFFLINE_HARVESTING_3 = "LongerOfflineHarvesting3",

			FLY_FAST_1 = "FlyFast1",
			FLY_FAST_2 = "FlyFast2",
			FLY_FAST_3 = "FlyFast3",
			FASTER_CROP_GROWTH_1 = "FasterCropGrowth1",
			FASTER_CROP_GROWTH_2 = "FasterCropGrowth2",
			FASTER_CROP_GROWTH_3 = "FasterCropGrowth3",
			FASTER_CRYSTAL_OPENING_1 = "FasterCrystalOpening1",
			FASTER_CRYSTAL_OPENING_2 = "FasterCrystalOpening2",
			FASTER_CRYSTAL_OPENING_3 = "FasterCrystalOpening3",
			REFUND_CRYSTAL_1 = "RefundCrystal1",
			REFUND_CRYSTAL_2 = "RefundCrystal2",
			REFUND_CRYSTAL_3 = "RefundCrystal3",
			MORE_NODE_ITEMS_1 = "MoreNodeItems1",
			MORE_NODE_ITEMS_2 = "MoreNodeItems2",
			MORE_NODE_ITEMS_3 = "MoreNodeItems3",

			LONGER_FIREBALL_RANGE_1 = "LongerFireballRange1",
			LONGER_FIREBALL_RANGE_2 = "LongerFireballRange2",
			LONGER_FIREBALL_RANGE_3 = "LongerFireballRange3",
			MERGE_DRAGON_GET_EGG_1 = "MergeDragonGetEgg1",
			MERGE_DRAGON_GET_EGG_2 = "MergeDragonGetEgg2",
			MERGE_DRAGON_GET_EGG_3 = "MergeDragonGetEgg3",
			HARVEST_CROP_GET_EGG_1 = "HarvestCropGetEgg1",
			HARVEST_CROP_GET_EGG_2 = "HarvestCropGetEgg2",
			HARVEST_CROP_GET_EGG_3 = "HarvestCropGetEgg3",
			HARVEST_CROP_MORE_XP_1 = "HarvestCropMoreXp1",
			HARVEST_CROP_MORE_XP_2 = "HarvestCropMoreXp2",
			HARVEST_CROP_MORE_XP_3 = "HarvestCropMoreXp3",
			WIDER_FIREBALL_ANGLE_1 = "WiderFireballAngle1",
			WIDER_FIREBALL_ANGLE_2 = "WiderFireballAngle2",
			WIDER_FIREBALL_ANGLE_3 = "WiderFireballAngle3",
		},
	},
	AbilityStatus = {
		LOCKED = 1,
		UNLOCKED = 2,
		EQUIPPED = 3,
		REPLACED = 4,
	},
	HudElements = {
		COINS = 1,
		GEMS = 2,
		BACKPACK = 3,
		OPTION_BUTTON = 4,
		TRADE_BUTTON = 5,
		LUCK = 6,
	},
	FtueSetupType = {
		NONE = 0,
		CREATE_AND_DROP_ITEM = 1,
		CREATE_ITEM = 2,
		CREATE_ITEM_IN_BACKPACK = 3,
	},
	FtueTransitionType = {
		PICKUP = 1,
		MOVE_TO_PLOT_LOCATION = 2,
		MOVE_TO_WORLD_LOCATION = 3,
		MOVE_TO_ITEM = 4,
		MERGE = 5,
		PLACE_ON_BOARD = 6,
		SUMMON_TO_EAT = 7,
		GET_GEMS = 8,
		GET_COINS = 9,
		GET_ITEMS = 10,
		EQUIP_ITEM = 11,
		UNEQUIP_ITEM = 12,
	},
	FtueConfigurationType = {
		MESSAGE = 1,
		SYSTEM_MESSAGE = 2,
		BEAM = 3,
		ANIMATE_PROMPTS = 4,
		POINT_TO_BACKPACK_FRAME = 5,
		BUY_ITEM = 6,
		CLOSE_OVERLAYS = 7,
		STROKE_2D_ELEMENT = 8,
		HIDE_TELEPORTERS = 9,
		ANIMATE_IN_TELEPORTERS = 10,
		DISABLE_BUY_STORE = 11,
		DISABLE_SELL_STORE = 12,
		BILLBOARD = 13,
	},
	FirstSessionOfferState = {
		NONE = 1,
		WAITING = 2,
		REDEEMABLE = 3,
		COMPLETE = 4,
	},
	TradingState = {
		NONE = 1,
		PLAYER_OPENED = 2,
		BOTH_OPENED = 3,
		PLAYER_LOCKED_OFFER = 4,
		PARTNER_LOCKED_OFFER = 5,
		BOTH_LOCKED_OFFER = 6,
		PLAYER_ACCEPTED = 7,
		PARTNER_ACCEPTED = 8,
		BOTH_ACCEPTED = 9,
		PLAYER_CONFIRMED = 10,
		PARTNER_CONFIRMED = 11,
		EXECUTING = 12,
	},
	PlayerVanityState = {
		LOCKED = 1,
		UNLOCKED = 2,
	},
	VanityComponentState = {
		LOCKED = 1,
		UNLOCKED = 2,
	},
	VanityPlacements = {
		MAIN_PLOT_INNER = 1,
		MAIN_PLOT_OUTER = 2,
		MAIN_PLOT_FENCE_1 = 3,
		MAIN_PLOT_FENCE_2 = 4,
		MAIN_PLOT_FENCE_3 = 5,
		MAIN_PLOT_FENCE_4 = 6,
		MAIN_PLOT_FENCE_5 = 7,
		MAIN_PLOT_FENCE_6 = 8,
		MAIN_PLOT_FENCE_7 = 9,
		MAIN_PLOT_FENCE_8 = 10,
		MAIN_PLOT_FENCE_9 = 11,
		EXPANSION_1_INNER = 12,
		EXPANSION_1_OUTER = 13,
		EXPANSION_2_INNER = 14,
		EXPANSION_2_OUTER = 15,
		EXPANSION_3_INNER = 16,
		EXPANSION_3_OUTER = 17,
		EXPANSION_4_INNER = 18,
		EXPANSION_4_OUTER = 19,
	},
	VanityAreas = {
		MAIN_PLOT = 1,
		MAIN_PLOT_FENCE = 2,
		EXPANSION_1 = 3,
		EXPANSION_2 = 4,
		EXPANSION_3 = 5,
		EXPANSION_4 = 6,

		PublicNames = {
			MAIN_PLOT = "Main Plot",
			MAIN_PLOT_FENCE = "Main Plot Fence",
			EXPANSION_1 = "Expansion 1",
			EXPANSION_2 = "Expansion 2",
			EXPANSION_3 = "Expansion 3",
			EXPANSION_4 = "Expansion 4",
		},
	},
	VanityAreaState = {
		LOCKED = 1,
		UNLOCKED = 2,
	},
	VanitySection = {
		MAIN_INNER = 1,
		MAIN_OUTER = 2,
		MAIN_FENCE = 3,
		EXPANSION_INNER = 4,
		EXPANSION_OUTER = 5,

		PublicNames = {
			MAIN_INNER = "MainInner",
			MAIN_OUTER = "MainOuter",
			MAIN_FENCE = "MainFence",
			EXPANSION_INNER = "ExpansionInner",
			EXPANSION_OUTER = "ExpansionOuter",
		},
	},

	getCount = function(tbl: EnumTable): number
		if typeof(tbl) ~= "table" then
			warn("first parameter to getCount() needs to be the enum table")
			return 0
		end
		local retval = 0
		for k, v in tbl do
			if typeof(v) ~= "number" then
				continue
			end

			retval += 1
		end
		return retval
	end,
	getAllValues = function(tbl: EnumTable): { number }
		if typeof(tbl) ~= "table" then
			warn("first parameter to getAllValues() needs to be the enum table")
			return {}
		end
		local retval: { number } = {}
		for k, v in tbl do
			if typeof(v) ~= "number" then
				continue
			end

			table.insert(retval, v)
		end
		table.sort(retval, function(a: number, b: number): boolean
			return a < b
		end)
		return retval
	end,
	isValidValue = function(tbl: EnumTable, value: number?): boolean
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums isValidValue() needs to be the enum table")
			return false
		end
		for k, v in tbl do
			if v == value then
				return true
			end
		end
		return false
	end,
	getName = function(tbl: EnumTable, value: number?): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getName() needs to be the enum table")
			return "invalid"
		end

		for k, v in tbl do
			if v == value then
				return k
			end
		end
		warn("invalid enum to getName " .. tostring(value))
		return nil
	end,
	getValueByName = function(tbl: EnumTable, name: string?): number?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getValueByName() needs to be the enum table")
			return nil
		end

		for k, v in tbl do
			if k == name and typeof(v) == "number" then
				return v
			end
		end
		warn("invalid enum to getValueByName " .. tostring(name))
		return nil
	end,
	getPublicName = function(tbl: EnumTable, value: number?): string?
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums getPublicName() needs to be the enum table")
			return "invalid"
		end

		if value == nil then
			return nil
		end

		local key: string? = nil
		for k, v in tbl do
			if v == value then
				key = k
			end
		end
		if key == nil then
			return "invalid enum " .. tostring(value)
		end
		local publicNames: PublicNames? = tbl.PublicNames
		if typeof(publicNames) ~= "table" then
			return "enum table has no public names, including for key " .. key
		end
		if not publicNames[key] then
			return nil
		end
		return publicNames[key]
	end,
	validateValue = function(tbl: EnumTable, value: number?): boolean
		if typeof(tbl) ~= "table" then
			warn("first parameter to enums validateValue() needs to be the enum table")
			return false
		end
		for k, v in tbl do
			if v == value then
				return true
			end
		end
		return false
	end,
}

return module
