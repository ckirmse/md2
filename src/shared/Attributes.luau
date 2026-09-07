--!strict

local module

module = {
	ITEM_ID = "ItemId",

	-- as of 2026-january-5 only used for buy store
	ITEM_NAME = "ItemName",

	-- mergeable items need this so client knows which ones can be merged
	MERGE_NAME = "MergeName",
	MERGE_ALL_NAME = "MergeAllName",

	-- pickup items need this so client knows which ones can be merged
	USER_ID = "UserId",
	-- pickup items need this to show in prompt
	PICKUP_NAME = "PickupName",
	SIZE = "Size",
	EQUIP = "Equip",
	RARITY = "Rarity",
	ITEM_TYPE = "ItemType",

	DISPLAY_NAME = "DisplayName",
	NAME_PLATE_EXTRA_TEXT = "NameplateExtraText",

	-- visual items that should be removed from crops based on amount of available food should have this
	VARIABLE_FOOD = "VariableFood",

	-- dragons need an part with this as a boolean set to true
	SEAT_LOCATION = "SeatLocation",

	DRAGON_RISE_SPEED = "RiseSpeed",
	DRAGON_MAX_FLIGHT_DURATION = "MaxFlightDuration",
	DRAGON_STAMINA = "Stamina",
	DRAGON_IS_IN_FREE_FLY_ZONE = "IsInFreeFlyZone",
	CLIENT_CONTROL = "ClientControl",

	DRAGON_FLAP_DATA = "DragonFlapData",
	DRAGON_PULSE_DATA = "DragonPulseData",
	DRAGON_RIDER = "DragonRider",

	DRAGON_POWER = "DragonPower",
	DRAGON_SLOT_INDEX = "DragonSlotIndex",

	OPEN_COMPLETE_TIME = "OpenCompleteTime",

	-- sellable items need this so client knows what it is
	SELL_NAME = "SellName",
	COUNT = "Count",

	-- for plot index of some plot pieces such as origins, signs, etc.
	-- also used for items in inventory
	INDEX = "Index",

	-- for sellable items in SplendidData
	COINS = "Coins",
	ASSET_ID = "AssetId",
	COLOR = "Color",

	GROW_COMPLETE_TIME = "GrowCompleteTime",
	MODIFICATIONS = "Modifications",
	MUTATION = "Mutation",

	PRIMARY_ELEMENT = "PrimaryElement",

	OBJECT_ID = "ObjectId",

	-- parts of an MItem that should be set to appropriate color/texture when mutated
	MUTATION_TARGET = "MutationTarget",
	MUTATION_SURFACE_APPEARANCE_NAME = "MutationSurfaceAppearanceName",

	PART_INDEX = "PartIndex",

	CASTER_PATH = "CasterPath",

	ANIMATION_CHARGE_UP = "AnimationChargeUp",
	ANIMATION_SHOOT_FIREBALL = "AnimationShootFireball",
	ANIMATION_MINE_NODE = "AnimationMineNode",
	ANIMATION_EAT = "AnimationEat",
	ANIMATION_OPENING = "AnimationOpening",
	ANIMATION_CLAIMING = "AnimationClaiming",
	ANIMATION_FIREBALL_HIT = "AnimationFireballHit",
	ANIMATION_CRYSTAL_OPENED = "AnimationCrystalOpened",
	ANIMATION_DRAGON_COMING_TO_OPEN = "AnimationDragonComingToOpen",
	ANIMATION_CRYSTAL_CLAIMABLE = "AnimationCrystalClaimable",
	ANIMATION_FLY_AWAY = "AnimationFlyAway",
	ANIMATION_MODIFICATIONS_REMOVED = "AnimationModificationsRemoved",
	ANIMATION_NODE_ROTATE = "AnimationNodeRotate",
	ANIMATION_HIGHLIGHT_FADE_OUT = "AnimationHighlightFadeOut",
	ANIMATION_MERGE_PARTICLES = "AnimationMergeParticles",
	ANIMATION_EXPLODE_CRITTER = "AnimationExplodeCritter",

	MERGING = "Merging",

	-- player variables (some are server-side only)
	MERGE_CIRCLE_RADIUS = "MergeCircleRadius",
	MERGE_CROP_GET_SEED_FRAC = "MergeCropGetSeedFrac",
	HARVEST_CROP_GET_SEED_FRAC = "HarvestCropGetSeedFrac",
	HARVEST_CROP_MORE_GEMS_FRAC = "HarvestCropMoreGemsFrac",
	OFFLINE_HARVESTING_MAX_DURATION = "OfflineHarvestingMaxDuration",
	CROPS_GROW_FASTER_FRAC = "CropsGrowFasterFrac",
	CRYSTALS_OPEN_FASTER_FRAC = "CrystalsOpenFasterFrac",
	REFUND_CRYSTAL_FRAC = "RefundCrystalFrac",
	FLY_FAST_DURATION = "FlyFastDuration",
	FIREBALL_RANGE = "FireballRange",
	MERGE_DRAGON_GET_EGG_FRAC = "MergeDragonGetEggFrac",
	HARVEST_CROP_GET_EGG_FRAC = "HarvestCropGetEggFrac",
	HARVEST_CROP_MORE_XP_FRAC = "HarvestCropMoreXpFrac",
	FIREBALL_ANGLE = "FireballAngle",
	EXTRA_NODE_LOOT_PREFIX = "ExtraNodeLootPrefix",

	UNLOCKED_ABILITY_SLOTS = "UnlockedAbilitySlots",
	UNLOCKABLE_ABILITY_SLOT_DATA = "UnlockableAbilitySlotData",

	PRODUCT_ID = "ProductId",
	DURATION = "Duration",

	LEVEL = "Level",
	OPENED = "Opened",

	BLUEPRINT = "Blueprint",
	STATE = "State",
	UNLOCKABLE = "Unlockable",
	TEMPLATE_PATHS = "TemplatePaths",
	BLUEPRINT_DISPLAY_NAME = "BlueprintDisplayName",
	BLUEPRINT_TEMPLATE_PATH = "BlueprintTemplatePath",
	VANITY_COMPONENT_NAME = "VanityComponentName",
	VANITY_AREA_STATE = "VanityAreaState",
	VANITY_DECORATE_NAME = "VanityDecorateName",

	IS_CRYSTAL_CRITTER = "IsCrystalCritter",
	TEMPLATE_PATH = "TemplatePath",
	SCREENSHOT_CAMERA_POSITION = "ScreenshotCameraPosition",
	CRATE_TEMPLATE_PATH = "CrateTemplatePath",
	BASE_TIME = "BaseTime",
	PERIOD = "Period",
	RADIUS = "Radius",
	CAPACITY_STR = "CapacityStr",

	INSTANCE_NAME = "InstanceName",
	HEADER_NAME = "HeaderName",
	DISCOUNT_PRODUCT_ID = "DiscountProductId",
	DISCOUNT_AVAILABLE_TIME = "DiscountAvailableTime",

	COMMON = "Common",
	UNCOMMON = "Uncommon",
	RARE = "Rare",
	EPIC = "Epic",

	PERCENT = "Percent",
	BEGIN_TIME = "BeginTime",
	END_TIME = "EndTime",

	TIME_LUCK_PERCENT = "TimeLuckPercent",
	FRIEND_LUCK_PERCENT = "FriendLuckPercent",
	GROUP_LUCK_PERCENT = "GroupLuckPercent",
	INDEX_LUCK_PERCENT = "IndexLuckPercent",

	IS_MERGE_ALL_UNLOCKED = "IsMergeAllUnlocked",

	-- Category/type specially for shop filtering system
	SHOP_CATEGORY = "ShopCategory",
}

return module
