--!strict

local enums = require("@game/ReplicatedStorage/Shared/Enums")

local FtueSteps = {}

-- where a beam should point; plotLocation/fixture/item carry their own payload field
export type FtueDestination =
	{ type: "plotLocation", plotLocation: { number } }
	| { type: "fixture", fixtureName: string }
	| { type: "item", itemName: string }

-- the type field holds an enums.FtueSetupType value; the other fields depend on it, so they are
-- all optional (Luau cannot discriminate a union on a numeric tag)
export type FtueSetupEntry = {
	type: number,
	itemName: string?,
	plotLocation: { number }?,
	fallDuration: number?,
}

-- the type field holds an enums.FtueConfigurationType value
export type FtueConfigurationEntry = {
	type: number,
	message: string?,
	destination: FtueDestination?,
	name: string?,
	defaultText: string?,
	touchText: string?,
	strokeName: string?,
	elementPath: string?,
	itemName: string?,
	messageTable: { [string]: string }?,
	count: number?,
	plotLocation: { number }?,
}

export type FtueItemDescriptor = {
	itemName: string,
	count: number,
}

-- the type field holds an enums.FtueTransitionType value; stepName is nil on the terminal transition
export type FtueTransitionEntry = {
	stepName: string?,
	isPrimary: boolean?,
	type: number,
	plotLocation: { number }?,
	maxDistance: number?,
	itemName: string?,
	itemDescriptors: { FtueItemDescriptor }?,
	primaryElement: number?,
	count: number?,
}

export type FtueStepData = {
	stepName: string,
	mapSaveDataToStepName: string?,
	setup: { FtueSetupEntry },
	configuration: { FtueConfigurationEntry },
	transitions: { FtueTransitionEntry },
}

local FtueStepDatas: { FtueStepData } = {
	{
		stepName = "walkIntoPlot",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Welcome! Walk into your plot",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "plotLocation",
					plotLocation = {0, -60},
				},
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "equipEgg",
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION,
				plotLocation = {0, -60},
				maxDistance = 10,
			},
		}
	},
	{
		stepName = "equipEgg",
		setup = {
			{
				type = enums.FtueSetupType.CREATE_ITEM_IN_BACKPACK,
				itemName = "Green Dragon Egg",
			}
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry egg",
				touchText = "Tap to carry egg",
			},
			{
				type = enums.FtueConfigurationType.STROKE_2D_ELEMENT,
				strokeName = "Ftue2DStroke",
				elementPath = "BackpackGui.Backpack.Hotbar",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "walkToSecondEgg",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "walkToSecondEgg",
		mapSaveDataToStepName = "equipEgg",
		setup = {
			{
				type = enums.FtueSetupType.CREATE_AND_DROP_ITEM,
				itemName = "Green Dragon Egg",
				plotLocation = {25, -80},
				fallDuration = 1.5,
			},
			{
				type = enums.FtueSetupType.CREATE_AND_DROP_ITEM,
				itemName = "Green Dragon Egg",
				plotLocation = {20, -80},
				fallDuration = 2.0,
			},
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "plotLocation",
					plotLocation = {25, -80},
				},

			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggs",
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION,
				plotLocation = {25, -80},
				maxDistance = 20,
			},
			{
				stepName = "equipEgg",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "walkToSecondEggPickupFirstEgg",
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "walkToSecondEggPickupFirstEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Pick up that egg",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "item",
					itemName = "Green Dragon Egg",
				},
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "walkToSecondEgg",
				isPrimary = true,
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggs",
		mapSaveDataToStepName = "fuseEggsEquipEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Fuse 3 eggs to create a level 1 dragon",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "plotLocation",
					plotLocation = {22, -79},
				},
			},
			{
				type = enums.FtueConfigurationType.ANIMATE_PROMPTS,
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "placeDragonOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.MERGE,
			},
			{
				stepName = "fuseEggsEquipEgg",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "fuseEggsPickupFirstEgg",
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggsEquipEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry egg",
				touchText = "Tap to carry egg",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggs",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "fuseEggsPlaceEggOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Dragon Egg",
			}
		}
	},
	{
		stepName = "fuseEggsPlaceEggOnBoard",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceCropBillboard",
				plotLocation = {22, -78},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggs",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "fuseEggsPlaceEggOnBoardEquipEgg",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggsPlaceEggOnBoardEquipEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry egg",
				touchText = "Tap to carry egg",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggsPlaceEggOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "fuseEggsPlaceTwoEggsOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggsPlaceTwoEggsOnBoard",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceCropBillboard",
				plotLocation = {22, -78},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggsPlaceEggOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Dragon Egg",
			},
			{
				stepName = "fuseEggsPlaceTwoEggsOnBoardEquipEgg",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggsPlaceTwoEggsOnBoardEquipEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry egg",
				touchText = "Tap to carry egg",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggsPlaceTwoEggsOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "fuseEggsPickupFirstEgg",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Pick up that egg",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "item",
					itemName = "Green Dragon Egg",
				},
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseEggs",
				isPrimary = true,
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Dragon Egg",
			},
		}
	},
	{
		stepName = "placeDragonOnBoard",
		mapSaveDataToStepName = "placeDragonOnBoardEquipDragon",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceDragonBillboard",
				plotLocation = {15, -75},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "walkToFirstSeed",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Dragon Level 1"
			},
			{
				stepName = "placeDragonOnBoardEquipDragon",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Dragon Level 1",
			},
		}
	},
	{
		stepName = "placeDragonOnBoardEquipDragon",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry dragon",
				touchText = "Tap to carry dragon",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "placeDragonOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Dragon Level 1",
			},
		}
	},
	{
		stepName = "walkToFirstSeed",
		setup = {
			{
				type = enums.FtueSetupType.CREATE_AND_DROP_ITEM,
				itemName = "Green Seed",
				plotLocation = {-10, -50},
				fallDuration = 1.5,
			},
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Go and pick up the seed",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "item",
					itemName = "Green Seed",
				},
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeeds",
				isPrimary = true,
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Seed",
			},
			{
				stepName = "placeDragonOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Dragon Level 1",
			},
		}
	},
	{
		stepName = "fuseSeeds",
		mapSaveDataToStepName = "fuseSeedsEquipSeed",
		setup = {
			{
				type = enums.FtueSetupType.CREATE_AND_DROP_ITEM,
				itemName = "Green Seed",
				plotLocation = {-10, -50},
				fallDuration = 1.5,
			},
			{
				type = enums.FtueSetupType.CREATE_AND_DROP_ITEM,
				itemName = "Green Seed",
				plotLocation = {-10, -54},
				fallDuration = 2,
			},
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Fuse 3 seeds to create a level 1 plant",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "item",
					itemName = "Green Seed",
				},
			},
			{
				type = enums.FtueConfigurationType.ANIMATE_PROMPTS,
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "placeCropOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.MERGE,
			},
			{
				stepName = "walkToFirstSeed",
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Seed",
			},
			{
				stepName = "fuseSeedsEquipSeed",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "fuseSeedsEquipSeed",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry seed",
				touchText = "Tap to carry seed",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeeds",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Seed",
			},
			{
				stepName = "fuseSeedsPlaceSeedOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "fuseSeedsPlaceSeedOnBoard",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceCropBillboard",
				plotLocation = {-8, -50},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeeds",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Seed",
			},
			{
				stepName = "fuseSeedsPlaceSeedOnBoardEquipSeed",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "fuseSeedsPlaceSeedOnBoardEquipSeed",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry seed",
				touchText = "Tap to carry seed",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeedsPlaceSeedOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Seed",
			},
			{
				stepName = "fuseSeedsPlaceTwoSeedsOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "fuseSeedsPlaceTwoSeedsOnBoard",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceCropBillboard",
				plotLocation = {22, -78},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeedsPlaceSeedOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Seed",
			},
			{
				stepName = "fuseSeedsPlaceTwoSeedsOnBoardEquipSeed",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "fuseSeedsPlaceTwoSeedsOnBoardEquipSeed",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry seed",
				touchText = "Tap to carry seed",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "fuseSeedsPlaceTwoSeedsOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Seed",
			},
		}
	},
	{
		stepName = "placeCropOnBoard",
		mapSaveDataToStepName = "placeCropOnBoardEquipCrop",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BILLBOARD,
				name = "FtuePlaceCropBillboard",
				plotLocation = {-15, -50},
				defaultText = "Click to place",
				touchText = "Tap to place",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "firstEat",
				isPrimary = true,
				type = enums.FtueTransitionType.PLACE_ON_BOARD,
				itemName = "Green Plant 1",
			},
			{
				stepName = "placeCropOnBoardEquipCrop",
				type = enums.FtueTransitionType.UNEQUIP_ITEM,
				itemName = "Green Plant 1",
			}
		}
	},
	{
		stepName = "placeCropOnBoardEquipCrop",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME,
				name = "FtueEquipEggFrame",
				defaultText = "Click to carry plant",
				touchText = "Tap to carry plant",
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "placeCropOnBoard",
				isPrimary = true,
				type = enums.FtueTransitionType.EQUIP_ITEM,
				itemName = "Green Plant 1",
			},
		}
	},
	{
		stepName = "firstEat",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Harvest the plant",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "item",
					itemName = "Green Plant 1",
				},
			},
			{
				type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				-- rewired 2026-august-20: collectGems/goToSell/firstSell removed (gem economy ->
				-- direct coins); skip straight to goToBuy once the player has actually harvested
				-- enough to have real money, same threshold the removed firstSell step used.
				stepName = "goToBuy",
				isPrimary = true,
				type = enums.FtueTransitionType.GET_COINS,
				count = 260,
			},
			{
				stepName = "placeCropOnBoard",
				type = enums.FtueTransitionType.PICKUP,
				itemName = "Green Plant 1",
			},
		}
	},
	-- legacy/dormant (2026-august-20): harvesting grants coins directly now, so there's nothing
	-- to collect and no sell shop to visit. Steps kept commented rather than deleted.
	-- {
	-- 	stepName = "collectGems",
	-- 	setup = {
	-- 	},
	-- 	configuration = {
	-- 		{
	-- 			type = enums.FtueConfigurationType.MESSAGE,
	-- 			message = "Collect %i gems",
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.BEAM,
	-- 			destination = {
	-- 				type = "item",
	-- 				itemName = "Green Plant 1",
	-- 			},
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.HIDE_TELEPORTERS,
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
	-- 		},
	-- 	},
	-- 	transitions = {
	-- 		{
	-- 			stepName = "goToSell",
	-- 			isPrimary = true,
	-- 			type = enums.FtueTransitionType.GET_GEMS,
	-- 			primaryElement = enums.PrimaryElements.NATURE,
	-- 			count = 5,
	-- 		},
	-- 	}
	-- },
	-- {
	-- 	stepName = "goToSell",
	-- 	setup = {
	-- 	},
	-- 	configuration = {
	-- 		{
	-- 			type = enums.FtueConfigurationType.MESSAGE,
	-- 			message = "Go to sell your gems",
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.BEAM,
	-- 			destination = {
	-- 				type = "fixture",
	-- 				fixtureName = "SellStore",
	-- 			},
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.STROKE_2D_ELEMENT,
	-- 			strokeName = "Ftue2DStroke",
	-- 			elementPath = "ScreenGui.TeleportButtons.TeleportSellButton",
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.ANIMATE_IN_TELEPORTERS,
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
	-- 		},
	-- 	},
	-- 	transitions = {
	-- 		{
	-- 			stepName = "firstSell",
	-- 			isPrimary = true,
	-- 			type = enums.FtueTransitionType.MOVE_TO_WORLD_LOCATION,
	-- 			plotLocation = {5.5, 34.5},
	-- 			maxDistance = 10,
	-- 		},
	-- 	}
	-- },
	-- {
	-- 	stepName = "firstSell",
	-- 	mapSaveDataToStepName = "goToSell",
	-- 	setup = {
	-- 	},
	-- 	configuration = {
	-- 		{
	-- 			type = enums.FtueConfigurationType.MESSAGE,
	-- 			message = "Sell all of your gems to get coins",
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.ANIMATE_PROMPTS,
	-- 		},
	-- 		{
	-- 			type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
	-- 		},
	-- 	},
	-- 	transitions = {
	-- 		{
	-- 			stepName = "goToBuy",
	-- 			isPrimary = true,
	-- 			type = enums.FtueTransitionType.GET_COINS,
	-- 			count = 260,
	-- 		},
	-- 	}
	-- },
	{
		stepName = "goToBuy",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Go to buy some items",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "fixture",
					fixtureName = "BuyStore",
				},
			},
			{
				type = enums.FtueConfigurationType.STROKE_2D_ELEMENT,
				strokeName = "Ftue2DStroke",
				elementPath = "ScreenGui.TeleportButtons.TeleportBuyButton",
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "firstBuy",
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_WORLD_LOCATION,
				plotLocation = {-7, 34.5},
				maxDistance = 10,
			},
		}
	},
	{
		stepName = "firstBuy",
		mapSaveDataToStepName = "goToBuy",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BUY_ITEM,
				itemName = "Green Seed",
				messageTable = {
					default = "Buy %i seeds",
					["1"] = "Buy 1 seed",
				},
				count = 3,
			},
			{
				type = enums.FtueConfigurationType.ANIMATE_PROMPTS,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "secondBuy",
				isPrimary = true,
				type = enums.FtueTransitionType.GET_ITEMS,
				itemDescriptors = {
					{
						itemName = "Green Seed",
						count = 3,
					},
				},
			},
		}
	},
	{
		stepName = "secondBuy",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "fixture",
					fixtureName = "BuyStore",
				},
			},
			{
				type = enums.FtueConfigurationType.BUY_ITEM,
				itemName = "Green Dragon Egg",
				messageTable = {
					default = "Buy %i eggs",
					["1"] = "Buy 1 egg",
				},
				count = 3,
			},
		},
		transitions = {
			{
				stepName = "returnToPlot",
				isPrimary = true,
				type = enums.FtueTransitionType.GET_ITEMS,
				itemDescriptors = {
					{
						itemName = "Green Dragon Egg",
						count = 3,
					},
				},
			},
		}
	},
	{
		stepName = "returnToPlot",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.CLOSE_OVERLAYS,
			},
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Return home to your plot",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "plotLocation",
					plotLocation = {0, 0},
				},
			},
			{
				type = enums.FtueConfigurationType.STROKE_2D_ELEMENT,
				strokeName = "Ftue2DStroke",
				elementPath = "ScreenGui.TeleportButtons.TeleportHomeButton",
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "returnToPlotGoInside",
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION,
				plotLocation = {0, 0},
				maxDistance = 8,
			},
		}
	},
	{
		stepName = "returnToPlotGoInside",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.CLOSE_OVERLAYS,
			},
			{
				type = enums.FtueConfigurationType.MESSAGE,
				message = "Return home to your plot",
			},
			{
				type = enums.FtueConfigurationType.BEAM,
				destination = {
					type = "plotLocation",
					plotLocation = {0, -40},
				},
			},
			{
				type = enums.FtueConfigurationType.DISABLE_BUY_STORE,
			},
			{
				type = enums.FtueConfigurationType.DISABLE_SELL_STORE,
			},
		},
		transitions = {
			{
				stepName = "keepOnFusing",
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION,
				plotLocation = {0, -40},
				maxDistance = 8,
			},
		}
	},
	{
		stepName = "keepOnFusing",
		setup = {
		},
		configuration = {
			{
				type = enums.FtueConfigurationType.SYSTEM_MESSAGE,
				message = "Keep on fusing! You can ride level 4 dragons!",
			},
		},
		transitions = {
			{
				stepName = nil,
				isPrimary = true,
				type = enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION,
				plotLocation = {0, -45},
				maxDistance = 10,
			},
		}
	},
}

function FtueSteps.validateStepName(stepName: string?): boolean
	for _, ftueStepData in FtueStepDatas do
		if ftueStepData.stepName ~= stepName then
			continue
		end
		return true
	end

	return false
end

function FtueSteps.getFirstFtueStepName(): string
	return FtueStepDatas[1].stepName
end

function FtueSteps.getStepDataForStepName(stepName: string?): FtueStepData?
	for _, ftueStepData in FtueStepDatas do
		if ftueStepData.stepName ~= stepName then
			continue
		end
		return ftueStepData
	end

	warn("stepName not found", stepName)

	return nil
end

function FtueSteps:mapStepNameFromSaveData(stepName: string?): string?
	local stepData = assert(FtueSteps.getStepDataForStepName(stepName), "no step data for step name " .. tostring(stepName))
	if not stepData.mapSaveDataToStepName then
		return stepName
	end

	return stepData.mapSaveDataToStepName
end

return FtueSteps
