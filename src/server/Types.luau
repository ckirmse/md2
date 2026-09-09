--!strict

--[[
	Central type module: every type used across module boundaries lives here, so any file can
	annotate cross-module values without requiring the module that implements them (which would
	recreate the require cycles that dependency injection removed). Types.luau must never require
	another server module.

	Two sections:
	- HAND-MAINTAINED (top): the class-hierarchy interfaces (Item/BaseObject/DataType/ItemMover
	  families). Subclass types compose by intersection and list only members new to that class;
	  see CLAUDE.md "How the class hierarchies are typed".
	- GENERATED (below the marker): consumer interfaces for the initClass-injected singletons and
	  PlayerData, derived from their annotated definitions by tools/generate_types.py. The values
	  still arrive untyped through initClass(deps), so these are a promise kept in sync by
	  regenerating after signature changes, not something the solver checks.
]]

export type TimerFields = {
	_running: boolean,
	_startTime: number?,
	_duration: number?,
	_task: thread?,
	func: () -> (),
}

export type Timer = {
	_running: boolean,
	_startTime: number?,
	_duration: number?,
	_task: thread?,
	func: () -> (),

	start: (self: Timer, duration: number) -> (),
	getTimeLeft: (self: Timer) -> number?,
	isRunning: (self: Timer) -> boolean,
	stop: (self: Timer) -> (),
	cancel: (self: Timer) -> (),
}

export type DubinsPlan = {
	path: { CFrame },
	type: string?,
}

export type GettingEatenState = {
	dragonItemId: number,
	step: number,
	totalSteps: number,
	currentCountPerStep: number,
	maxCountPerStep: number,
}

export type OpeningState = {
	dragonItemId: number?,
	completeTime: number?,
	endTimer: Timer?,
	isComplete: boolean?,
}

export type Repulsor = {
	position: Vector3,
	boardSpacing: number,
}

-- obj (the world model or part cloned from the GameData template) and part (its primary part) are
-- used dynamically throughout and templates are Studio data, so they stay untyped
export type ItemFields = {
	itemId: number,
	itemName: string,
	type: string,
	userId: number,
	isParentingOnLoad: boolean,
	obj: any,
	part: any,
	prevObjParent: any,
	venueChangedEvent: BindableEvent,
	parentChangedConnect: RBXScriptConnection?,
	settleFinalPosition: Vector3?,
	settleTween: Tween?,
	settleTweenCompletedConnect: RBXScriptConnection?,
	settleTweenConnect: RBXScriptConnection?,
}

export type Item = {
	itemId: number,
	itemName: string,
	type: string,
	userId: number,
	isParentingOnLoad: boolean,
	obj: any,
	part: any,
	prevObjParent: any,
	venueChangedEvent: BindableEvent,
	parentChangedConnect: RBXScriptConnection?,
	settleFinalPosition: Vector3?,
	settleTween: Tween?,
	settleTweenCompletedConnect: RBXScriptConnection?,
	settleTweenConnect: RBXScriptConnection?,

	-- methods (own and inherited)
	activate: (self: Item) -> (),
	calculateSettleOnGroundStep: (self: Item, basePosition: Vector3, repulsors: { { position: Vector3, boardSpacing: number } }) -> Vector3?,
	canBePickedUp: (self: Item) -> boolean,
	cleanupSettleOnGroundInWorkspace: (self: Item) -> (),
	clone: (self: Item, newItemId: number) -> any,
	copyToPlayer: (self: Item, count: number?, player: Player) -> any,
	createAndDecayHighlight: (self: Item, color: Color3?) -> (),
	createSettleTween: (self: Item, duration: number, cframe: CFrame) -> Tween,
	destroy: (self: Item) -> (),
	equip: (self: Item) -> (),
	findTool: (self: Item) -> Tool?,
	getCapacityCost: (self: Item) -> number,
	getCount: (self: Item) -> number,
	getDataDumpString: (self: Item) -> string,
	getDisplayName: (self: Item) -> string,
	getIsParentingOnLoad: (self: Item) -> boolean,
	getItemData: (self: Item) -> any,
	getItemDataType: (self: Item) -> any,
	getItemId: (self: Item) -> number,
	getItemName: (self: Item) -> string,
	getObj: (self: Item) -> any,
	getPart: (self: Item) -> any,
	getPlayer: (self: Item) -> Player?,
	getPlayerData: (self: Item) -> any,
	getSafeCFrameOnLoad: (self: Item, cframe: CFrame) -> CFrame,
	getSaveData: (self: Item, itemIdMap: any) -> any,
	getSettleCFrameForPosition: (self: Item, position: Vector3) -> CFrame,
	getSettleDurationForPosition: (self: Item, position: Vector3) -> number,
	getSettlePositionForLocation: (self: Item, location: Vector3) -> Vector3,
	getToolActivationItem: (self: Item) -> any,
	getToolName: (self: Item) -> string,
	getType: (self: Item) -> string,
	getUserId: (self: Item) -> number,
	getVenueChangedEvent: (self: Item) -> RBXScriptSignal,
	getVisibleName: (self: Item) -> string,
	getWorldSaveCFrame: (self: Item) -> CFrame,
	initItem: (self: Item, obj: any) -> (),
	loadSaveData: (self: Item, itemSaveData: any, itemIdMap: any) -> (),
	moveFromPlayerToWorkspace: (self: Item) -> (),
	notifyLoadComplete: (self: Item, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?) -> (),
	notifyMergingWithTriggerItem: (self: Item, triggerItem: any) -> (),
	notifyNewClone: (self: Item) -> (),
	notifyNewCopy: (self: Item, sourceItem: any, count: number?) -> (),
	notifyParentChanged: (self: Item) -> (),
	notifyParentPlayer: (self: Item) -> (),
	notifyParentWorkspace: (self: Item) -> (),
	notifyTooLow: (self: Item) -> (),
	notifyToolActivated: (self: Item) -> (),
	notifyVisibleNameChanged: (self: Item) -> (),
	pickup: (self: Item) -> (),
	processClone: (self: Item) -> (),
	processCopy: (self: Item, sourceItem: any, count: number?) -> (),
	processEquipped: (self: Item) -> (),
	processLoadComplete: (self: Item, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?) -> (),
	processParentPlayer: (self: Item) -> (),
	processParentWorkspace: (self: Item) -> (),
	processUnequipped: (self: Item) -> (),
	putInBackpack: (self: Item) -> Tool?,
	reduceCount: (self: Item, count: number) -> boolean,
	resetBillboard: (self: Item) -> (),
	setBackpackIndex: (self: Item, index: number?) -> (),
	setPreventSettling: (self: Item) -> (),
	setVenueWorkspaceAvailable: (self: Item) -> (),
	setVenueWorkspaceBusy: (self: Item) -> (),
	setVenueWorkspaceSettling: (self: Item) -> (),
	settleOnGroundInWorkspace: (self: Item, doneFunc: () -> (), extraRepulsors: { { position: Vector3, boardSpacing: number } }?) -> (),
	setupChildPartsToObj: (self: Item) -> (),
	setupChildPartsToPrimaryPart: (self: Item) -> (),
	teleportToRecoveryPosition: (self: Item) -> (),
	tryGetGripCFrame: (self: Item) -> CFrame?,
	updateDataDump: (self: Item) -> (),
}

export type NumberItemFields = ItemFields & {
	number: number,
}

-- inherited and overridden members come from Item; only members new to NumberItem are listed here
export type NumberItem = Item & {
	number: number,

	addCount: (self: NumberItem, count: number) -> (),
	canStackWith: (self: NumberItem, item: any) -> boolean,
	decrementCount: (self: NumberItem) -> (),
	getVisibleNameSuffix: (self: NumberItem) -> string,
	incrementCount: (self: NumberItem) -> (),
	init: (self: NumberItem) -> (),
	notifyNumberChanged: (self: NumberItem) -> (),
	processNumberChanged: (self: NumberItem) -> (),
	setCount: (self: NumberItem, count: number) -> (),
	splitOffCount: (self: NumberItem, count: number) -> NumberItem?,
	splitOffOne: (self: NumberItem) -> NumberItem?,
}

export type MItemFields = NumberItemFields & {
	mutation: number,
	modifications: { number },
}

-- inherited and overridden members come from NumberItem; only members new to MItem are listed here
export type MItem = NumberItem & {
	modifications: { number },
	mutation: number,

	addModification: (self: MItem, modification: number) -> (),
	calculateModificationMultiplier: (self: MItem) -> number,
	doesHaveModification: (self: MItem, modification: number) -> boolean,
	getEncodedModifications: (self: MItem) -> string,
	getModificationCount: (self: MItem) -> number,
	getModifications: (self: MItem) -> { number },
	getMutation: (self: MItem) -> number,
	hasIdenticalModifications: (self: MItem, item: any) -> boolean,
	hasIdenticalMutation: (self: MItem, item: any) -> boolean,
	isMItemIdentical: (self: MItem, item: any) -> boolean,
	notifyModificationsChanged: (self: MItem) -> (),
	processModificationsChanged: (self: MItem) -> (),
	processMutationChanged: (self: MItem) -> (),
	setModifications: (self: MItem, modifications: { number }) -> (),
	setMutation: (self: MItem, mutation: number) -> (),
	toggleModification: (self: MItem, modification: number) -> (),
}

export type CropFields = MItemFields & {
	state: number?,
	doPreventSettling: boolean?,
	currentFoodAmount: number,
	gettingEaten: GettingEatenState,
	random: Random,
	heartbeatConnect: RBXScriptConnection?,
}

-- inherited and overridden members come from MItem; only members new to Crop are listed here
export type Crop = MItem & {
	currentFoodAmount: number,
	doPreventSettling: boolean?,
	gettingEaten: GettingEatenState,
	heartbeatConnect: RBXScriptConnection?,
	random: Random,
	state: number?,

	addGrowTime: (self: Crop, elapsedSec: number) -> (),
	applyModificationsToFruitIfNeeded: (self: Crop) -> (),
	beginGettingEaten: (self: Crop, dragon: any) -> (),
	beginGrowing: (self: Crop) -> (),
	beginIdle: (self: Crop) -> (),
	beginState: (self: Crop, state: number?, ...any) -> (),
	checkFullyGrown: (self: Crop) -> (),
	cleanupGettingEaten: (self: Crop) -> (),
	cleanupGrowing: (self: Crop) -> (),
	cleanupIdle: (self: Crop) -> (),
	endGettingEaten: (self: Crop) -> (),
	endState: (self: Crop) -> (),
	finishPlaceInWorkspace: (self: Crop) -> (),
	getCurrentFoodAmount: (self: Crop) -> number,
	growFull: (self: Crop) -> (),
	isConsumable: (self: Crop) -> (),
	isGettingEaten: (self: Crop) -> (),
	isGrowing: (self: Crop) -> (),
	isPlayerCloseEnoughToShootFireballAtCrop: (self: Crop, player: Player) -> (),
	notifyDragonComingToEat: (self: Crop, dragon: any) -> (),
	notifyDragonNoLongerComingToEat: (self: Crop, dragon: any) -> (),
	notifyDragonStartEating: (self: Crop, dragon: any) -> (),
	setState: (self: Crop, state: number?, data: any) -> (),
	tryGrow: (self: Crop, elapsedSec: number) -> (),
	tryStepGetEaten: (self: Crop) -> (),
	updateFoodVisuals: (self: Crop) -> (),
}

export type DragonEggFields = MItemFields & {
	doPreventSettling: boolean?,
}

-- inherited and overridden members come from MItem; only members new to DragonEgg are listed here
export type DragonEgg = MItem & {
	doPreventSettling: boolean?,

}

-- the per-state scratch tables (movingToEat, eating, opening, ...) are dynamic bags that get reset
-- with fresh literals as states change, so they stay untyped
export type ShadowDragonFields = MItemFields & {
	state: number?,
	doPreventSettling: boolean?,
	power: number?,
	random: Random,
	stamina: any,
	overrideMaxStamina: number?,
	isRiding: boolean?,
	ridingBeginTime: number?,
	lastRidingUpdateTime: number?,
	wasRidingMaxDuration: boolean?,
	lastKnownGoodIdleLocation: Vector3?,
	lastKnownGoodOutsidePosition: Vector3?,
	eating: any,
	movingToEat: any,
	movingToIdle: any,
	movingToMine: any,
	movingToOpen: any,
	movingToOutside: any,
	opening: any,
	settling: any,
	stableSlotIndex: number?,
}

-- inherited and overridden members come from MItem; only members new to ShadowDragon are listed here
export type ShadowDragon = MItem & {
	doPreventSettling: boolean?,
	power: number?,
	stableSlotIndex: number?,
	eating: any,
	isRiding: boolean?,
	lastKnownGoodIdleLocation: Vector3?,
	lastKnownGoodOutsidePosition: Vector3?,
	lastRidingUpdateTime: number?,
	movingToEat: any,
	movingToIdle: any,
	movingToMine: any,
	movingToOpen: any,
	movingToOutside: any,
	opening: any,
	overrideMaxStamina: number?,
	random: Random,
	ridingBeginTime: number?,
	settling: any,
	stamina: any,
	state: number?,
	wasRidingMaxDuration: boolean?,

	beginEating: (self: ShadowDragon, crop: any) -> (),
	beginIdle: (self: ShadowDragon, data: any) -> (),
	beginMovingToEat: (self: ShadowDragon, crop: any) -> (),
	beginMovingToIdle: (self: ShadowDragon) -> (),
	beginMovingToIdleWithCFrame: (self: ShadowDragon, destCFrame: CFrame) -> (),
	beginMovingToIdleWithLocation: (self: ShadowDragon, location: Vector3) -> (),
	beginMovingToIdleWithPosition: (self: ShadowDragon, position: Vector3) -> (),
	beginMovingToMine: (self: ShadowDragon, node: any) -> (),
	beginMovingToOpen: (self: ShadowDragon, crystal: any) -> (),
	beginMovingToOutside: (self: ShadowDragon, data: any) -> (),
	beginOpening: (self: ShadowDragon, crystal: any) -> (),
	beginOutside: (self: ShadowDragon, data: any) -> (),
	beginSettling: (self: ShadowDragon) -> (),
	beginState: (self: ShadowDragon, state: number?, data: any) -> (),
	calculateGoodIdleLocation: (self: ShadowDragon) -> Vector3,
	calculateGoodSaveCFrame: (self: ShadowDragon) -> CFrame,
	calculateIdleHeightAtLocation: (self: ShadowDragon, location: Vector3) -> number,
	canChargeUp: (self: ShadowDragon) -> boolean,
	cleanupEating: (self: ShadowDragon) -> (),
	cleanupIdle: (self: ShadowDragon) -> (),
	cleanupMovingToEat: (self: ShadowDragon) -> (),
	cleanupMovingToIdle: (self: ShadowDragon) -> (),
	cleanupMovingToMine: (self: ShadowDragon) -> (),
	cleanupMovingToOpen: (self: ShadowDragon) -> (),
	cleanupMovingToOutside: (self: ShadowDragon) -> (),
	cleanupOpening: (self: ShadowDragon) -> (),
	cleanupOutside: (self: ShadowDragon) -> (),
	cleanupSettling: (self: ShadowDragon) -> (),
	endState: (self: ShadowDragon) -> (),
	getEatingItemId: (self: ShadowDragon) -> any,
	getFlapDataForCurrentState: (self: ShadowDragon) -> (number, number),
	getMaxStamina: (self: ShadowDragon) -> number,
	getMovingToEatItemId: (self: ShadowDragon) -> any,
	getMovingToOpenItemId: (self: ShadowDragon) -> any,
	getPower: (self: ShadowDragon) -> number,
	getStableSlotIndex: (self: ShadowDragon) -> number?,
	isAvailableToEat: (self: ShadowDragon) -> boolean,
	isAvailableToMine: (self: ShadowDragon) -> boolean,
	isAvailableToOpen: (self: ShadowDragon) -> boolean,
	isClientControlling: (self: ShadowDragon) -> boolean,
	isInFreeFlyZone: (self: ShadowDragon) -> boolean,
	moveDragonFromBackpackToWorkspace: (self: ShadowDragon) -> (),
	notifyEndEating: (self: ShadowDragon) -> (),
	notifyEndMovingToEat: (self: ShadowDragon) -> (),
	notifyEndMovingToOpen: (self: ShadowDragon) -> (),
	notifyEndOpening: (self: ShadowDragon) -> (),
	notifyItemMoverDone: (self: ShadowDragon) -> (),
	notifyPlayerReturnedToPlot: (self: ShadowDragon) -> (),
	notifyRideBegin: (self: ShadowDragon) -> (),
	notifyRideEnd: (self: ShadowDragon) -> (),
	notifyShouldChargeUp: (self: ShadowDragon) -> (),
	notifyShouldEatCrop: (self: ShadowDragon, crop: any) -> (),
	notifyShouldMineNode: (self: ShadowDragon, node: any) -> (),
	notifyShouldMoveToEat: (self: ShadowDragon, crop: any) -> (),
	notifyShouldMoveToIdle: (self: ShadowDragon) -> (),
	notifyShouldMoveToIdleAtCurrentLocation: (self: ShadowDragon) -> (),
	notifyShouldMoveToMine: (self: ShadowDragon, node: any) -> (),
	notifyShouldMoveToOpen: (self: ShadowDragon, crystal: any) -> (),
	notifyShouldOpenCrystal: (self: ShadowDragon, crystal: any) -> (),
	notifyShouldShootFireballAtCritter: (self: ShadowDragon, critter: any) -> (),
	notifyShouldShootFireballAtCrop: (self: ShadowDragon, crop: any) -> (),
	notifyUnequippableEquipped: (self: ShadowDragon) -> (),
	parkInStableSlot: (self: ShadowDragon, slotCFrame: CFrame) -> (),
	recomputePower: (self: ShadowDragon) -> (),
	returnToBackpackFromStableSlot: (self: ShadowDragon) -> (),
	setClientControlMotion: (self: ShadowDragon) -> (),
	setFlapData: (self: ShadowDragon, periodDivisor: number, amplitudeMultiplier: number) -> (),
	setOverrideMaxStamina: (self: ShadowDragon, stamina: number?) -> (),
	setServerControlMotion: (self: ShadowDragon) -> (),
	setStableSlotIndex: (self: ShadowDragon, stableSlotIndex: number?) -> (),
	setState: (self: ShadowDragon, state: number?, data: any) -> (),
	setupIdleInWorkspace: (self: ShadowDragon) -> (),
	trySetRidingItemCFrame: (self: ShadowDragon, time: number, cframe: CFrame) -> (),
	tryStepUpdateStaminaAndFreeFlyZone: (self: ShadowDragon) -> (),
}

export type CrystalFields = NumberItemFields & {
	state: number?,
	doPreventSettling: boolean?,
	opening: OpeningState,
}

-- inherited and overridden members come from NumberItem; only members new to Crystal are listed here
export type Crystal = NumberItem & {
	doPreventSettling: boolean?,
	opening: OpeningState,
	state: number?,

	beginIdle: (self: Crystal) -> (),
	beginOpened: (self: Crystal) -> (),
	beginOpening: (self: Crystal, dragon: any, remainingSec: number?) -> (),
	beginState: (self: Crystal, state: number?, ...any) -> (),
	cleanupIdle: (self: Crystal) -> (),
	cleanupOpened: (self: Crystal) -> (),
	cleanupOpening: (self: Crystal) -> (),
	endState: (self: Crystal) -> (),
	finishOpeningSuccessfully: (self: Crystal) -> (),
	finishPlaceInWorkspace: (self: Crystal) -> (),
	getRemainingOpeningSec: (self: Crystal) -> number?,
	isOpened: (self: Crystal) -> (),
	isOpening: (self: Crystal) -> (),
	notifyClaim: (self: Crystal) -> (),
	notifyDragonComingToOpen: (self: Crystal, dragon: any) -> (),
	notifyDragonNoLongerComingToOpen: (self: Crystal, dragon: any) -> (),
	notifyDragonStartOpening: (self: Crystal, dragon: any) -> (),
	notifyEndGettingOpened: (self: Crystal) -> (),
	setState: (self: Crystal, state: number?, ...any) -> (),
}

export type GemFields = NumberItemFields & {
	isVacuuming: boolean?,
}

-- inherited and overridden members come from NumberItem; only members new to Gem are listed here
export type Gem = NumberItem & {
	isVacuuming: boolean?,

	beginVacuum: (self: Gem) -> (),
	checkVacuum: (self: Gem) -> (),
	grantCoinsInsteadOfSpawning: (self: Gem) -> (),
}

export type PackFields = NumberItemFields & {
	state: number?,
	doPreventSettling: boolean?,
}

-- inherited and overridden members come from NumberItem; only members new to Pack are listed here
export type Pack = NumberItem & {
	doPreventSettling: boolean?,
	state: number?,

	beginIdle: (self: Pack) -> (),
	beginState: (self: Pack, state: number?, ...any) -> (),
	cleanupIdle: (self: Pack) -> (),
	endState: (self: Pack) -> (),
	finishPlaceInWorkspace: (self: Pack) -> (),
	notifyShouldOpen: (self: Pack) -> (),
	setState: (self: Pack, state: number?, ...any) -> (),
}

export type KeyFields = NumberItemFields & {
	doPreventSettling: boolean?,
}

-- inherited and overridden members come from NumberItem; only members new to Key are listed here
export type Key = NumberItem & {
	doPreventSettling: boolean?,

}

export type BlueprintFields = NumberItemFields & {
	doPreventSettling: boolean?,
}

-- inherited and overridden members come from NumberItem; only members new to Blueprint are listed here
export type Blueprint = NumberItem & {
	doPreventSettling: boolean?,

}

export type CrateFields = NumberItemFields & {
	state: number?,
	doPreventSettling: boolean?,
	rewardType: string?,
	lootTableName: string?,
	displayText: string?,
}

-- inherited and overridden members come from NumberItem; only members new to Crate are listed here
export type Crate = NumberItem & {
	displayText: string?,
	doPreventSettling: boolean?,
	lootTableName: string?,
	rewardType: string?,
	state: number?,

	beginIdle: (self: Crate) -> (),
	beginState: (self: Crate, state: number?, ...any) -> (),
	cleanupIdle: (self: Crate) -> (),
	endState: (self: Crate) -> (),
	finishPlaceInWorkspace: (self: Crate) -> (),
	notifyShouldOpen: (self: Crate) -> (),
	setRewardSource: (self: Crate, rewardType: string?, lootTableName: string?, displayText: string?) -> (),
	setState: (self: Crate, state: number?, ...any) -> (),
}

export type BaseObjectFields = {
	-- the cloned world model; untyped because it flows through GameData templates
	obj: any,
	objectId: number,
	objectName: string,
}

export type BaseObject = {
	-- the cloned world model; untyped because it flows through GameData templates
	obj: any,
	objectId: number,
	objectName: string,

	-- methods (own and inherited)
	destroy: (self: BaseObject) -> (),
	getObj: (self: BaseObject) -> any,
	getObjectData: (self: BaseObject) -> any,
	getObjectId: (self: BaseObject) -> number,
	getObjectName: (self: BaseObject) -> string,
}

export type NodeFields = BaseObjectFields & {
	state: number?,
}

-- inherited and overridden members come from BaseObject; only members new to Node are listed here
export type Node = BaseObject & {
	state: number?,

	beginEmpty: (self: Node) -> (),
	beginGettingMined: (self: Node, dragon: any) -> (),
	beginIdle: (self: Node) -> (),
	beginState: (self: Node, state: number?, data: any) -> (),
	canBeMinedByPlayer: (self: Node, player: Player) -> (),
	cleanupEmpty: (self: Node) -> (),
	cleanupGettingMined: (self: Node) -> (),
	cleanupIdle: (self: Node) -> (),
	endState: (self: Node) -> (),
	getMineTargetPosition: (self: Node) -> (),
	getSaveData: (self: Node) -> any,
	isPlayerCloseEnoughToMineWhileRiding: (self: Node, player: Player) -> (),
	isPlayerCloseEnoughToSummonToMine: (self: Node, player: Player) -> (),
	loadSaveData: (self: Node, objectSaveData: any) -> (),
	notifyDragonComingToMine: (self: Node, dragon: any) -> (),
	notifyMinedByDragon: (self: Node, dragon: any) -> (),
	notifyRefill: (self: Node) -> (),
	setState: (self: Node, state: number?, data: any) -> (),
}

export type ChestFields = BaseObjectFields & {
	state: number?,
}

-- inherited and overridden members come from BaseObject; only members new to Chest are listed here
export type Chest = BaseObject & {
	state: number?,

	beginIdle: (self: Chest) -> (),
	beginOpened: (self: Chest) -> (),
	beginOpening: (self: Chest) -> (),
	beginState: (self: Chest, state: number?, ...any) -> (),
	canKeyOpen: (self: Chest, key: any) -> (),
	cleanupIdle: (self: Chest) -> (),
	cleanupOpened: (self: Chest) -> (),
	cleanupOpening: (self: Chest) -> (),
	endState: (self: Chest) -> (),
	getSaveData: (self: Chest) -> any,
	isClosed: (self: Chest) -> (),
	isPlayerCloseEnoughToOpen: (self: Chest, player: Player) -> (),
	loadSaveData: (self: Chest, objectSaveData: any) -> (),
	notifyShouldOpen: (self: Chest, key: any) -> (),
	setState: (self: Chest, state: number?, data: any) -> (),
}

export type CritterFields = BaseObjectFields & {
	state: number?,
	baseTime: number,
	radius: number,
	period: number,
}

-- inherited and overridden members come from BaseObject; only members new to Critter are listed here
export type Critter = BaseObject & {
	baseTime: number,
	period: number,
	radius: number,
	state: number?,

	beginIdle: (self: Critter) -> (),
	beginOpened: (self: Critter) -> (),
	beginState: (self: Critter, state: number?, ...any) -> (),
	canKeyOpen: (self: Critter, key: any) -> (),
	cleanupIdle: (self: Critter) -> (),
	cleanupOpened: (self: Critter) -> (),
	endState: (self: Critter) -> (),
	getCurrentPosition: (self: Critter) -> Vector3,
	getFuturePosition: (self: Critter, timeFromNowSec: number) -> Vector3,
	getSaveData: (self: Critter) -> any,
	isPlayerCloseEnoughToOpen: (self: Critter, player: Player) -> (),
	isPlayerCloseEnoughToShootFireballAtCritter: (self: Critter, player: Player) -> (),
	loadSaveData: (self: Critter, objectSaveData: any) -> (),
	notifyShotByDragon: (self: Critter, dragon: any) -> (),
	setState: (self: Critter, state: number?, data: any) -> (),
}

-- data holds the raw GameData module table and dataTableShape holds the shape-spec mini-DSL handed
-- to Validate.isTableShape; both are heterogeneous, so they stay untyped
export type DataTypeFields = {
	type: string,
	required: { any },
	optional: { any },
	data: any,
	dataTableShape: any,
	name: string?,
}

export type DataType = {
	type: string,
	required: { any },
	optional: { any },
	data: any,
	dataTableShape: any,
	name: string?,

	-- methods (own and inherited)
	addDataFromInstances: (self: DataType) -> (),
	getRawData: (self: DataType) -> any,
	processInstances: (self: DataType) -> (),
	setProperties: (self: DataType, data: any) -> (),
	validateData: (self: DataType) -> boolean,
	validateInstances: (self: DataType) -> boolean,
}

export type ObjectTypeFields = DataTypeFields & {
	template: Instance?,
}

-- inherited and overridden members come from DataType; only members new to ObjectType are listed here
export type ObjectType = DataType & {
	template: Instance?,

	getTemplate: (self: ObjectType) -> Instance?,
	setTemplate: (self: ObjectType, template: Instance?) -> (),
}

-- inherited and overridden members come from ObjectType; only members new to CropObjectType are listed here
export type CropObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to DragonEggObjectType are listed here
export type DragonEggObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to CrystalObjectType are listed here
export type CrystalObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to GemObjectType are listed here
export type GemObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to PackObjectType are listed here
export type PackObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to KeyObjectType are listed here
export type KeyObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to BlueprintObjectType are listed here
export type BlueprintObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to CrateObjectType are listed here
export type CrateObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to ShadowDragonObjectType are listed here
export type ShadowDragonObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to NodeObjectType are listed here
export type NodeObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to ChestObjectType are listed here
export type ChestObjectType = ObjectType

-- inherited and overridden members come from ObjectType; only members new to CritterObjectType are listed here
export type CritterObjectType = ObjectType

export type ItemMover = {
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,

	-- methods (own and inherited)
	destroy: (self: ItemMover) -> (),
	getObj: (self: ItemMover) -> any,
	getPart: (self: ItemMover) -> any,
	getStepCallback: (self: ItemMover) -> ((CFrame) -> ())?,
	notifyDone: (self: ItemMover) -> (),
	setStepCallback: (self: ItemMover, func: ((CFrame) -> ())?) -> (),
	tryBegin: (self: ItemMover) -> boolean,
}

-- inherited and overridden members come from ItemMover; only members new to CircleItemMover are listed here
export type CircleItemMover = ItemMover & {
	currentTween: Tween?,
	heartbeatConnect: RBXScriptConnection?,
	plan: DubinsPlan?,
	planIndex: number,
	radius: number,
	speed: number,
	tweenCompletedConnect: RBXScriptConnection?,

	beginDubins: (self: CircleItemMover) -> boolean,
	beginLevel: (self: CircleItemMover) -> (),
	beginMoving: (self: CircleItemMover) -> (),
	runHeartbeat: (self: CircleItemMover, deltaTime: number) -> (),
	tryApplyDubinsStepCount: (self: CircleItemMover, count: number) -> boolean,
}

-- inherited and overridden members come from ItemMover; only members new to DubinsItemMover are listed here
export type DubinsItemMover = ItemMover & {
	currentTween: Tween?,
	minRadius: number,
	plan: DubinsPlan?,
	planIndex: number,
	runConnect: RBXScriptConnection?,
	tweenCompletedConnect: RBXScriptConnection?,

	beginDubins: (self: DubinsItemMover) -> boolean,
	beginLevel: (self: DubinsItemMover) -> (),
	beginMoving: (self: DubinsItemMover) -> (),
	run: (self: DubinsItemMover, deltaTime: number) -> (),
	tryApplyDubinsStep: (self: DubinsItemMover) -> boolean,
}

-- inherited and overridden members come from ItemMover; only members new to DirectFlyItemMover are listed here
export type DirectFlyItemMover = ItemMover & {
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,

	beginMoving: (self: DirectFlyItemMover) -> (),
}

-- inherited and overridden members come from ItemMover; only members new to PathfindingItemMover are listed here
export type PathfindingItemMover = ItemMover & {
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
	waypointIndex: number,
	waypoints: { PathWaypoint },

	beginMovingToNextWaypoint: (self: PathfindingItemMover) -> (),
}

-- inherited and overridden members come from ItemMover; only members new to UpAndOverItemMover are listed here
export type UpAndOverItemMover = ItemMover & {
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,

	beginMoveOver: (self: UpAndOverItemMover) -> (),
	beginMoveUp: (self: UpAndOverItemMover) -> (),
	beginMoving: (self: UpAndOverItemMover) -> (),
}

-- ===== GENERATED SECTION -- everything below is written by tools/generate_types.py; do not edit by hand =====

export type GameController = {
	addPrimaryElementXpToPlayer: (self: GameController, player: Player?, primaryElement: number, xpDiff: number, part: any) -> (),
	addRemoteEventHandler: (self: GameController, remoteEventName: string, funcName: string) -> (),
	areChestIslandsEnabled: (self: GameController) -> boolean,
	calculateEatingSteps: (self: GameController, dragon: any, crop: any) -> (number, number),
	calculateGemsForHarvest: (self: GameController, dragon: any, crop: any) -> number,
	calculateXpForHarvest: (self: GameController, dragon: any, crop: any) -> number,
	convertBankedGemsToCoins: (self: GameController, player: Player) -> (),
	createItemsFromItemCreationDataForPlayer: (self: GameController, itemCreationData: { [string]: number }, player: Player?) -> { any },
	createPollTimer: (self: GameController) -> (),
	endDragonsEatingCrop: (self: GameController, crop: any) -> (),
	getAllBlueprintNames: (self: GameController) -> { string },
	getAllBuyableItemNames: (self: GameController) -> { string },
	getAllCropNames: (self: GameController) -> { string },
	getAllCrystalNames: (self: GameController) -> { string },
	getAllDragonEggNames: (self: GameController) -> { string },
	getAllDragonNames: (self: GameController) -> { string },
	getAllGemItemNames: (self: GameController) -> { string },
	getAllIslandNames: (self: GameController) -> { string },
	getAllKeyNames: (self: GameController) -> { string },
	getAllPackNames: (self: GameController) -> { string },
	getAllPlayerUserIds: (self: GameController) -> { number },
	getAllRobuxBuyableItemNames: (self: GameController) -> { string },
	getAllSellableItemNames: (self: GameController) -> { string },
	getBestDragonToEatForPlayer: (self: GameController, player: Player, crop: any) -> any,
	getBestDragonToMineForPlayer: (self: GameController, player: Player, crystal: any) -> any,
	getBestDragonToOpenForPlayer: (self: GameController, player: Player, crystal: any) -> (any, any),
	getBlueprintNamesForRarity: (self: GameController, rarity: number) -> { string },
	getClosestNodeToPlayer: (self: GameController, player: Player) -> any,
	getConfigValue: (self: GameController, key: string) -> any,
	getCountEatingCrop: (self: GameController, crop: any) -> number,
	getDragonBeingHeldByPlayer: (self: GameController, player: Player) -> any,
	getGemItemNameForPrimaryElement: (self: GameController, primaryElement: number) -> string?,
	getLevel0ItemNameForItem: (self: GameController, item: any) -> string?,
	getLevelEquivalentItemNameForItem: (self: GameController, item: any, level: number) -> string?,
	getNextObjectId: (self: GameController) -> number,
	getPlayerByName: (self: GameController, playerName: any) -> Player?,
	getPlayerData: (self: GameController, player: Player?) -> any,
	getRemoteEventMetrics: (self: GameController) -> any,
	grantCoinsForGemValue: (self: GameController, player: Player?, primaryElement: number, gemCount: number) -> (),
	init: (self: GameController) -> (),
	initCollision: (self: GameController) -> (),
	isIndexEnabled: (self: GameController) -> boolean,
	isLocationInFreeFlyZone: (self: GameController, location: Vector3) -> boolean,
	isPlayerRidingItemId: (self: GameController, player: Player, itemId: any) -> boolean,
	isTradingEnabled: (self: GameController) -> boolean,
	listenToPlayerEvents: (self: GameController) -> (),
	listenToRemoteEvents: (self: GameController) -> (),
	loadGameConfig: (self: GameController) -> (),
	notifyCropFullyEaten: (self: GameController, crop: any, dragon: any, xp: number, gemCount: number) -> (),
	notifyCropNoLongerAvailable: (self: GameController, crop: any) -> (),
	notifyCrystalNoLongerAvailable: (self: GameController, crystal: any) -> (),
	notifyDragonStoppedEatingCrop: (self: GameController, dragon: any, crop: any) -> (),
	notifyDragonStoppedOpeningCrystal: (self: GameController, dragon: any, crystal: any) -> (),
	notifyPlayerLevelChanged: (self: GameController, player: Player) -> (),
	notifyPlayerReceiveTradeRequestsOptionChanged: (self: GameController, player: Player) -> (),
	notifyUpdateGameConfigSnapshot: (self: GameController) -> (),
	processPlayerAdd: (self: GameController, player: Player) -> (),
	processPlayerRemove: (self: GameController, player: Player) -> (),
	processPollTimer: (self: GameController) -> (),
	refillNodes: (self: GameController) -> (),
	refreshGameConfig: (self: GameController) -> (),
	removePreProfileSaveData: (self: GameController, player: Player, saveData: any) -> (),
	restockFixedIslands: (self: GameController, islandName: string) -> (),
	restockIslands: (self: GameController) -> (),
	run: (self: GameController, deltaTime: number) -> (),
	sendSystemMessageToAllPlayers: (self: GameController, message: string) -> (),
	sendSystemMessageToPlayer: (self: GameController, player: Player?, message: string) -> (),
	spawnItemsAtPosition: (self: GameController, items: { any }, position: Vector3) -> (),
	spawnItemsAtPositionAndGoToPlayerBackpack: (self: GameController, items: { any }, position: Vector3, player: Player?) -> (),
	spawnItemsInBackpack: (self: GameController, items: { any }) -> (),
	tryAcceptTrade: (self: GameController, player: Player, partnerPlayerName: any) -> (),
	tryBeginDragonEatingCrop: (self: GameController, dragon: any, crop: any) -> (),
	tryBeginDragonOpeningCrystal: (self: GameController, dragon: any, crystal: any) -> (),
	tryBeginRideDragon: (self: GameController, player: Player, itemId: any, playerRelativeToDragonCFrame: any) -> (),
	tryBuyItemName: (self: GameController, player: Player, itemName: any) -> (),
	tryBuyMaxItemName: (self: GameController, player: Player, itemName: any) -> (),
	tryBuyVanityArea: (self: GameController, player: Player, vanityArea: any) -> (),
	tryCancelTrade: (self: GameController, player: Player, partnerPlayerName: any) -> (),
	tryChargeUpRidingDragon: (self: GameController, player: Player) -> (),
	tryCheckGroup: (self: GameController, player: Player) -> (),
	tryClaimCrystal: (self: GameController, player: Player, crystalItemId: any) -> (),
	tryClaimIndexReward: (self: GameController, player: Player, category: any, scope: any, chainKey: any, tierIndex: any) -> (),
	tryClaimLuckBillboard: (self: GameController, player: Player) -> (),
	tryClaimWelcomeBackGift: (self: GameController, player: Player) -> (),
	tryConfirmTrade: (self: GameController, player: Player, partnerPlayerName: any) -> (),
	tryCustomerTool: (self: GameController, player: Player, command: any, ...any) -> (),
	tryDeliverInstantOpenCrystal: (self: GameController, player: Player, durationSec: number) -> boolean,
	tryDeliverPurchasedItemToPlayer: (self: GameController, player: Player, itemName: string, count: number) -> boolean,
	tryDevTool: (self: GameController, player: Player, command: any, ...any) -> (),
	tryDisconnectPlayerByUserId: (self: GameController, userId: number, message: string) -> boolean,
	tryEatWhileRiding: (self: GameController, player: Player, cropItemId: any) -> (),
	tryEndRideDragon: (self: GameController, player: Player, itemId: any) -> (),
	tryEquipAbility: (self: GameController, player: Player, ability: any) -> (),
	tryEquipDragon: (self: GameController, player: Player, itemId: any, stableSlotIndex: any) -> (),
	tryEquipVanityComponent: (self: GameController, player: Player, vanityPlacement: any, vanityComponentName: any) -> (),
	tryGrantPlayerRobuxProductId: (self: GameController, player: Player, productId: number) -> boolean,
	tryLoadPreProfileSaveData: (self: GameController, player: Player) -> any,
	tryLockTradeOffer: (self: GameController, player: Player, partnerPlayerName: any, playerOffer: any) -> (),
	tryLogAnalyticsEvent: (self: GameController, player: Player, eventName: any, properties: any) -> (),
	tryMarkInstantOpenCrystal: (self: GameController, player: Player, crystalItemId: any) -> (),
	tryMergeItemsWithHeldItem: (self: GameController, player: Player, heldItemId: any, itemIds: any, isMergeAll: any) -> (),
	tryMergeItemsWithRidingItem: (self: GameController, player: Player, ridingItemId: any, itemIds: any, isMergeAll: any) -> (),
	tryMineWhileRiding: (self: GameController, player: Player, nodeObjectId: any) -> (),
	tryOpenChest: (self: GameController, player: Player, objectId: number, heldItemId: any) -> (),
	tryOpenCrate: (self: GameController, player: Player, crateItemId: any) -> (),
	tryOpenPack: (self: GameController, player: Player, packItemId: any) -> (),
	tryPickupItem: (self: GameController, player: Player, itemId: any) -> (),
	tryPlaceLuckBillboardForPlayer: (self: GameController, player: Player) -> (),
	tryPutAwayRidingDragon: (self: GameController, player: Player) -> (),
	tryRedeemFirstSessionOffer: (self: GameController, player: Player) -> (),
	tryRefreshIndexData: (self: GameController, player: Player) -> (),
	tryRemoveTradeOffer: (self: GameController, player: Player, partnerPlayerName: any) -> (),
	tryRequestBeginTrade: (self: GameController, player: Player, partnerPlayerName: any) -> (),
	tryRespondBeginTrade: (self: GameController, player: Player, partnerPlayerName: any, doesAccept: any) -> (),
	trySetBackpackIndex: (self: GameController, player: Player, itemId: any, index: number?) -> (),
	trySetFtueStep: (self: GameController, player: Player, stepName: any) -> (),
	trySetOption: (self: GameController, player: Player, playerOptionKey: any, value: any) -> (),
	trySetRidingItemCFrame: (self: GameController, player: Player, itemId: any, time: any, cframe: any, playerRelativeToDragonCFrame: any) -> (),
	tryShootFireballAtCritter: (self: GameController, player: Player, critterObjectId: any) -> (),
	tryShootFireballAtCrop: (self: GameController, player: Player, cropItemId: any) -> (),
	tryStartProfileSession: (self: GameController, userId: number, options: any) -> any,
	trySubmitCode: (self: GameController, player: Player, rawCode: any) -> (),
	trySummonDragonToEat: (self: GameController, player: Player, cropItemId: any) -> (),
	trySummonDragonToMine: (self: GameController, player: Player, nodeObjectId: any) -> (),
	trySummonDragonToOpen: (self: GameController, player: Player, crystalItemId: any) -> (),
	tryTriggerContextualFtue: (self: GameController, player: Player, hintId: any) -> (),
	tryUnequipAbility: (self: GameController, player: Player, ability: any) -> (),
	tryUnequipDragon: (self: GameController, player: Player, stableSlotIndex: any) -> (),
	tryUnequipVanityPlacement: (self: GameController, player: Player, vanityPlacement: any) -> (),
	tryUnlockVanityComponent: (self: GameController, player: Player, vanityPlacement: any, vanityComponentName: any) -> (),
}

export type ItemManager = {
	applyMixinsToClonedItem: (self: ItemManager, item: Item) -> (),
	applyMixinsToItem: (self: ItemManager, item: Item) -> (),
	checkItemsFallingTooLow: (self: ItemManager) -> (),
	cloneItem: (self: ItemManager, item: Item) -> Item?,
	createItem: (self: ItemManager, itemName: string, userId: any) -> Item?,
	createItemRaw: (self: ItemManager, itemId: number, itemData: any, userId: any) -> Item?,
	destroyItem: (self: ItemManager, item: Item) -> boolean,
	getAllDragons: (self: ItemManager) -> { ShadowDragon },
	getAllGems: (self: ItemManager) -> { Gem },
	getAvailableDragonsToEatForPlayer: (self: ItemManager, player: Player) -> { ShadowDragon },
	getAvailableDragonsToMineForPlayer: (self: ItemManager, player: Player) -> { ShadowDragon },
	getAvailableDragonsToOpenForPlayer: (self: ItemManager, player: Player) -> { ShadowDragon },
	getCropsDragonCanEat: (self: ItemManager, dragon: ShadowDragon) -> { Crop },
	getCropsGettingEaten: (self: ItemManager) -> { Crop },
	getCropsOnGround: (self: ItemManager) -> { Crop },
	getCropsOnGroundForUserId: (self: ItemManager, userId: any) -> { Crop },
	getDragonsEatingCrop: (self: ItemManager, crop: Crop) -> { ShadowDragon },
	getDragonsMovingToEatCrop: (self: ItemManager, crop: Crop) -> { ShadowDragon },
	getDragonsMovingToOpenCrystal: (self: ItemManager, crystal: Crystal) -> { ShadowDragon },
	getDragonsOnGround: (self: ItemManager) -> { ShadowDragon },
	getDragonsOnGroundForUserId: (self: ItemManager, userId: any) -> { ShadowDragon },
	getGrowingCrops: (self: ItemManager) -> { Crop },
	getItemById: (self: ItemManager, itemId: number?) -> Item?,
	getItemCountByUserId: (self: ItemManager, userId: any) -> number,
	getItemCountByUserIdAndName: (self: ItemManager, userId: any, itemName: string) -> number,
	getItemsNotOnGroundByUserId: (self: ItemManager, userId: any) -> { Item },
	getItemsOnGroundByUserId: (self: ItemManager, userId: any) -> { Item },
	getNextObjectId: (self: ItemManager) -> number,
	getOpeningCrystalsForUserId: (self: ItemManager, userId: any) -> { Crystal },
	getRidableDragonsForPlayer: (self: ItemManager, player: Player) -> { ShadowDragon },
	getSaveDataForPlayer: (self: ItemManager, player: Player) -> any,
	getUseBillboards: (self: ItemManager) -> boolean,
	isMutationCapableType: (self: ItemManager, itemType: string) -> boolean,
	loadDataForPlayer: (self: ItemManager, player: Player, saveData: any, offlineElapsedSec: number?) -> (),
	loadItem: (self: ItemManager, itemId: number, itemData: any, player: any, itemSaveData: any, itemIdMap: any) -> (),
	notifyRemovePlayer: (self: ItemManager, player: Player) -> (),
	removeAllItemsForPlayer: (self: ItemManager, player: Player) -> (),
	setUseBillboards: (self: ItemManager, doUseBillboards: any) -> (),
}

export type PlotsManager = {
	addAllChildrenAndMapCFramesForPlotIndex: (self: PlotsManager, plotIndex: number, root: any, holder: Instance) -> (),
	calculateTreeBounds: (self: PlotsManager, root: any) -> any,
	createItemOnPlot: (self: PlotsManager, index: number, name: any, plotPosition: Vector3, userId: number) -> (),
	equipVanityComponentForPlayerAtPlacement: (self: PlotsManager, player: Player, vanityPlacement: number, vanityComponentName: string) -> (),
	getAllExpansionInnerNames: (self: PlotsManager) -> { string },
	getAllExpansionOuterNames: (self: PlotsManager) -> { string },
	getAllFenceNames: (self: PlotsManager) -> { string },
	getAllMainPlotInnerNames: (self: PlotsManager) -> { string },
	getAllMainPlotOuterNames: (self: PlotsManager) -> { string },
	getAllVanityComponentNames: (self: PlotsManager) -> { string },
	getCategoryVanityComponentNames: (self: PlotsManager, vanityComponentName: string) -> { string },
	getClosestPlotIndexByPosition: (self: PlotsManager, position: Vector3) -> any,
	getEndCapCFrame: (self: PlotsManager, endCapIndex: number) -> CFrame,
	getGroundPositionFromPlotPosition: (self: PlotsManager, plotPosition: Vector3, index: number) -> Vector3,
	getNumEndCaps: (self: PlotsManager) -> number,
	getNumPlots: (self: PlotsManager) -> number,
	getPlotCFrameForUserId: (self: PlotsManager, userId: number) -> CFrame?,
	getPlotCFrameFromWorldCFrameForUserId: (self: PlotsManager, cframe: CFrame, userId: number) -> CFrame,
	getPlotIndexByUserId: (self: PlotsManager, userId: number) -> number?,
	getPlotItemRecoveryPositionByUserId: (self: PlotsManager, userId: number) -> Vector3?,
	getPlotPositionFromWorldPositionForUserId: (self: PlotsManager, position: Vector3, userId: number) -> Vector3,
	getRandomLocationInMainPlot: (self: PlotsManager, plotIndex: number) -> Vector3,
	getRandomLocationInMainPlotByUserId: (self: PlotsManager, userId: number) -> Vector3?,
	getVanityComponentDataByName: (self: PlotsManager, vanityComponentName: string) -> any,
	getVanityComponentNameForBlueprintName: (self: PlotsManager, blueprintItemName: string) -> string?,
	getWorldCFrameFromPlotCFrameForUserId: (self: PlotsManager, cframe: CFrame, userId: number) -> CFrame?,
	getWorldPositionFromPlotPositionForUserId: (self: PlotsManager, position: Vector3, userId: number) -> Vector3?,
	init: (self: PlotsManager) -> (),
	initVanityData: (self: PlotsManager) -> (),
	isPlotIndexOccupied: (self: PlotsManager, plotIndex: number) -> boolean,
	isPositionInExpansionXZ: (self: PlotsManager, position: Vector3, vanityArea: number, plotIndex: number) -> boolean,
	isPositionInExpansionXZByUserId: (self: PlotsManager, position: Vector3, vanityArea: number, userId: number) -> boolean,
	isPositionInMainPlotXZ: (self: PlotsManager, position: Vector3, plotIndex: number) -> boolean,
	isPositionInMainPlotXZByUserId: (self: PlotsManager, position: Vector3, userId: number) -> boolean,
	notifyAddUserId: (self: PlotsManager, userId: number) -> number?,
	notifyRemovePlayer: (self: PlotsManager, player: Player) -> (),
	removeAllChildrenForPlotIndex: (self: PlotsManager, plotIndex: number, holder: Instance) -> (),
	removeAllVanity: (self: PlotsManager, plotIndex: number) -> (),
	removeVanityName: (self: PlotsManager, plotIndex: number, name: any) -> (),
	replacePlotModel: (self: PlotsManager, plotIndex: number, name: any, path: string) -> (),
	replaceVanityInstance: (self: PlotsManager, plotIndex: number, name: any, path: string) -> (),
	restoreExpansionInner: (self: PlotsManager, plotIndex: number, vanityPlacement: number) -> (),
	restoreExpansionOuter: (self: PlotsManager, plotIndex: number, vanityPlacement: number) -> (),
	restoreInnerPlot: (self: PlotsManager, plotIndex: number) -> (),
	restoreOuterPlot: (self: PlotsManager, plotIndex: number) -> (),
	setupPlotIndexForJoiningPlayer: (self: PlotsManager, plotIndex: number) -> (),
	translatePositionEndCapToWorld: (self: PlotsManager, position: Vector3, index: number) -> Vector3,
	translatePositionPlotToWorld: (self: PlotsManager, position: Vector3, index: number) -> Vector3,
	translatePositionWorldToPlot: (self: PlotsManager, position: Vector3, index: number) -> Vector3,
	unequipVanityPlacementForPlayer: (self: PlotsManager, player: Player, vanityPlacement: number) -> (),
	validateVanityComponentName: (self: PlotsManager, vanityComponentName: string) -> boolean,
	validateVanityPlacement: (self: PlotsManager, vanityPlacement: number) -> boolean,
}

export type PickupMixin = {
	canPickupItem: (self: PickupMixin, player: Player, itemId: number) -> (),
	notifyItemCannotBePickedUp: (self: PickupMixin, item: any) -> (),
	notifyItemCloned: (self: PickupMixin, item: any) -> (),
	notifyItemCreated: (self: PickupMixin, item: any) -> (),
	notifyPickupItem: (self: PickupMixin, player: Player, itemId: number) -> (),
}

export type RideMixin = {
	canRideItem: (self: RideMixin, player: Player, itemId: number) -> boolean,
	isPlayerRiding: (self: RideMixin, player: Player) -> boolean,
	notifyItemCloned: (self: RideMixin, item: any) -> (),
	notifyItemCreated: (self: RideMixin, item: any) -> (),
	notifyPlayerBeginRideDragon: (self: RideMixin, player: Player, itemId: number, playerRelativeToDragonCFrame: CFrame?) -> (),
	notifyPlayerEndRideDragon: (self: RideMixin, player: Player, itemId: number) -> (),
	stopPlayerRiding: (self: RideMixin, player: Player) -> (),
	tryGetRidingDragonForPlayer: (self: RideMixin, player: Player) -> ShadowDragon?,
}

export type FtueManager = {
	getDefaultFtueProgress: (self: FtueManager) -> any,
	getDisabledFtueProgress: (self: FtueManager) -> any,
	isInFtue: (self: FtueManager, ftueProgress: any) -> boolean,
	mapFtueProgressFromSaveData: (self: FtueManager, ftueProgress: any) -> any,
	notifyBuyItemForPlayer: (self: FtueManager, player: Player) -> (),
	notifyCoinsCountChangedForPlayer: (self: FtueManager, player: Player, value: number) -> (),
	notifyGemsCountChangedForPlayer: (self: FtueManager, player: Player, playerAttributesKey: string, value: number) -> (),
	notifyItemEquipped: (self: FtueManager, player: Player?, itemId: number) -> (),
	notifyItemPlacedOnGroundForPlayer: (self: FtueManager, player: Player?, itemId: number) -> (),
	notifyItemUnequipped: (self: FtueManager, player: Player?, itemId: number) -> (),
	notifyMergeForPlayer: (self: FtueManager, player: Player, mergeItem: any) -> (),
	notifyPickupItemForPlayer: (self: FtueManager, player: Player, itemId: number) -> (),
	notifySummonToEatForPlayer: (self: FtueManager, player: Player, dragon: any, crop: any) -> (),
	setupStep: (self: FtueManager, player: Player, stepName: string?) -> (),
	setupStepIfNeeded: (self: FtueManager, player: Player, stepName: string?) -> (),
	tryGetStepData: (self: FtueManager, player: Player) -> any,
	trySetComplete: (self: FtueManager, player: Player) -> boolean,
	trySetStepName: (self: FtueManager, player: Player, stepName: string?) -> (),
}

export type ContextualFtueManager = {
	tryTrigger: (self: ContextualFtueManager, player: Player?, hintId: string) -> boolean,
}

export type IslandManager = {
	beginFadeOutPendingIslandsBatch: (self: IslandManager, batchSize: number, fadeDurationSec: number) -> (),
	configureIslandAsCritter: (self: IslandManager, islandData: any, objectName: string, position: Vector3) -> (),
	createChestsOnIsland: (self: IslandManager, islandData: any, chestTypeLootName: string?, random: Random) -> (),
	createFixedIslands: (self: IslandManager, islandName: string) -> (),
	createIslandDataFromIsland: (self: IslandManager, island: any) -> any,
	createNodesOnIsland: (self: IslandManager, islandData: any, nodeTypeLootName: string?, random: Random) -> (),
	createPendingIslandsBatch: (self: IslandManager, batchSize: number, fadeDurationSec: number) -> (),
	createPollTimer: (self: IslandManager) -> (),
	destroyPendingIslandsBatch: (self: IslandManager, batchSize: number) -> (),
	getChestByObjectId: (self: IslandManager, objectId: number) -> any,
	getClosestNode: (self: IslandManager, position: Vector3) -> any,
	getCritterByObjectId: (self: IslandManager, objectId: number) -> any,
	getCurrentEra: (self: IslandManager) -> number,
	getNodeByObjectId: (self: IslandManager, objectId: number) -> any,
	init: (self: IslandManager) -> (),
	isChestObjectId: (self: IslandManager, objectId: number) -> boolean,
	isCritterObjectId: (self: IslandManager, objectId: number) -> boolean,
	isNodeObjectId: (self: IslandManager, objectId: number) -> boolean,
	markToDestroyIslands: (self: IslandManager) -> (),
	queueCreateIslandsParameters: (self: IslandManager) -> (),
	refillNodes: (self: IslandManager) -> (),
	restockFixedIslands: (self: IslandManager, islandName: string) -> (),
	restockIslands: (self: IslandManager) -> (),
	setTimerForNextEra: (self: IslandManager) -> (),
	tryCreateIsland: (self: IslandManager, lootTableName: string, random: Random, locationMap: any, mapPositionFunc: any) -> Model?,
	tryMineNode: (self: IslandManager, player: Player, objectId: number) -> (),
	updateIslands: (self: IslandManager) -> (),
}

export type MutationStoreManager = {
	addClientDataToFolder: (self: MutationStoreManager, mutationStoreDataFolder: Instance) -> (),
	getSecondsUntilMidnightUTC: (self: MutationStoreManager) -> number,
	init: (self: MutationStoreManager) -> (),
	isDiscountProductId: (self: MutationStoreManager, robuxProductId: number) -> boolean,
	isProductId: (self: MutationStoreManager, robuxProductId: number) -> boolean,
	notifyAddPlayer: (self: MutationStoreManager, player: Player) -> (),
	rollAndCreateItem: (self: MutationStoreManager, player: Player?, lootTableName: string) -> (any, any),
	tryDeliverToPlayer: (self: MutationStoreManager, player: Player, robuxProductId: number) -> boolean,
	updateDiscountAttributeForPlayer: (self: MutationStoreManager, player: Player, availableTime: number) -> (),
}

export type VanityStoreManager = {
	addClientDataToFolder: (self: VanityStoreManager, vanityStoreDataFolder: Instance) -> (),
	getSecondsUntilMidnightUTC: (self: VanityStoreManager) -> number,
	init: (self: VanityStoreManager) -> (),
	isDiscountProductId: (self: VanityStoreManager, robuxProductId: number) -> boolean,
	isProductId: (self: VanityStoreManager, robuxProductId: number) -> boolean,
	notifyAddPlayer: (self: VanityStoreManager, player: Player) -> (),
	resetDiscountForPlayer: (self: VanityStoreManager, player: Player) -> (),
	rollAndCreateItem: (self: VanityStoreManager, player: Player?, lootTableName: string) -> any,
	tryDeliverToPlayer: (self: VanityStoreManager, player: Player, robuxProductId: number) -> boolean,
	updateDiscountAttributeForPlayer: (self: VanityStoreManager, player: Player, availableTime: number) -> (),
}

export type FirstSessionOfferManager = {
	canRedeem: (self: FirstSessionOfferManager, player: Player) -> boolean,
	getDefaultFirstSessionOfferState: (self: FirstSessionOfferManager) -> any,
	mapFirstSessionOfferStateFromSaveData: (self: FirstSessionOfferManager, player: Player, firstSessionOfferState: any) -> any,
	redeem: (self: FirstSessionOfferManager, player: Player) -> (),
	setRedeemable: (self: FirstSessionOfferManager, player: Player) -> (),
	startOffer: (self: FirstSessionOfferManager, player: Player) -> (),
}

export type PlayerData = {
	addCodeRedeemed: (self: PlayerData, code: any) -> (),
	addPrimaryElementXp: (self: PlayerData, primaryElement: any, xpDiff: any, position: Vector3) -> (),
	addToStat: (self: PlayerData, statName: any, count: number) -> (),
	backfillBlueprintIndexDiscoveryIfNeeded: (self: PlayerData) -> (),
	canEquipAbility: (self: PlayerData, ability: any) -> (),
	canMergeAll: (self: PlayerData) -> (),
	canUnequipAbility: (self: PlayerData, ability: any) -> (),
	checkPlayerFallingTooLow: (self: PlayerData) -> (),
	clearStableSlot: (self: PlayerData, stableSlotIndex: number) -> (),
	createLuckTimerIfNeeded: (self: PlayerData) -> (),
	createOrUpdateGameConfigInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	createOrUpdateOtherPlayerInGuiData: (self: PlayerData, splendidDataFolder: any, otherPlayer: any) -> (),
	destroy: (self: PlayerData) -> (),
	doAllowActivateItem: (self: PlayerData, item: any) -> boolean,
	doesPlayerHaveItemCount: (self: PlayerData, itemName: any, count: number) -> (),
	equipAbility: (self: PlayerData, ability: any) -> (),
	equipVanityComponentAtPlacement: (self: PlayerData, vanityPlacement: any, vanityComponentName: any) -> (),
	getAbilityStatuses: (self: PlayerData) -> (),
	getBuyStorePurchaseCountsForEra: (self: PlayerData, era: number) -> any,
	getCreationTime: (self: PlayerData) -> (),
	getDefaultContextualFtueState: (self: PlayerData) -> (),
	getDefaultVanityAreaStates: (self: PlayerData) -> (),
	getDefaultVanityComponentStates: (self: PlayerData) -> (),
	getDefaultVanityPlacements: (self: PlayerData) -> (),
	getDevToolSettings: (self: PlayerData) -> (),
	getFirstSessionOfferState: (self: PlayerData) -> (),
	getFriendLuckPercent: (self: PlayerData) -> (),
	getFtueProgress: (self: PlayerData) -> (),
	getGroupLuckPercent: (self: PlayerData) -> (),
	getIndexDiscoveredItems: (self: PlayerData) -> (),
	getIndexDiscoveredMutations: (self: PlayerData) -> (),
	getIndexMutationChancePercent: (self: PlayerData) -> (),
	getIsFriend: (self: PlayerData, userId: number) -> (),
	getIsInPlot: (self: PlayerData) -> (),
	getItemForPlayer: (self: PlayerData, itemName: any) -> Item?,
	getLatestRidingItemId: (self: PlayerData) -> (),
	getLuckPercent: (self: PlayerData) -> (),
	getLuckTimeRange: (self: PlayerData) -> (),
	getMergeData: (self: PlayerData) -> (),
	getNonDefaultVanityComponentStates: (self: PlayerData) -> (),
	getOption: (self: PlayerData, playerOptionKey: any) -> (),
	getOptions: (self: PlayerData) -> (),
	getPlayerCapacityUsed: (self: PlayerData) -> (),
	getPlayerMaxCapacity: (self: PlayerData) -> (),
	getPlayerVariable: (self: PlayerData, attributeName: any) -> (),
	getProfile: (self: PlayerData) -> (),
	getRidingItemId: (self: PlayerData) -> (),
	getRidingPlayerRelativeToDragonCFrame: (self: PlayerData) -> (),
	getSaveData: (self: PlayerData) -> any,
	getSessionCount: (self: PlayerData) -> (),
	getStableDragonInSlot: (self: PlayerData, stableSlotIndex: number) -> number?,
	getStableSlots: (self: PlayerData) -> any,
	getStarterOfferProgress: (self: PlayerData) -> (),
	getTimeLuckPercent: (self: PlayerData) -> (),
	getTotalDragonPower: (self: PlayerData) -> number,
	getTotalLevel: (self: PlayerData) -> (),
	getTotalPlaySec: (self: PlayerData) -> (),
	getTradeRequestCount: (self: PlayerData) -> (),
	getVanityAreaState: (self: PlayerData, vanityArea: any) -> (),
	grantIndexMutationChanceBuff: (self: PlayerData, amount: any) -> (),
	grantIndexStatBuff: (self: PlayerData, attributeName: any, amount: any) -> (),
	growAllCrops: (self: PlayerData) -> (),
	hasClaimedIndexReward: (self: PlayerData, tierId: any) -> (),
	hasCodeRedeemed: (self: PlayerData, code: any) -> (),
	hasDevToolAccess: (self: PlayerData) -> (),
	hasDiscoveredIndexItem: (self: PlayerData, itemName: any) -> (),
	hasDiscoveredIndexMutation: (self: PlayerData, mutationTier: any) -> (),
	hasProfile: (self: PlayerData) -> (),
	hasTriggeredContextualFtue: (self: PlayerData, id: any) -> (),
	incrementStat: (self: PlayerData, statName: any) -> (),
	incrementTradeRequestCount: (self: PlayerData) -> (),
	init: (self: PlayerData, profile: any) -> (),
	initCharacter: (self: PlayerData) -> (),
	initFriendUserIds: (self: PlayerData) -> (),
	initGroupData: (self: PlayerData) -> (),
	initLeaderboardData: (self: PlayerData) -> (),
	initLuck: (self: PlayerData) -> (),
	initPlayerGuiData: (self: PlayerData) -> (),
	isAtOrAboveCapacity: (self: PlayerData) -> (),
	isInFtue: (self: PlayerData) -> (),
	isLocationInPlotOrUnlockedExpansions: (self: PlayerData, location: Vector3) -> (),
	isVanityComponentLocked: (self: PlayerData, vanityComponentName: any) -> (),
	isVanityComponentUnlocked: (self: PlayerData, vanityComponentName: any) -> (),
	loadOptions: (self: PlayerData, options: any) -> (),
	loadSaveData: (self: PlayerData, saveData: any) -> (),
	markContextualFtueTriggered: (self: PlayerData, id: any) -> (),
	markIndexItemDiscovered: (self: PlayerData, itemName: any) -> (),
	markIndexMutationDiscovered: (self: PlayerData, mutationTier: any) -> (),
	markIndexRewardClaimed: (self: PlayerData, tierId: any) -> (),
	markInstantOpenCrystalItemId: (self: PlayerData, itemId: any) -> (),
	mergeVanityComponentStatesWithDefault: (self: PlayerData, vanityComponentStates: any) -> (),
	notifyItemAddedToWorkspace: (self: PlayerData, item: any) -> (),
	notifyItemReceived: (self: PlayerData, receivedItem: any) -> (),
	notifyItemRemovedFromWorkspace: (self: PlayerData, item: any) -> (),
	notifyOtherPlayerAdded: (self: PlayerData, otherPlayer: any) -> (),
	notifyOtherPlayerLevelChanged: (self: PlayerData, otherPlayer: any) -> (),
	notifyOtherPlayerReceiveTradeRequestsOptionChanged: (self: PlayerData, otherPlayer: any) -> (),
	notifyOtherPlayerRemoved: (self: PlayerData, otherPlayer: any) -> (),
	notifyReceivedMutation: (self: PlayerData) -> (),
	notifyRemovingPlayer: (self: PlayerData) -> (),
	notifyRidingItemCFrame: (self: PlayerData, cframe: CFrame, playerRelativeToDragonCFrame: any) -> (),
	notifyUpdateGameConfigSnapshot: (self: PlayerData) -> (),
	processOfflineTime: (self: PlayerData, durationSec: any) -> (),
	recomputeTotalDragonPower: (self: PlayerData) -> (),
	resetAbilityStatuses: (self: PlayerData) -> (),
	resetAllVanity: (self: PlayerData) -> (),
	resetCodesRedeemed: (self: PlayerData) -> (),
	resetContextualFtueState: (self: PlayerData) -> (),
	resetFirstSessionOfferState: (self: PlayerData) -> (),
	resetFtueProgress: (self: PlayerData) -> (),
	resetIndexData: (self: PlayerData) -> (),
	resetIndexMutationData: (self: PlayerData) -> (),
	resetIndexRewards: (self: PlayerData) -> (),
	resetLuckBillboard: (self: PlayerData) -> (),
	resetPromptGroupTime: (self: PlayerData) -> (),
	resetPurchasedSlotUnlocks: (self: PlayerData) -> (),
	resetStats: (self: PlayerData) -> (),
	resetTradeRequestCount: (self: PlayerData) -> (),
	restartFirstSessionOfferState: (self: PlayerData) -> (),
	restartFtueProgress: (self: PlayerData) -> (),
	setDefaultAbilityStatuses: (self: PlayerData) -> (),
	setDefaultStats: (self: PlayerData) -> (),
	setDevToolSetting: (self: PlayerData, name: any, value: any) -> (),
	setFirstSessionOfferState: (self: PlayerData, firstSessionOfferState: any) -> (),
	setFtueProgress: (self: PlayerData, ftueProgress: any) -> (),
	setIfSaveOnExit: (self: PlayerData, saveOnExit: any) -> (),
	setMergeData: (self: PlayerData, data: any) -> (),
	setPlayerVariable: (self: PlayerData, attributeName: any, value: any) -> (),
	setPurchasedSlotUnlock: (self: PlayerData, primaryElement: any) -> (),
	setRedeemableFirstSessionOfferState: (self: PlayerData) -> (),
	setRiding: (self: PlayerData, itemId: any, playerRelativeToDragonCFrame: any) -> (),
	setStableDragonInSlot: (self: PlayerData, stableSlotIndex: number, itemId: number) -> (),
	setStarterOfferProgress: (self: PlayerData, starterOfferProgress: any) -> (),
	setVanityState: (self: PlayerData, vanityState: any) -> (),
	shouldSaveOnExit: (self: PlayerData) -> (),
	syncDefaultExpansionVanityAreaIfNeeded: (self: PlayerData, vanityArea: any) -> (),
	syncVanityToWorld: (self: PlayerData) -> (),
	tryClaimWelcomeBackGift: (self: PlayerData) -> (),
	tryConsumeIndexRefreshCooldown: (self: PlayerData) -> (),
	tryDeliverDoubleWelcomeBackGift: (self: PlayerData) -> (),
	tryGetBestInstantOpenCrystalItemId: (self: PlayerData, durationSec: any) -> (),
	trySetOption: (self: PlayerData, playerOptionKey: any, value: any) -> (),
	unequipAbility: (self: PlayerData, ability: any) -> (),
	unequipVanityPlacement: (self: PlayerData, vanityPlacement: any) -> (),
	unlockPlayerVanityStateIfNeeded: (self: PlayerData) -> (),
	unlockPrimaryElementIfNeeded: (self: PlayerData, primaryElement: any) -> (),
	unlockProperAbilitiesForPrimaryElement: (self: PlayerData, primaryElement: any) -> (),
	unlockVanityArea: (self: PlayerData, vanityArea: any) -> (),
	unlockVanityComponent: (self: PlayerData, vanityComponentName: any) -> (),
	updateCapacityDisplay: (self: PlayerData) -> (),
	updateCommunityGroupData: (self: PlayerData) -> (),
	updateLeaderboardData: (self: PlayerData) -> (),
	updateLevelsVisuals: (self: PlayerData) -> (),
	updateLuckInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	updatePlayerFeaturesInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	updatePlayerIsInPlot: (self: PlayerData) -> (),
	updatePlayerVariables: (self: PlayerData) -> (),
	updatePlayerVariablesFromAbilities: (self: PlayerData) -> (),
	updatePlayerVariablesFromIndexRewards: (self: PlayerData) -> (),
	updatePlayerVariablesFromLevels: (self: PlayerData) -> (),
	updateVanityAreaDataInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	updateVanityDataInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	updateVanityPlacementDataInGuiData: (self: PlayerData, splendidDataFolder: any) -> (),
	updateVanityStateVisuals: (self: PlayerData) -> (),
}

return {}
