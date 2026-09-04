--!strict

local module

-- these are applied by mixins to the appropriate objects

module = {
	ITEM = "Item",
	MERGEABLE = "Mergeable",
	RIDABLE = "Ridable",
	PICKUPABLE = "Pickupable",

	CROP = "Crop",
	CONSUMABLE_CROP = "ConsumableCrop",

	DRAGON_EGG = "DragonEgg",

	SHADOW = "Shadow",

	SHADOW_DRAGON = "ShadowDragon",

	GEM = "Gem",

	CRYSTAL = "Crystal",
	OPENABLE_CRYSTAL = "OpenableCrystal",
	CLAIMABLE_CRYSTAL = "ClaimableCrystal",

	NODE = "Node",
	MINABLE_NODE = "MinableNode",

	PACK = "Pack",
	OPENABLE_PACK = "OpenablePack",

	CRATE = "Crate",
	OPENABLE_CRATE = "OpenableCrate",

	KEY = "Key",

	BLUEPRINT = "Blueprint",

	CHEST = "Chest",

	VANITY_GNOME_ATTACHMENT = "VanityGnomeAttachment",
	VANITY_GNOME_LOCKED = "VanityGnomeLocked",
	VANITY_GNOME_UNLOCKED = "VanityGnomeUnlocked",

	CRITTER = "Critter",
	CRITTER_CASTER = "CritterCaster",
}

return module