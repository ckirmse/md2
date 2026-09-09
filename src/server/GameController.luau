--!strict

local GameController = {}
GameController.__index = GameController

local configService = game:GetService("ConfigService")
local physicsService = game:GetService("PhysicsService")
local playersService = game:GetService("Players")

local ProfileStore = require("./Libs/ProfileStore")

local analyticsManager = require("./AnalyticsManager")
local buyStoreManager = require("./BuyStoreManager")
local Chest = require("./Chest")
local codeManager = require("./CodeManager")
local contextualFtueManager = require("./ContextualFtueManager")
local Critter = require("./Critter")
local Crop = require("./Crop")
local Crystal = require("./Crystal")
local customerTools = require("./CustomerTools")
local devTools = require("./DevTools")
local firstSessionOfferManager = require("./FirstSessionOfferManager")
local ftueManager = require("./FtueManager")
local gameDataVerifier = require("./GameDataVerifier")
local Gem = require("./Gem")
local Crate = require("./Crate")
local incomeManager = require("./IncomeManager")
local indexManager = require("./IndexManager")
local Item = require("./Item")
local objectDataStore = require("./ObjectDataStore")
local islandManager = require("./IslandManager")
local itemManager = require("./ItemManager")
local ItemMover = require("./ItemMover")
local lootTableManager = require("./LootTableManager")
local MItem = require("./MItem")
local mergeMixin = require("./MergeMixin")
local Node = require("./Node")
local NumberItem = require("./NumberItem")
local Pack = require("./Pack")
local pickupMixin = require("./PickupMixin")
local playerAttributesManager = require("./PlayerAttributesManager")
local PlayerData = require("./PlayerData")
local plotsManager = require("./PlotsManager")
local processReceipt = require("./ProcessReceipt")
local rideMixin = require("./RideMixin")
local sellMixin = require("./SellMixin")
local serverListener = require("./ServerListener")
local ShadowDragon = require("./ShadowDragon")
local stableManager = require("./StableManager")
local starterOfferManager = require("./StarterOfferManager")
local storageManager = require("./StorageManager")
local Timer = require("./Timer")
local tradeManager = require("./TradeManager")
local Types = require("./Types")
local Validate = require("./Validate")
local mutationStoreManager = require("./MutationStoreManager")
local vanityStoreManager = require("./VanityStoreManager")
local verticalMixin = require("./VerticalMixin")
local weatherManager = require("./WeatherManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents") :: Folder
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets") :: Folder
local Effects = GameAssets:WaitForChild("Effects") :: Folder
local CrystalHitAudioParent = Effects:WaitForChild("CrystalHitAudioParent") :: Part
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects") :: Folder
local CrystalHits = ParticleEffects:WaitForChild("CrystalHits") :: Part

local Abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local FtueSteps = require("@game/ReplicatedStorage/Shared/FtueSteps")
local GameConfigKeys = require("@game/ReplicatedStorage/Shared/GameConfigKeys")
local PivotToTargetTween = require("@game/ReplicatedStorage/Shared/PivotToTargetTween")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

-- most of this state is dynamic bookkeeping over untyped items/config, so the fields stay loose
type GameControllerFields = {
	playerDatas: { [Player]: any },
	playerStore: any,
	random: Random,
	gameConfig: any,
	gameConfigSnapshot: any,
	buyableItemNames: any,
	robuxBuyableItemNames: any,
	sellableItemNames: any,
	gemItemNames: any,
	remoteEventMetrics: any,
	pollTimer: any,
	pollCount: number,
	latestPollTime: number,
	waitExitCount: number,
}

export type GameController = typeof(setmetatable({} :: GameControllerFields, GameController))
local WelcomeBack = require("@game/ReplicatedStorage/Shared/WelcomeBack")

local crystalTimeData = require("@game/ServerScriptService/GameData/Control/CrystalTime")
local eatingTimeData = require("@game/ServerScriptService/GameData/Control/EatingTime")
local starterOfferData = require("@game/ServerScriptService/GameData/Control/StarterOffer")
local vanityAreasData = require("@game/ServerScriptService/GameData/Control/VanityAreas")

local defaultGameConfigSnapshot = {
	tradingEnabled = false,
	chestIslandsEnabled = false,
	indexEnabled = true,
}

local mixinData = {
	merge = mergeMixin,
	pickup = pickupMixin,
	ride = rideMixin,
	sell = sellMixin,
	vertical = verticalMixin,
}

local TRADE_OFFER_TABLE_SHAPE = {
	itemDescriptors = {
		type = "array",
		elementType = {
			itemId = "positiveInteger",
			count = "positiveInteger",
		},
	},
}

-- legacy: as of 2026-august-20, harvesting/merging grant coins directly instead of gems (see
-- GameController.grantCoinsForGemValue), so gem-selling is dormant. only trySellGems used this.
-- local SELL_GEMS_TABLE_SHAPE = {
-- 	primaryElement = {
-- 		type = "enum",
-- 		name = "PrimaryElements",
-- 	},
-- 	count = "positiveInteger",
-- }

--[[
	if not Validate.isTable(sellCountsStrs) then
		print("bad parameter to sell, not a table", player, sellCountsStrs)
		RemoteEvents.NotifySellStatus:FireClient(player, false)
		return
	end

	if next(sellCountsStrs) == nil then
		print("bad sell table empty", player)
		RemoteEvents.NotifySellStatus:FireClient(player, false)
		return
	end

	local sellCounts = {}
	for primaryElementStr, count in sellCountsStrs do
		local primaryElement = tonumber(primaryElementStr)
		if not Elements.validatePrimaryElement(primaryElement) then
			print("bad parameter to sell, not primary element", player, primaryElementStr)
			RemoteEvents.NotifySellStatus:FireClient(player, false)
			return
		end
		sellCounts[primaryElement] = count
		--print("sell counts", primaryElement, count)
	end

	for primaryElement, count in sellCounts do
		if (count % 1) ~= 0 then
			print("bad sell count non-integer", player, count)
			RemoteEvents.NotifySellStatus:FireClient(player, false)
			return
		end
		if count < 1 then
			print("bad sell count not positive", player, count)
			RemoteEvents.NotifySellStatus:FireClient(player, false)
			return
		end

		local availableCount = playerAttributesManager:get(player, Elements.getGemsKeyForPrimaryElement(primaryElement))
		if count > availableCount then
			print("bad sell count larger than available", player, count, availableCount)
			RemoteEvents.NotifySellStatus:FireClient(player, false)
			return
		end
	end
	]]

function GameController.getAllDragonNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "shadowDragon")
end

function GameController.getAllDragonEggNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "dragonEgg")
end

function GameController.getAllCropNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "crop")
end

function GameController.getAllCrystalNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "crystal")
end

function GameController.getAllPackNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "pack")
end

function GameController.getAllKeyNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "key")
end

function GameController.getAllBlueprintNames(self: GameController): { string }
	return objectDataStore:getAllObjectNamesByDataKeyValue("type", "blueprint")
end

function GameController.getBlueprintNamesForRarity(self: GameController, rarity: number): { string }
	local allBlueprintNames = self:getAllBlueprintNames()
	local blueprintNames = {}
	for _, itemName in allBlueprintNames do
		local objectData = objectDataStore:getObjectDataByName(itemName)
		if objectData.rarity ~= rarity then
			continue
		end

		table.insert(blueprintNames, itemName)
	end

	return blueprintNames
end

function GameController.getAllGemItemNames(self: GameController): { string }
	if not self.gemItemNames then
		self.gemItemNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", "gem")
	end

	return self.gemItemNames
end

function GameController.getAllBuyableItemNames(self: GameController): { string }
	if not self.buyableItemNames then
		self.buyableItemNames = objectDataStore:getAllObjectNamesWithDataKeyPath("buy")
	end

	return self.buyableItemNames
end

function GameController.getAllRobuxBuyableItemNames(self: GameController): { string }
	if not self.robuxBuyableItemNames then
		self.robuxBuyableItemNames = objectDataStore:getAllObjectNamesWithDataKeyPath("buy.robuxProductId")
	end

	return self.robuxBuyableItemNames
end

function GameController.getAllSellableItemNames(self: GameController): { string }
	if not self.sellableItemNames then
		self.sellableItemNames = objectDataStore:getAllObjectNamesWithDataKeyPath("mixins.sell")
	end

	return self.sellableItemNames
end

function GameController.getAllIslandNames(self: GameController): { string }
	local retval = {}

	local IslandsFolder = GameAssets:WaitForChild("Islands")
	for _, inst in IslandsFolder:GetChildren() do
		table.insert(retval, inst.Name)
	end

	return retval
end

function GameController.getLevelEquivalentItemNameForItem(self: GameController, item: any, level: number): string?
	local itemType = item:getType()
	if itemType == "shadowDragon" then
		itemType = "dragonEgg"
	end
	local objectNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", itemType)
	--print("possibilities", objectNames)

	local itemData = item:getItemData()
	local primaryElement = itemData.primaryElement
	local rarity = itemData.rarity

	for _, name in objectNames do
		local testItemData = objectDataStore:getObjectDataByName(name)
		--print("considering", testItemData)
		if testItemData.level ~= level then
			continue
		end
		if testItemData.primaryElement ~= primaryElement then
			continue
		end
		if testItemData.rarity ~= rarity then
			continue
		end

		--print("found it", testItemData)
		return testItemData.name
	end

	-- not a warning--some item types don't have level 0 (keys are one example as of 2026-may-11)

	return nil
end

function GameController.getLevel0ItemNameForItem(self: GameController, item: any): string?
	return self:getLevelEquivalentItemNameForItem(item, 0)
end

function GameController.getGemItemNameForPrimaryElement(self: GameController, primaryElement: number): string?
	local gemItemNames = self:getAllGemItemNames()
	for _, gemItemName in gemItemNames do
		local gemItemData = objectDataStore:getObjectDataByName(gemItemName)
		if gemItemData.primaryElement == primaryElement and gemItemData.denominations then
			return gemItemData.name
		end
	end

	warn("primary element", primaryElement, "cannot find gem primary item name")
	return nil
end

-- legacy/dormant (2026-august-20): harvesting/merging used to spawn physical Gem items that
-- players collected and sold; they now grant coins directly (see grantCoinsForGemValue below).
-- kept commented rather than deleted since Gem.luau/GemObjectType.luau and DevTools.addGemPile
-- still exist and can still spawn these via other paths.
-- function GameController.spawnGemsForPlayerFromItem(self: GameController, player: Player?, primaryElement: number, totalValue: number, item: any): ()
-- 	if not player then
-- 		return
-- 	end
-- 	local part = item:getPart()
-- 	local position = part.Position
-- 	local initialDistance = math.max(part.Size.X, part.Size.Z)
-- 	self:spawnGemsForPlayer(player, primaryElement, totalValue, position, initialDistance)
-- end
--
-- type GemItemInfo = {
-- 	itemName: string,
-- 	count: number,
-- 	nextFrac: number,
-- }
--
-- function GameController.spawnGemsForPlayer(self: GameController, player: Player, primaryElement: number, totalValue: number, position: Vector3, initialDistance: number): ()
-- 	local baseItemName = self:getGemItemNameForPrimaryElement(primaryElement)
-- 	if not baseItemName then
-- 		warn("no gem base item name found for primary element", primaryElement, "player", player)
-- 		return
-- 	end
--
-- 	local itemData = objectDataStore:getObjectDataByName(baseItemName)
--
-- 	local gemItemInfos: { GemItemInfo } = {}
--
-- 	local totalCount = 0
--
-- 	local remainingValue = totalValue
-- 	for _, denominationData in itemData.denominations do
-- 		--print("looking at", remainingValue, denominationData, denominationData.value)
-- 		local count: number = remainingValue // denominationData.value
-- 		if count == 0 then
-- 			continue
-- 		end
--
-- 		remainingValue -= count * denominationData.value
--
-- 		table.insert(gemItemInfos, { itemName = denominationData.itemName, count = count, nextFrac = 1 / count })
-- 		--print("gemItemInfo", gemItemInfos[#gemItemInfos])
-- 		totalCount += count
-- 	end
--
-- 	local angle = self.random:NextNumber(0, 360)
--
-- 	for i = 1, totalCount do
-- 		-- evenly spread out the gems of different denominations
-- 		-- cute algorithm based on https://stackoverflow.com/questions/3370554/evenly-distributing-all-items-in-a-list
-- 		local gemItemIndex = 1
-- 		local lowestFrac = gemItemInfos[gemItemIndex].nextFrac
-- 		for j = 1, #gemItemInfos do
-- 			if gemItemInfos[j].nextFrac < lowestFrac then
-- 				gemItemIndex = j
-- 				lowestFrac = gemItemInfos[j].nextFrac
-- 			end
-- 		end
-- 		gemItemInfos[gemItemIndex].nextFrac += 1 / gemItemInfos[gemItemIndex].count
-- 		local itemName = gemItemInfos[gemItemIndex].itemName
--
-- 		local groundHeight = utils.getGroundHeight(position.X, position.Z) or 0
--
-- 		--print("choosing gem", itemName, lowestFrac)
-- 		local directionUnit = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
-- 		-- don't let the gems get embedded in the spawning item
-- 		local directionOffset = directionUnit * initialDistance
--
-- 		local extraHeight
-- 		if position.Y - 8 > groundHeight then
-- 			-- spawning while a bit off the ground, so they're going to fall; give a bit of a boost
-- 			extraHeight = Vector3.new(0, self.random:NextNumber(5, 10), 0)
-- 		else
-- 			extraHeight = Vector3.new(0, self.random:NextNumber(0, 3), 0)
-- 		end
--
-- 		local gemPosition = position + directionOffset + extraHeight
-- 		local gem = itemManager:createItem(itemName, player.UserId)
-- 		if not gem then
-- 			continue
-- 		end
-- 		local gemObj = gem:getObj()
-- 		gemObj:PivotTo(CFrame.new(gemPosition))
--
-- 		gemObj.Parent = workspace
--
-- 		local gemPart = gem:getPart()
--
-- 		local impulse = directionUnit * (gemPart.AssemblyMass * 20)
-- 		impulse += Vector3.new(0, gemPart.AssemblyMass * (10 + self.random:NextNumber(0, 8)), 0)
-- 		gemPart:ApplyImpulse(impulse)
--
-- 		--print("spawn gems position offset", positionOffset, "impulse", impulse)
-- 		angle = (angle + 360 / totalCount) % 360
-- 	end
-- end

-- grants coins directly for a gem-equivalent value, in place of the legacy physical gem spawn
-- above; coinAmount = gemCount * (that element's current gem sell value in coins) * 10.
function GameController.grantCoinsForGemValue(self: GameController, player: Player?, primaryElement: number, gemCount: number): ()
	if not player or gemCount <= 0 then
		return
	end

	local gemItemName = self:getGemItemNameForPrimaryElement(primaryElement)
	if not gemItemName then
		return
	end

	local gemItemData = objectDataStore:getObjectDataByName(gemItemName)
	local coinAmount = math.ceil(gemCount * gemItemData.mixins.sell.coins * 10)
	if coinAmount <= 0 then
		return
	end

	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, coinAmount)
end

-- one-time-per-balance sweep of leftover banked gem currency into coins; safe to call on every
-- login since nothing grants gemsX attributes anymore, so a balance stays at 0 once converted
-- (2026-august-21)
function GameController.convertBankedGemsToCoins(self: GameController, player: Player): ()
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)
		local balance = playerAttributesManager:get(player, gemsKey)
		if balance <= 0 then
			continue
		end

		self:grantCoinsForGemValue(player, primaryElement, balance)
		playerAttributesManager:set(player, gemsKey, 0)
	end
end

function GameController.isPlayerRidingItemId(self: GameController, player: Player, itemId: any): boolean
	-- getPlayerData is defined further down the file, which the old solver cannot see from here
	return (self :: any):getPlayerData(player):getRidingItemId() == itemId
end

local freeFlyCornerA = Vector3.new(-168.4, 0, 460.4)
local freeFlyCornerB = Vector3.new(165.9, 0, 5.6)
function GameController.isLocationInFreeFlyZone(self: GameController, location: Vector3): boolean
	return utils.isLocationInRectangleXZ(location, freeFlyCornerA, freeFlyCornerB)
end

function GameController.getCountEatingCrop(self: GameController, crop: any): number
	local dragons = itemManager:getDragonsEatingCrop(crop)
	return #dragons
end

function GameController.endDragonsEatingCrop(self: GameController, crop: any): ()
	local dragons = itemManager:getDragonsEatingCrop(crop)
	for _, dragon in dragons do
		dragon:notifyEndEating()
	end
end

function GameController.notifyCropNoLongerAvailable(self: GameController, crop: any): ()
	local dragons = itemManager:getDragonsMovingToEatCrop(crop)
	for _, dragon in dragons do
		dragon:notifyEndMovingToEat()
	end
end

function GameController.notifyCrystalNoLongerAvailable(self: GameController, crystal: any): ()
	local dragons = itemManager:getDragonsMovingToOpenCrystal(crystal)
	for _, dragon in dragons do
		dragon:notifyEndMovingToOpen()
	end
end

function GameController.notifyCropFullyEaten(self: GameController, crop: any, dragon: any, xp: number, gemCount: number): ()
	local player = crop:getPlayer()
	analyticsManager:logEvent(player, analyticsManager.Events.Harvest, {
		objectName = crop:getItemName(),
		primaryElement = enums.getPublicName(enums.PrimaryElements, dragon:getItemData().primaryElement),
		dragonObjectName = dragon:getItemName(),
		gemCount = gemCount,
		xp = xp,
	})

	local playerData = self:getPlayerData(player)
	playerData:incrementStat("dragonsFed")

	local extraSpawnItems = {}

	local cropItemData = crop:getItemData()

	local cropLevel10ItemName = self:getLevelEquivalentItemNameForItem(crop, 10)
	local cropLevel10ItemData = objectDataStore:getObjectDataByName(cropLevel10ItemName :: string)

	-- support "harvest crop get seed" ability

	-- from gdd "(Harvested Plant Regen Timer / Lvl10 Plant Regen Timer) * (Harvested Plant capacityCost / Lvl10 Plant capacityCost) * Ability Value"
	local getSeedFrac = (cropItemData.food.growMin / cropLevel10ItemData.food.growMin)
		* (cropItemData.capacityCost / cropLevel10ItemData.capacityCost)
		* playerData:getPlayerVariable(Attributes.HARVEST_CROP_GET_SEED_FRAC)
	--print("seed frac is", getSeedFrac)
	if self.random:NextNumber(0, 1) < getSeedFrac then
		--print("trying to give an ability-triggered seed here")
		local seedItemName = self:getLevel0ItemNameForItem(crop)
		-- safety check; it should always succeed
		local seedItem = if seedItemName then itemManager:createItem(seedItemName, player.UserId) else nil
		if seedItem then
			table.insert(extraSpawnItems, seedItem)

			analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
				objectName = seedItem:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, seedItem:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, seedItem:getItemData().rarity),
				itemType = seedItem:getType(),
				acquisitionSource = "abilityHarvestCropGetSeed",
			})
		end
	end

	-- support "harvest crop get egg" ability

	-- from gdd "(Harvested Plant Regen Timer / Lvl10 Plant Regen Timer) * (Harvested Plant capacityCost / Lvl10 Plant capacityCost) * Ability Value"
	local getEggFrac = (cropItemData.food.growMin / cropLevel10ItemData.food.growMin)
		* (cropItemData.capacityCost / cropLevel10ItemData.capacityCost)
		* playerData:getPlayerVariable(Attributes.HARVEST_CROP_GET_EGG_FRAC)
	--print("egg frac is", getEggFrac)
	if self.random:NextNumber(0, 1) < getEggFrac then
		--print("trying to give an ability-triggered egg here")
		local eggItemName = self:getLevel0ItemNameForItem(dragon)
		-- safety check; it should always succeed
		local eggItem = if eggItemName then itemManager:createItem(eggItemName, player.UserId) else nil
		if eggItem then
			table.insert(extraSpawnItems, eggItem)

			analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
				objectName = eggItem:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, eggItem:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, eggItem:getItemData().rarity),
				itemType = eggItem:getType(),
				acquisitionSource = "abilityHarvestCropGetEgg",
			})
		end
	end

	if #extraSpawnItems > 0 then
		self:spawnItemsAtPosition(extraSpawnItems, crop:getObj():getPivot().Position)
	end
end

function GameController.tryBeginDragonEatingCrop(self: GameController, dragon: any, crop: any): ()
	--print("found some food, obj beginning to eat it", dragon:getItemName(), crop:getItemName())

	--print("obj", obj, "beginEating this food", food, "currently being eaten by others:", self:getCountEatingThis(food))

	dragon:notifyShouldEatCrop(crop)

	crop:notifyDragonStartEating(dragon)
end

function GameController.tryBeginDragonOpeningCrystal(self: GameController, dragon: any, crystal: any): ()
	--print("found crystal, obj beginning to open it", dragon:getItemName(), crystal:getItemName())

	dragon:notifyShouldOpenCrystal(crystal)

	crystal:notifyDragonStartOpening(dragon)
end

function GameController.notifyDragonStoppedEatingCrop(self: GameController, dragon: any, crop: any): ()
	if self:getCountEatingCrop(crop) == 0 then
		-- last dragon just stopped
		crop:endGettingEaten()
	end
end

function GameController.notifyDragonStoppedOpeningCrystal(self: GameController, dragon: any, crystal: any): ()
	crystal:notifyEndGettingOpened()
end

-- find "best" dragon from the player to come eat
function GameController.getBestDragonToEatForPlayer(self: GameController, player: Player, crop: any): any
	local rideDragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if rideDragon then
		return rideDragon
	end

	local heldDragon = self:getDragonBeingHeldByPlayer(player)
	if heldDragon then
		local bestDragon
		if heldDragon:getCount() > 1 then
			bestDragon = heldDragon:splitOffOne();
			-- and unequip remainder
			(player.Character :: any).Humanoid:UnequipTools()
		else
			local tool = heldDragon:findTool()
			-- get the part out of the tool so it's not destroyed along with the tool
			heldDragon:getPart().Parent = nil
			if tool then
				tool:Destroy()
			end
			heldDragon:setupChildPartsToObj()

			bestDragon = heldDragon
		end

		bestDragon:moveFromPlayerToWorkspace()

		return bestDragon
	end

	local possibleEatingDragons = itemManager:getAvailableDragonsToEatForPlayer(player)
	if #possibleEatingDragons == 0 then
		return nil
	end

	local cropPrimaryElement = crop:getItemData().primaryElement
	local bestDragon = possibleEatingDragons[1]
	for i = 1, #possibleEatingDragons do
		local dragon = possibleEatingDragons[i]
		local dragonItemData = dragon:getItemData()

		local bestDragonItemData = bestDragon:getItemData()

		-- top priority: matching crop affinity
		if
			dragonItemData.primaryElement == cropPrimaryElement
			and bestDragonItemData.primaryElement ~= cropPrimaryElement
		then
			bestDragon = dragon
			continue
		end
		if
			dragonItemData.primaryElement ~= cropPrimaryElement
			and bestDragonItemData.primaryElement == cropPrimaryElement
		then
			continue
		end

		-- next priority: highest level
		if dragonItemData.level > bestDragonItemData.level then
			bestDragon = dragon
			continue
		end
		if dragonItemData.level < bestDragonItemData.level then
			continue
		end

		-- next priority: highest mutation
		if dragon:getMutation() ~= bestDragon:getMutation() then
			if MItem.getBestMutation(dragon:getMutation(), bestDragon:getMutation()) == dragon:getMutation() then
				bestDragon = dragon
				continue
			end
			continue
		end

		-- last choice: closest
		local dragonDistance =
			utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - dragon:getObj():GetPivot().Position)
		local bestDragonDistance =
			utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - bestDragon:getObj():GetPivot().Position)
		if dragonDistance < bestDragonDistance then
			bestDragon = dragon
			continue
		end
	end

	return bestDragon
end

-- find "best" dragon from the player to come open
-- returns dragon/nil, reason
function GameController.getBestDragonToOpenForPlayer(self: GameController, player: Player, crystal: any): (any, any)
	local crystalItemData = crystal:getItemData()
	local crystalPrimaryElement = crystalItemData.primaryElement

	local rideDragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if rideDragon then
		local rideDragonItemData = rideDragon:getItemData()

		if rideDragonItemData.level >= crystalItemData.open.minDragonLevel then
			--print("riding dragon qualifies to open crystal, so using it")
			return rideDragon
		end
	end

	local possibleOpeningDragons = itemManager:getAvailableDragonsToOpenForPlayer(player)
	if #possibleOpeningDragons == 0 then
		return nil, "There are no idle dragons"
	end

	local bestDragon = nil
	for i = 1, #possibleOpeningDragons do
		local dragon = possibleOpeningDragons[i]
		local dragonItemData = dragon:getItemData()

		if dragonItemData.level < crystalItemData.open.minDragonLevel then
			continue
		end

		if not bestDragon then
			bestDragon = dragon
			continue
		end

		local bestDragonItemData = bestDragon:getItemData()

		-- top priority: matching crop affinity
		if
			dragonItemData.primaryElement == crystalPrimaryElement
			and bestDragonItemData.primaryElement ~= crystalPrimaryElement
		then
			bestDragon = dragon
			continue
		end
		if
			dragonItemData.primaryElement ~= crystalPrimaryElement
			and bestDragonItemData.primaryElement == crystalPrimaryElement
		then
			continue
		end

		-- next priority: highest level
		if dragonItemData.level > bestDragonItemData.level then
			bestDragon = dragon
			continue
		end
		if dragonItemData.level < bestDragonItemData.level then
			continue
		end

		-- last choice: closest
		local dragonDistance =
			utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - dragon:getObj():GetPivot().Position)
		local bestDragonDistance =
			utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - bestDragon:getObj():GetPivot().Position)
		if dragonDistance < bestDragonDistance then
			bestDragon = dragon
			continue
		end
	end

	if not bestDragon then
		return nil,
			string.format(
				"There are no idle dragons of level %i or higher available",
				crystalItemData.open.minDragonLevel
			)
	end

	return bestDragon
end

-- find "best" dragon from the player to come mine
function GameController.getBestDragonToMineForPlayer(self: GameController, player: Player, crystal: any): any
	-- only option we allow as of 2026-april-10 is the latest dragon you were riding
	-- there had been possible exploits to summon a different dragon with high stamina

	local playerData = self:getPlayerData(player)
	local itemId = playerData:getLatestRidingItemId()
	if not itemId then
		return nil
	end
	local dragon = itemManager:getItemById(itemId) :: Types.ShadowDragon?
	if not dragon then
		return nil
	end
	if not dragon:isAvailableToMine() then
		return nil
	end

	return dragon
	--[[
	local possibleMiningDragons = itemManager:getAvailableDragonsToMineForPlayer(player)
	if #possibleMiningDragons == 0 then
		return nil
	end

	local bestDragon = nil
	for i = 1, #possibleMiningDragons do
		local dragon = possibleMiningDragons[i]

		if not bestDragon then
			bestDragon = dragon
			continue
		end

		-- pick the closest
		local dragonDistance = utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - dragon:getObj():GetPivot().Position)
		local bestDragonDistance = utils.getMagnitudeXZ((player.Character :: any).HumanoidRootPart.Position - bestDragon:getObj():GetPivot().Position)
		if dragonDistance < bestDragonDistance then
			bestDragon = dragon
			continue
		end
	end

	return bestDragon
	]]
end

-- takes a standard itemCreationData object (map from itemName to count)
function GameController.createItemsFromItemCreationDataForPlayer(self: GameController, itemCreationData: { [string]: number }, player: Player?): { any }
	if not player then
		return {}
	end
	local items = {}

	for itemName, count in itemCreationData do
		for i = 1, count do
			local item = itemManager:createItem(itemName, player.UserId)
			table.insert(items, item)
		end
	end

	return items
end

-- the position is where the items should be centered; might not be player's position
-- items is an array of items that have been created but not put in workspace yet
function GameController.spawnItemsAtPosition(self: GameController, items: { any }, position: Vector3): ()
	if #items < 1 then
		return
	end

	for i, item in items do
		--[[
		if playerData:isAtOrAboveCapacity() then
			item:putInBackpack()
			backpackItemCount += item:getCount()
			continue
		end
		]]
		local obj = item:getObj()

		-- highlights don't always immediately work, so delay...
		-- xxx ideally should put this on client
		task.delay(0.05, function()
			item:createAndDecayHighlight()
		end)

		local orientation = CFrame.fromEulerAnglesXYZ(0, math.rad(self.random:NextNumber(0, 360)), 0)
		local cframe = orientation + position

		obj:PivotTo(cframe)

		-- when getting placed on ground, these will get separated out by item settling logic
		obj.Parent = workspace
	end
end

-- items is an array of items that have been created but not put in workspace yet
function GameController.spawnItemsInBackpack(self: GameController, items: { any }): ()
	if #items < 1 then
		return
	end
	local player = items[1]:getPlayer()
	local playerData = self:getPlayerData(player)
	if not playerData then
		return
	end

	local backpackItemCount = 0
	for i, item in items do
		item:putInBackpack()
		backpackItemCount += item:getCount()
	end

	if backpackItemCount >= 1 then
		self:sendSystemMessageToPlayer(player, string.format("%i items placed in your backpack", backpackItemCount))
	end
end

function GameController.spawnItemsAtPositionAndGoToPlayerBackpack(self: GameController, items: { any }, position: Vector3, player: Player?): ()
	if not player then
		return
	end
	-- put them at specified location to start
	for i, item in items do
		local obj = item:getObj()
		local part = item:getPart()

		local itemData = item:getItemData()
		if not itemData.mixins.pickup then
			warn("item cannot be sent to player backpack", item)
			itemManager:destroyItem(item)
			return
		end

		local cframe = CFrame.fromEulerAnglesXYZ(0, math.rad(self.random:NextNumber(0, 360)), 0) + position

		part.Anchored = true -- don't let anything move it except for us
		obj:PivotTo(cframe)

		obj.Parent = workspace
	end

	local UP_DURATION_SEC = 1.0
	local RADIUS = 10
	local HEIGHT = 6

	local TO_PLAYER_DURATION_SEC = 0.4

	-- animate them up and outward
	for i, item in items do
		local obj = item:getObj()
		local cframe = obj:GetPivot()
		local direction
		if #items > 1 then
			local angle = (i * 2 * math.pi / #items) * self.random:NextNumber(0.8, 1.2)
			direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		else
			direction = Vector3.zero
		end
		local upPosition = cframe.Position
			+ RADIUS * self.random:NextNumber(0.5, 1.5) * direction
			+ Vector3.new(0, HEIGHT * self.random:NextNumber(0.5, 1.5), 0)
		local upCFrame = cframe.Rotation + upPosition

		local upDurationSec = UP_DURATION_SEC * self.random:NextNumber(0.5, 1.5)
		local upTweenInfo = TweenInfo.new(upDurationSec, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
		local upTween = PivotToTween(obj, upTweenInfo, upCFrame)

		upTween.Completed:Connect(function()
			local toPlayerDurationSec = TO_PLAYER_DURATION_SEC * self.random:NextNumber(0.5, 1.5)
			local toPlayerTweenInfo =
				TweenInfo.new(toPlayerDurationSec, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
			local toPlayerTween = PivotToTargetTween(obj, toPlayerTweenInfo, (player.Character :: any).HumanoidRootPart)
			toPlayerTween.Completed:Connect(function()
				item:putInBackpack()

				-- would be nice to move this to client, but on which object? xxx
				-- player of course, and handle in clientPlayerManager

				local primaryElement = item:getItemData().primaryElement

				local playerPosition = (player.Character :: any).HumanoidRootPart.Position

				local crystalHits = CrystalHits:Clone()
				crystalHits.Anchored = true
				crystalHits.Position = playerPosition
				utils.setPropertyTreeClassName(
					crystalHits,
					"ParticleEmitter",
					"Color",
					ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement))
				)
				crystalHits.Parent = player.Character

				utils.safelyDisposeOfParticleParent(crystalHits, 0.5)

				local crystalHitAudioParent = CrystalHitAudioParent:Clone()
				crystalHitAudioParent.Position = playerPosition
				crystalHitAudioParent.Parent = workspace
				game:GetService("Debris"):AddItem(crystalHitAudioParent, 5) -- destroy after 5s

				local audioCrystalHit = crystalHitAudioParent:FindFirstChild("AudioCrystalHit") :: AudioPlayer?
				if audioCrystalHit then
					audioCrystalHit:Play()
				end
			end)
			toPlayerTween:Play()
		end)

		upTween:Play()
	end
end

-- returns tuple of steps, maxCountPerStep
function GameController.calculateEatingSteps(self: GameController, dragon: any, crop: any): (number, number)
	local cropItemData = crop:getItemData()
	local dragonItemData = dragon:getItemData()

	local totalSteps = 1
	local maxCountPerStep = 1

	local levelDiff = cropItemData.level - dragonItemData.level
	for _, eatingTimeEntry in eatingTimeData.eatingTime do
		if eatingTimeEntry.levelDiff ~= levelDiff then
			continue
		end

		totalSteps = eatingTimeEntry.steps
		maxCountPerStep = eatingTimeEntry.secPerStep
		break
	end

	return totalSteps, maxCountPerStep
end

function GameController.calculateXpForHarvest(self: GameController, dragon: any, crop: any): number
	local player = crop:getPlayer()
	local playerData = self:getPlayerData(player)
	local abilityFrac = playerData:getPlayerVariable(Attributes.HARVEST_CROP_MORE_GEMS_FRAC)
	local playerAbilityMultiplier = 1 + abilityFrac

	local cropItemData = crop:getItemData()
	local dragonItemData = dragon:getItemData()

	local dragonMutationMultiplier = 1 + MItem.getMutationBonus(dragon:getMutation())
	local cropMutationMultiplier = 1 + MItem.getMutationBonus(crop:getMutation())

	local modificationMultiplier = crop:calculateModificationMultiplier()

	local affinityMultiplier
	if cropItemData.primaryElement == dragonItemData.primaryElement then
		affinityMultiplier = 2
	else
		affinityMultiplier = 1
	end

	local dragonXpMultiplier = dragonItemData.eat.xpMultiplier

	local xp = math.ceil(
		cropItemData.food.xp
			* cropMutationMultiplier
			* dragonXpMultiplier
			* dragonMutationMultiplier
			* affinityMultiplier
			* modificationMultiplier
			* playerAbilityMultiplier
	)

	--print("harvest xp calculation: crop base", cropItemData.food.xp, "crop mutation multiplier", cropMutationMultiplier, "dragon multiplier", dragonXpMultiplier, "dragon mutation multiplier", dragonMutationMultiplier, "affinity multiplier", affinityMultiplier, "modificationMultiplier", modificationMultiplier, "playerAbilityMultiplier", playerAbilityMultiplier, "=", xp)

	return xp
end

function GameController.calculateGemsForHarvest(self: GameController, dragon: any, crop: any): number
	local player = crop:getPlayer()
	local playerData = self:getPlayerData(player)
	local abilityFrac = playerData:getPlayerVariable(Attributes.HARVEST_CROP_MORE_GEMS_FRAC)
	local playerAbilityMultiplier = 1 + abilityFrac

	local cropItemData = crop:getItemData()
	local dragonItemData = dragon:getItemData()

	local dragonMutationMultiplier = 1 + MItem.getMutationBonus(dragon:getMutation())
	local cropMutationMultiplier = 1 + MItem.getMutationBonus(crop:getMutation())

	local modificationMultiplier = crop:calculateModificationMultiplier()

	local affinityMultiplier
	if cropItemData.primaryElement == dragonItemData.primaryElement then
		affinityMultiplier = 2
	else
		affinityMultiplier = 1
	end

	local dragonGemMultiplier = dragonItemData.eat.gemMultiplier

	local gemCount = math.ceil(
		cropItemData.food.gems.count
			* dragonGemMultiplier
			* dragonMutationMultiplier
			* cropMutationMultiplier
			* affinityMultiplier
			* modificationMultiplier
			* playerAbilityMultiplier
	)

	--print("gem calculation: crop base", cropItemData.food.gems.count, "dragon multiplier", dragonGemMultiplier, "dragon mutation multiplier", dragonMutationMultiplier, "crop mutation multiplier", cropMutationMultiplier, "affinity multiplier", affinityMultiplier, "modificationMultiplier", modificationMultiplier, "playerAbilityMultiplier", playerAbilityMultiplier, "=", gemCount)

	return gemCount
end

-- part is something the xp display should draw near
function GameController.addPrimaryElementXpToPlayer(self: GameController, player: Player?, primaryElement: number, xpDiff: number, part: any): ()
	if not player then
		return
	end
	local position = part.Position + Vector3.new(0, part.Size.Y / 2 + 1, 0)

	local playerData = self:getPlayerData(player)

	playerData:addPrimaryElementXp(primaryElement, xpDiff, position)
end

function GameController.sendSystemMessageToPlayer(self: GameController, player: Player?, message: string): ()
	if not player then
		return
	end
	RemoteEvents.NotifySystemMessage:FireClient(player, message)
end

function GameController.sendSystemMessageToAllPlayers(self: GameController, message: string): ()
	for _, player in playersService:GetPlayers() do
		self:sendSystemMessageToPlayer(player, message)
	end
end

function GameController.getPlayerByName(self: GameController, playerName: any): Player?
	for _, player in playersService:GetPlayers() do
		if player.Name == playerName then
			return player
		end
	end
	return nil
end

function GameController.getDragonBeingHeldByPlayer(self: GameController, player: Player): any
	for _, tool in (player.Character :: Model):GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end

		local obj = tool:FindFirstChild("Handle")
		if not obj then
			continue
		end

		local itemId = obj:GetAttribute(Attributes.ITEM_ID) :: number
		local item = itemManager:getItemById(itemId)
		-- as of 2026-august-11 this compared item:getType().type, which is always nil for a
		-- string, so held dragons were never found; fixed to compare the type string itself
		if item and item:getType() == "shadowDragon" then
			return item :: Types.ShadowDragon
		end
	end

	return nil
end

function GameController.getClosestNodeToPlayer(self: GameController, player: Player): any
	local position = (player.Character :: any).HumanoidRootPart.Position
	return islandManager:getClosestNode(position)
end

function GameController.refillNodes(self: GameController): ()
	islandManager:refillNodes()
end

function GameController.restockIslands(self: GameController): ()
	islandManager:restockIslands()
end

function GameController.restockFixedIslands(self: GameController, islandName: string): ()
	islandManager:restockFixedIslands(islandName)
end

function GameController.tryDisconnectPlayerByUserId(self: GameController, userId: number, message: string): boolean
	for player, playerData in self.playerDatas do
		if player.UserId ~= userId then
			continue
		end

		player:Kick(message)
		return true
	end

	return false
end

function GameController.getPlayerData(self: GameController, player: Player?): any
	if not player then
		-- the player already left
		return nil
	end
	return self.playerDatas[player]
end

function GameController.getAllPlayerUserIds(self: GameController): { number }
	local userIds = {}
	for player, playerData in self.playerDatas do
		table.insert(userIds, player.UserId)
	end

	return userIds
end

-- purchased means acquired via coins or robux
function GameController.tryDeliverPurchasedItemToPlayer(self: GameController, player: Player, itemName: string, count: number): boolean
	local itemData = objectDataStore:getObjectDataByName(itemName)

	for i = 1, count do
		local item = itemManager:createItem(itemName, player.UserId)
		if not item then
			warn("failed to create purchased item", itemName)
			return false
		end

		if itemData.mixins.pickup then
			if not item:putInBackpack() then
				return false
			end
		elseif itemData.type == "shadowDragon" then
			local position = plotsManager:getPlotItemRecoveryPositionByUserId(player.UserId)
			if not position then
				-- no plot assigned; fail the delivery so the purchase refunds
				warn("no plot recovery position to deliver dragon", player, itemName)
				return false
			end
			--print("bought non-pickup dragon going to", position)
			item:getObj():PivotTo(CFrame.new(position))

			item:getObj().Parent = workspace
			local dragon = item :: Types.ShadowDragon
			dragon:notifyShouldMoveToIdle()
			self:sendSystemMessageToPlayer(player, "Your new dragon awaits you in your plot")

			-- contextual FTUE: explain flying the first time the player receives a level 4+ dragon
			if itemData.level and itemData.level >= 4 then
				contextualFtueManager:tryTrigger(player, "flyingUnlocked")
			end
		else
			warn("unknown buy situation whene non-dragon cannot be picked up", item)
			return false
		end
	end

	return true
end

function GameController.tryDeliverInstantOpenCrystal(self: GameController, player: Player, durationSec: number): boolean
	local playerData = self:getPlayerData(player)

	-- see if player has a specific one queued up or a fallback reasonable one
	local itemId = playerData:tryGetBestInstantOpenCrystalItemId(durationSec)

	if not itemId then
		-- nothing to open...
		warn("failed robux purchase of crystal speedup", player, durationSec)
		return false
	end

	--print("instant opening", itemId)

	local crystal = itemManager:getItemById(itemId) :: Types.Crystal?
	if not crystal then
		warn("instant open crystal item disappeared", player, itemId)
		return false
	end
	crystal:finishOpeningSuccessfully()
	return true
end

function GameController.tryGrantPlayerRobuxProductId(self: GameController, player: Player, productId: number): boolean
	local playerData = self:getPlayerData(player)
	if not playerData then
		warn("cannot grant robux because player not here", player, productId)
		return false
	end

	local itemNames = self:getAllRobuxBuyableItemNames()
	--print("robux buyable item names found", #itemNames, itemNames)
	for _, itemName in itemNames do
		local itemData = objectDataStore:getObjectDataByName(itemName)
		if itemData.buy.robuxProductId ~= productId then
			continue
		end

		local count = itemData.buy.robuxCount
		print("trying to deliver robux purchased item", player, itemName, count)

		-- in case a player does a robux purchase during ftue
		task.defer(function()
			ftueManager:notifyBuyItemForPlayer(player)
		end)

		task.defer(function()
			analyticsManager:logEvent(player, analyticsManager.Events.GainItem, {
				objectName = itemName,
				primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
				rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
				itemType = itemData.type,
				acquisitionSource = "buyRobux",
			})
		end)

		return self:tryDeliverPurchasedItemToPlayer(player, itemName, count)
	end

	-- look for instant-open crystals
	for _, instantOpenCrystalData in crystalTimeData.instantOpenCrystal do
		if instantOpenCrystalData.robuxProductId ~= productId then
			continue
		end

		return self:tryDeliverInstantOpenCrystal(player, instantOpenCrystalData.durationSec)
	end

	-- look for unlocking an ability slot early
	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		if Elements.getUnlockAbilitySlotRobuxProductIdForPrimaryElement(primaryElement) ~= productId then
			continue
		end

		playerData:setPurchasedSlotUnlock(primaryElement)
		return true
	end

	-- look for starter offer
	if starterOfferData.robuxProductId == productId then
		starterOfferManager:deliverToPlayer(player)
		return true
	end

	for _, vanityArea in enums.getAllValues(enums.VanityAreas) do
		if not vanityAreasData.unlockPurchase[vanityArea] then
			continue
		end

		if vanityAreasData.unlockPurchase[vanityArea].robuxProductId ~= productId then
			continue
		end

		--print("server knows player bought vanity area", player, vanityArea)
		playerData:unlockVanityArea(vanityArea)

		return true
	end

	if vanityStoreManager:isProductId(productId) then
		--print("vanity store purchase", productId)
		if not vanityStoreManager:tryDeliverToPlayer(player, productId) then
			return false
		end

		return true
	end

	if mutationStoreManager:isProductId(productId) then
		if not mutationStoreManager:tryDeliverToPlayer(player, productId) then
			return false
		end

		return true
	end

	if productId == WelcomeBack.DOUBLE_WELCOME_BACK_PRODUCT_ID then
		return playerData:tryDeliverDoubleWelcomeBackGift()
	end

	-- in the future we can have other robux purchasable things (such as "restock store")--this is where to handle those
	--

	warn("did not find product id to purchase", player, productId)

	return false
end

function GameController.notifyPlayerLevelChanged(self: GameController, player: Player): ()
	for otherPlayer, otherPlayerData in self.playerDatas do
		otherPlayerData:notifyOtherPlayerLevelChanged(player)
	end
end

function GameController.notifyPlayerReceiveTradeRequestsOptionChanged(self: GameController, player: Player): ()
	for otherPlayer, otherPlayerData in self.playerDatas do
		otherPlayerData:notifyOtherPlayerReceiveTradeRequestsOptionChanged(player)
	end
end

function GameController.tryLoadPreProfileSaveData(self: GameController, player: Player): any
	local slot = 0
	local successGame, saveData = storageManager:loadPlayerGame(player, slot)
	if not successGame then
		warn("unsuccessful loading player game from storage", player, slot)

		-- uh... this isn't good
		return nil
	end

	--print("loaded save data:", saveData)

	return saveData
end

function GameController.removePreProfileSaveData(self: GameController, player: Player, saveData: any): ()
	local slot = 0
	storageManager:backupPlayerGame(player, saveData, slot)
	storageManager:erasePlayerGame(player, slot)
end

function GameController.tryStartProfileSession(self: GameController, userId: number, options: any): any
	local key = storageManager:getProfileKeyForUserId(userId)

	local profile = self.playerStore:StartSessionAsync(key, options)

	return profile
end

function GameController.processPlayerAdd(self: GameController, player: Player): ()
	--print("server: player added", player.Name)

	if self.playerDatas[player] then
		warn("player added that we already have", player)
		return
	end

	local playerData = PlayerData.new(player)
	self.playerDatas[player] = playerData

	-- default to not save bad data unless initialization succeeds
	playerData:setIfSaveOnExit(false)

	local migratedSaveData = self:tryLoadPreProfileSaveData(player)

	local profile = self:tryStartProfileSession(player.UserId, {
		Cancel = function()
			return player.Parent ~= playersService
		end,
	})

	if profile == nil then
		-- this should only happen when the server is shutting down or if person joined game on 2 devices at essentially the same time
		player:Kick("Profile load failed; please rejoin")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR compliance

	profile.OnSessionEnd:Connect(function()
		if not self:getPlayerData(player) then
			-- no need to kick if already out; this happens in normal player exiting
			return
		end
		player:Kick("Profile session end; please rejoin")
	end)

	profile.OnSave:Connect(function()
		--print("about to save", player.Name)
		if playerData:shouldSaveOnExit() then
			profile.Data = {
				standardSave = playerData:getSaveData(),
			}
		end
	end)

	if player.Parent ~= game:GetService("Players") then
		-- player left before we got here
		profile:EndSession()
		return
	end

	playerData:init(profile)

	local successOptions, options = storageManager:loadPlayerOptions(player)
	if not successOptions then
		print("unsuccessful loading player options from storage", player)

		-- not a huge deal
		options = {}
	end
	if not options then
		-- new player gets here as well as errors
		options = {}
	end
	if typeof(options) ~= "table" then
		options = {}
	end

	playerData:loadOptions(options)

	print("server: player join", player.Name)

	plotsManager:notifyAddUserId(player.UserId)

	-- character loading was disabled by default, so we can force it to happen right here
	player:LoadCharacterAsync()

	playerData:initCharacter()

	local saveData
	if migratedSaveData then
		saveData = migratedSaveData
	else
		saveData = profile.Data.standardSave
	end
	playerData:loadSaveData(saveData)
	self:convertBankedGemsToCoins(player)

	if playerData:getSessionCount() == 1 then
		local creationTime = playerData:getCreationTime()
		local joinDateStr = DateTime.fromUnixTimestamp(creationTime):FormatUniversalTime("YYYY-MM-DD", "en-us")
		analyticsManager:logEvent(player, analyticsManager.Events.FirstPlay, {
			joinDate = joinDateStr,
		})
	end

	-- everything loaded/initialized for the player, so if they leave then we want to save their data
	playerData:setIfSaveOnExit(true)

	if migratedSaveData then
		profile:Save()
		self:removePreProfileSaveData(player, migratedSaveData)

		print("migrated save data for", player)
		analyticsManager:logEvent(player, analyticsManager.Events.MigratePreProfileSaveData, {})
	end

	-- build up and send blob of data for client initialization

	local devToolSettings = nil
	if playerData:hasDevToolAccess() then
		devToolSettings = {
			doUseBillboards = itemManager:getUseBillboards(),
		}
	end

	local ftueProgress = playerData:getFtueProgress()
	local initData = {
		plotIndex = plotsManager:getPlotIndexByUserId(player.UserId),
		plotCFrame = plotsManager:getPlotCFrameForUserId(player.UserId),
		buyStoreData = buyStoreManager:getBuyStoreDataForPlayer(player),
		clientWeatherDatas = weatherManager:getClientWeatherDatas(),
		devToolSettings = devToolSettings,
		options = playerData:getOptions(),
		abilityStatuses = playerData:getAbilityStatuses(),
		starterOfferData = starterOfferManager:updateAndGetStarterOfferDataForPlayer(player),
		ftueProgress = ftueProgress,
		firstSessionOfferState = playerData:getFirstSessionOfferState(),
		showLuckBillboard = not playerData.hasClaimedGroupLuck and not ftueProgress.isEnabled,
	}
	RemoteEvents.NotifyInit:FireClient(player, initData)

	mutationStoreManager:notifyAddPlayer(player)
	vanityStoreManager:notifyAddPlayer(player)
	incomeManager:notifyAddPlayer(player)

	playerData:initFriendUserIds()

	for otherPlayer, otherPlayerData in self.playerDatas do
		otherPlayerData:notifyOtherPlayerAdded(player)
	end
end

function GameController.processPlayerRemove(self: GameController, player: Player): ()
	-- we don't do anything async until saving the data at the end so other players see this one disappear quickly

	if not self.playerDatas[player] then
		warn("try to remove player that we do not have have", player)
		return
	end

	local playerData = self.playerDatas[player]

	playerData:notifyRemovingPlayer()

	local options = playerData:getOptions()
	local profile = playerData:getProfile()

	-- remove it from the table to make sure we never try to get save data again while destroying
	self.playerDatas[player] = nil

	self.waitExitCount += 1

	if profile then
		profile:EndSession()
	else
		print("player exiting without a profile", player)
	end

	tradeManager:notifyRemovePlayer(player)
	itemManager:notifyRemovePlayer(player)
	plotsManager:notifyRemovePlayer(player)
	incomeManager:notifyRemovePlayer(player)

	for otherPlayer, otherPlayerData in self.playerDatas do
		otherPlayerData:notifyOtherPlayerRemoved(player)
	end

	-- don't do anything async above this
	storageManager:savePlayerOptions(player, options)

	self.waitExitCount -= 1

	playerData:destroy()
end

function GameController.listenToPlayerEvents(self: GameController): ()
	playersService.PlayerAdded:Connect(function(player)
		self:processPlayerAdd(player)
	end)

	playersService.PlayerRemoving:Connect(function(player)
		self:processPlayerRemove(player)
	end)

	for _, player in playersService:GetPlayers() do
		self:processPlayerAdd(player)
	end
end

function GameController.getNextObjectId(self: GameController): number
	return itemManager:getNextObjectId()
end

--[[
	Each event listener, right here is responsible for validating the input data being legitimate item ids and owned by the right player
	Any deeper checks belong elsewhere
]]

function GameController.tryDevTool(self: GameController, player: Player, command: any, ...): ()
	--print("received dev tool", command, ...)

	local playerData = self:getPlayerData(player)

	if not playerData:hasDevToolAccess() then
		print("player attempted to send a dev tool command", player, player.UserId)
		return
	end

	if typeof(command) ~= "string" then
		warn("invalid command is not a string", command)
		return
	end
	if string.sub(command, 1, 1) == "_" then
		warn("invalid dev tool command starts with underscore", command)
		return
	end
	if command == "init" or command == "initClass" then
		warn("invalid dev tool command", command)
		return
	end

	local func = (devTools :: any)[command] :: (devTools.DevTools, Player, ...any) -> ()
	if not func or typeof(func) ~= "function" then
		warn("unknown dev tool command", command)
		return
	end

	print("executing dev tool", command, ...)
	func(devTools, player, ...)
end

function GameController.tryCustomerTool(self: GameController, player: Player, command: any, ...): ()
	--print("got try customer tool for player", player, command, ...)

	local playerData = self:getPlayerData(player)

	if not playerData:hasDevToolAccess() then
		print("player attempted to send a customer tool command", player, player.UserId)
		return
	end

	if typeof(command) ~= "string" then
		warn("invalid command is not a string", command)
		return
	end
	if string.sub(command, 1, 1) == "_" then
		warn("invalid customer tool command starts with underscore", command)
		return
	end
	if command == "init" or command == "initClass" then
		warn("invalid customer tool command", command)
		return
	end

	local func = (customerTools :: any)[command] :: (customerTools.CustomerTools, Player, ...any) -> ()
	if not func or typeof(func) ~= "function" then
		warn("unknown customer tool command", command)
		return
	end

	print("executing customer tool", command, ...)
	func(customerTools, player, ...)
end

function GameController.tryBuyItemName(self: GameController, player: Player, itemName: any): ()
	--print("got try buy for player", player, "of item", itemName)

	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		print("bad parameter to buy, item does not exist", itemName)
		-- should we tell client?
		return
	end
	if not itemData.buy then
		print("bad parameter to buy, item is not buyable", itemName)
		-- should we tell client?
		return
	end

	if not buyStoreManager:tryBuyItem(player, itemName) then
		RemoteEvents.NotifyBuyStatus:FireClient(player, false, buyStoreManager:getPurchasesForPlayer(player))
		return
	end

	analyticsManager:logSpendCurrency(
		player,
		itemData.buy.coins,
		playerAttributesManager:get(player, PlayerAttributeKeys.COINS),
		itemName
	)
	analyticsManager:logEvent(player, analyticsManager.Events.BuyItem, {
		objectName = itemName,
		coins = itemData.buy.coins,
		itemType = itemData.type,
		primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
	})

	RemoteEvents.NotifyBuyStatus:FireClient(player, true)
end

function GameController.tryBuyMaxItemName(self: GameController, player: Player, itemName: any): ()
	--print("got try buy max for player", player, "of item", itemName)

	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		print("bad parameter to buy max, item does not exist", itemName)
		return
	end
	if not itemData.buy then
		print("bad parameter to buy max, item is not buyable", itemName)
		return
	end

	local actualQuantity = buyStoreManager:tryBuyMaxItem(player, itemName)
	if not actualQuantity then
		RemoteEvents.NotifyBuyMaxStatus:FireClient(player, 0, buyStoreManager:getPurchasesForPlayer(player))
		return
	end

	analyticsManager:logSpendCurrency(
		player,
		itemData.buy.coins * actualQuantity,
		playerAttributesManager:get(player, PlayerAttributeKeys.COINS),
		itemName
	)
	analyticsManager:logEvent(player, analyticsManager.Events.BuyItem, {
		objectName = itemName,
		coins = itemData.buy.coins * actualQuantity,
		itemType = itemData.type,
		primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		rarity = enums.getPublicName(enums.Rarity, itemData.rarity),
		purchaseType = "max",
		quantity = actualQuantity,
	})

	RemoteEvents.NotifyBuyMaxStatus:FireClient(player, actualQuantity, buyStoreManager:getPurchasesForPlayer(player))
end

function GameController.tryMergeItemsWithHeldItem(self: GameController, player: Player, heldItemId: any, itemIds: any, isMergeAll: any): ()
	--print("got try merge with held item for player", player, "held item", heldItemId, "of items", itemIds)

	if not Validate.isItemIdForPlayer(player, heldItemId) then
		print("bad parameter to merge, held item id", player, heldItemId)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not Validate.areItemIdsForPlayer(player, itemIds) then
		print("bad parameter to merge, item ids", player, itemIds)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not Validate.isPlayerHoldingItemId(player, heldItemId) then
		print("bad parameter to merge, not holding item id", player, heldItemId)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if #itemIds > 1000 then
		print("player tried to merge too many items", #itemIds)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	local allItemIds = utils.shallowCopy(itemIds)
	table.insert(allItemIds, heldItemId)
	if not Validate.areUniqueItemIds(allItemIds) then
		print("bad parameter to merge, not item ids unique", player, allItemIds)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if rideMixin:isPlayerRiding(player) then
		print("bad call to merge with held item when riding", player)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	local playerData = self:getPlayerData(player)
	if not playerData:getIsInPlot() then
		print("player is not in plot, cannot merge", player)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if isMergeAll and not playerData:canMergeAll() then
		print("player is trying to merge all but merge all is locked", player)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not mergeMixin:canMergeItems(player, heldItemId, itemIds, isMergeAll) then
		print("bad data to merge with held item, merge mixin rejects it", player)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	--print("Server determined merge should be allowed")

	-- now merge them -- this is responsible for telling the client it started and ended, unusually
	mergeMixin:notifyMergeItemsWithHeldItem(player, heldItemId, itemIds, isMergeAll)
end

function GameController.tryMergeItemsWithRidingItem(self: GameController, player: Player, ridingItemId: any, itemIds: any, isMergeAll: any): ()
	--print("got try merge with riding item for player", player, "riding item", ridingItemId, "of items", itemIds)

	if not Validate.isItemIdForPlayer(player, ridingItemId) then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not Validate.areItemIdsForPlayer(player, itemIds) then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not self:isPlayerRidingItemId(player, ridingItemId) then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if #itemIds > 1000 then
		print("player tried to merge too many items", #itemIds)
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	local allItemIds = utils.shallowCopy(itemIds)
	table.insert(allItemIds, ridingItemId)
	if not Validate.areUniqueItemIds(allItemIds) then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon or dragon:getItemId() ~= ridingItemId then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	local playerData = self:getPlayerData(player)
	if not playerData:getIsInPlot() then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if isMergeAll and not playerData:canMergeAll() then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	--local ridingItem = itemManager:getItemById(ridingItemId)
	--print("checking if we can merge", ridingItemId, ridingItem, ridingItem:getPart(), ridingItem:getPart().Position)
	if not mergeMixin:canMergeItems(player, ridingItemId, itemIds, isMergeAll) then
		RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	-- now merge them -- this is responsible for telling the client it started and ended, unusually
	mergeMixin:notifyMergeItemsWithRidingItem(player, ridingItemId, itemIds, isMergeAll)
end

-- legacy/dormant: as of 2026-august-20, gems are no longer collected (harvesting/merging grant
-- coins directly, see grantCoinsForGemValue), so the Sell Store's remote handler is unreachable.
-- kept commented rather than deleted since the Sell Store UI itself is also kept dormant.
-- function GameController.trySellGems(self: GameController, player: Player, sellCounts: any): ()
-- 	--print("got try sell gems for player", player, sellCounts)
--
-- 	if not Validate.isTableShape(sellCounts, SELL_GEMS_TABLE_SHAPE) then
-- 		print("invalid sell counts try sell gems", player, sellCounts)
-- 		RemoteEvents.NotifySellStatus:FireClient(player, false)
-- 		return
-- 	end
--
-- 	-- now sell all the items
--
-- 	local primaryElement = sellCounts.primaryElement
-- 	local count = sellCounts.count
--
-- 	local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)
-- 	local currentGems = playerAttributesManager:get(player, gemsKey)
-- 	if currentGems < count then
-- 		print("player", player, "tried to sell", count, "gems but only has", currentGems)
-- 		RemoteEvents.NotifySellStatus:FireClient(player, false)
-- 		return
-- 	end
--
-- 	local totalCoins = 0
-- 	local totalCount = 0
--
-- 	local itemName = Elements.getGemItemNameForPrimaryElement(primaryElement)
-- 	local itemData = objectDataStore:getObjectDataByName(itemName)
--
-- 	totalCoins += itemData.mixins.sell.coins * count
-- 	totalCount += count
--
-- 	--print("player", player, "selling", totalCount, "items for", totalCoins, "coins")
--
-- 	playerAttributesManager:subtractWholeNumber(player, gemsKey, count)
--
-- 	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, totalCoins)
--
-- 	analyticsManager:logGainCurrency(
-- 		player,
-- 		totalCoins,
-- 		playerAttributesManager:get(player, PlayerAttributeKeys.COINS),
-- 		itemName
-- 	)
--
-- 	local coins = itemData.mixins.sell.coins * count
-- 	analyticsManager:logEvent(player, analyticsManager.Events.SellGems, {
-- 		objectName = itemName,
-- 		count = count,
-- 		coins = coins,
-- 		primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
-- 	})
--
-- 	RemoteEvents.NotifySellStatus:FireClient(player, true)
-- end

function GameController.trySummonDragonToEat(self: GameController, player: Player, cropItemId: any): ()
	--print("got try summon dragon to eat for player", player, "crop item", cropItemId)

	if not Validate.isItemIdForPlayer(player, cropItemId) then
		print("invalid item id by", player, "item id", cropItemId)
		RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(cropItemId) :: Types.Item
	if item:getType() ~= "crop" then
		print("invalid item, non-crop by", player, "item id", cropItemId)
		RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, false)
		return
	end

	local crop = item :: Types.Crop
	local cropObj = crop:getObj()

	if cropObj.parent ~= workspace then
		print("invalid item, crop, not in workspace by", player, "item id", cropItemId)
		RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, false)
		return
	end

	if #itemManager:getDragonsMovingToEatCrop(crop) > 0 or self:getCountEatingCrop(crop) > 0 then
		RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, false)
		return
	end

	--print("trying to summon dragon to eat", crop:getItemName())

	local dragon = self:getBestDragonToEatForPlayer(player, crop)
	if not dragon then
		self:sendSystemMessageToPlayer(player, "There are no dragons available to eat this")
		RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifySummonDragonToEatStatus:FireClient(player, true)

	--print("sending dragon", dragon, "to eat", crop)
	crop:notifyDragonComingToEat(dragon)

	dragon:notifyShouldMoveToEat(crop)

	ftueManager:notifySummonToEatForPlayer(player, dragon, crop)
end

function GameController.tryEatWhileRiding(self: GameController, player: Player, cropItemId: any): ()
	--print("got try eat while riding for player", player, "crop item", cropItemId)

	if not Validate.isItemIdForPlayer(player, cropItemId) then
		print("invalid item id by", player, "item id", cropItemId)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(cropItemId) :: Types.Item
	if item:getType() ~= "crop" then
		print("invalid item, non-crop by", player, "item id", cropItemId)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	local crop = item :: Types.Crop
	local cropObj = crop:getObj()

	if cropObj.parent ~= workspace then
		print("invalid item, crop, not in workspace by", player, "item id", cropItemId)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	if not crop:isConsumable() then
		print("invalid item, crop, not consumable by", player, "item id", cropItemId)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot eat while riding when not riding by", player)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	if not dragon:isAvailableToEat() then
		print("riding dragon already eating, can't also eat more", player)
		RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, false)
		return
	end

	--print("eating while riding", dragon, crop, dragon.state)

	dragon:notifyShouldMoveToEat(crop)

	-- if instead of moving to eat, we want to eat from right here, do these instead:
	--dragon:notifyShouldEatCrop(crop)
	--crop:notifyDragonStartEating(dragon)

	RemoteEvents.NotifyEatWhileRidingStatus:FireClient(player, true)
end

function GameController.tryPickupItem(self: GameController, player: Player, itemId: any): ()
	--print("got try pickup for player", player, "item", itemId)

	if not Validate.isItemIdForPlayer(player, itemId) then
		--RemoteEvents.NotifyPickupStatus:FireClient(player, false)
		--print("rejected pickup")
		return
	end

	if not pickupMixin:canPickupItem(player, itemId) then
		--RemoteEvents.NotifyPickupStatus:FireClient(player, false)
		print("rejected pickup")
		return
	end

	--print("Server determined pickup should be allowed")

	-- now pickup
	pickupMixin:notifyPickupItem(player, itemId)
end

function GameController.trySetOption(self: GameController, player: Player, playerOptionKey: any, value: any): ()
	--print("got attempt to set an option for player", player, playerOptionKey, value)

	local playerData = self:getPlayerData(player)
	playerData:trySetOption(playerOptionKey, value)
end

function GameController.trySummonDragonToOpen(self: GameController, player: Player, crystalItemId: any): ()
	--print("got try summon dragon to open for player", player, "crystal item", crystalItemId)

	if not Validate.isItemIdForPlayer(player, crystalItemId) then
		print("invalid item id by", player, "item id", crystalItemId)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(crystalItemId) :: Types.Item
	if item:getType() ~= "crystal" then
		print("invalid item, non-crystal by", player, "item id", crystalItemId)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	local crystal = item :: Types.Crystal
	local crystalObj = crystal:getObj()

	if crystalObj.parent ~= workspace then
		print("invalid item, crystal, not in workspace by", player, "item id", crystalItemId)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	--print("trying to summon dragon to open", crystal:getItemName())

	local dragon, reasonStr = self:getBestDragonToOpenForPlayer(player, crystal)
	if not dragon then
		self:sendSystemMessageToPlayer(player, reasonStr)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, true)

	crystal:notifyDragonComingToOpen(dragon)

	dragon:notifyShouldMoveToOpen(crystal)
end

function GameController.tryClaimCrystal(self: GameController, player: Player, crystalItemId: any): ()
	--print("got try claim crystal for player", player, "crystal item", crystalItemId)

	if not Validate.isItemIdForPlayer(player, crystalItemId) then
		print("invalid item id by", player, "item id", crystalItemId)
		RemoteEvents.NotifyClaimCrystalStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(crystalItemId) :: Types.Item
	if item:getType() ~= "crystal" then
		print("invalid item, non-crystal by", player, "item id", crystalItemId)
		RemoteEvents.NotifyClaimCrystalStatus:FireClient(player, false)
		return
	end

	local crystal = item :: Types.Crystal
	local crystalObj = crystal:getObj()

	if crystalObj.parent ~= workspace then
		print("invalid item, crystal, not in workspace by", player, "item id", crystalItemId)
		RemoteEvents.NotifyClaimCrystalStatus:FireClient(player, false)
		return
	end

	if not crystal:isOpened() then
		print("invalid item, crystal, not opened by", player, "item id", crystalItemId)
		RemoteEvents.NotifyClaimCrystalStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyClaimCrystalStatus:FireClient(player, true)

	crystal:notifyClaim()
end

function GameController.tryBeginRideDragon(self: GameController, player: Player, itemId: any, playerRelativeToDragonCFrame: any): ()
	--print("got try ride dragon for player", player, "dragon item", itemId)

	if not Validate.isItemId(itemId) then
		RemoteEvents.NotifyBeginRideDragonStatus:FireClient(player, false)
		return
	end

	if not rideMixin:canRideItem(player, itemId) then
		local playerData = self:getPlayerData(player)
		local ridingItemId = playerData:getRidingItemId()
		if ridingItemId then
			if ridingItemId == itemId then
				--uh... ok, they requested to ride a drogn we think they're already riding
				RemoteEvents.NotifyBeginRideDragonStatus:FireClient(player, true)
				return
			else
				print("player tried to ride", itemId, "while already riding", ridingItemId, "so we're stopping it")
				RemoteEvents.NotifyBeginRideDragonStatus:FireClient(player, false)
				rideMixin:stopPlayerRiding(player)
				return
			end
		end

		RemoteEvents.NotifyBeginRideDragonStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyBeginRideDragonStatus:FireClient(player, true)

	rideMixin:notifyPlayerBeginRideDragon(player, itemId, playerRelativeToDragonCFrame or CFrame.identity)
end

function GameController.tryEndRideDragon(self: GameController, player: Player, itemId: any): ()
	--print("got try ride dragon for player", player, "dragon item", itemId)

	if not Validate.isItemId(itemId) then
		--RemoteEvents.NotifyEndRideDragonStatus:FireClient(player, false)
		return
	end

	if not self:isPlayerRidingItemId(player, itemId) then
		print("invalid end riding request for item not riding by player", player, itemId)
		--RemoteEvents.NotifyEndRideDragonStatus:FireClient(player, false)
		return
	end

	--RemoteEvents.NotifyEndRideDragonStatus:FireClient(player, true)

	rideMixin:notifyPlayerEndRideDragon(player, itemId)
end

function GameController.tryMarkInstantOpenCrystal(self: GameController, player: Player, crystalItemId: any): ()
	--print("got try mark instant open crystal player", player, "of item", crystalItemId)

	if not Validate.isItemIdForPlayer(player, crystalItemId) then
		print("invalid item id by", player, "item id", crystalItemId)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(crystalItemId) :: Types.Item
	if item:getType() ~= "crystal" then
		print("invalid item, non-crystal by", player, "item id", crystalItemId)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	local crystal = item :: Types.Crystal

	if not crystal:isOpening() then
		print("invalid item, crystal, not opened by", player, "item id", crystalItemId)
		--RemoteEvents.NotifySummonDragonToOpenStatus:FireClient(player, false)
		return
	end

	local playerData = self:getPlayerData(player)

	--print("marking crystal", crystalItemId)
	playerData:markInstantOpenCrystalItemId(crystalItemId)

	-- for test purposes did this in the past, but now you need to robux purchase:
	--crystal:finishOpeningSuccessfully()
end

function GameController.trySummonDragonToMine(self: GameController, player: Player, nodeObjectId: any): ()
	--print("got try summon dragon to mine player", player, "of object id", nodeObjectId)

	if not Validate.isNodeObjectId(nodeObjectId) then
		-- this can happen when old ones killed / new ones created
		RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, false)
		return
	end

	local node = islandManager:getNodeByObjectId(nodeObjectId)

	if not node:canBeMinedByPlayer(player) then
		RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, false)
		return
	end

	if rideMixin:isPlayerRiding(player) then
		RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, false)
		return
	end

	if not node:isPlayerCloseEnoughToSummonToMine(player) then
		RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, false)
		return
	end

	--print("trying to summon dragon to mine node", node)

	local dragon = self:getBestDragonToMineForPlayer(player, node)
	if not dragon then
		self:sendSystemMessageToPlayer(player, "There are no dragons available to mine this crystal node")
		RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifySummonDragonToMineStatus:FireClient(player, true)

	node:notifyDragonComingToMine(dragon)

	dragon:notifyShouldMoveToMine(node)
end

function GameController.tryMineWhileRiding(self: GameController, player: Player, nodeObjectId: any): ()
	--print("got try mine while riding player", player, "of object id", nodeObjectId)

	if not Validate.isNodeObjectId(nodeObjectId) then
		--print("invalid object id by", player, "object id", nodeObjectId)
		-- this can happen when old ones killed / new ones created
		RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, false)
		return
	end

	local node = islandManager:getNodeByObjectId(nodeObjectId)

	if not node:canBeMinedByPlayer(player) then
		RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, false)
		return
	end

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot mine while riding when not riding by", player)
		RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, false)
		return
	end

	if not node:isPlayerCloseEnoughToMineWhileRiding(player) then
		RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, true)

	dragon:notifyShouldMineNode(node)
end

function GameController.tryOpenPack(self: GameController, player: Player, packItemId: any): ()
	--print("got try open pack player", player, "of item", packItemId)

	if not Validate.isItemIdForPlayer(player, packItemId) then
		print("invalid item id by", player, "item id", packItemId)
		RemoteEvents.NotifyOpenPackStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(packItemId) :: Types.Item
	if item:getType() ~= "pack" then
		print("invalid item, non-pack by", player, "item id", packItemId)
		RemoteEvents.NotifyOpenPackStatus:FireClient(player, false)
		return
	end

	local pack = item :: Types.Pack

	RemoteEvents.NotifyOpenPackStatus:FireClient(player, true)

	pack:notifyShouldOpen()
end

function GameController.tryOpenCrate(self: GameController, player: Player, crateItemId: any): ()
	if not Validate.isItemIdForPlayer(player, crateItemId) then
		print("invalid item id by", player, "item id", crateItemId)
		RemoteEvents.NotifyOpenCrateStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(crateItemId) :: Types.Item
	if item:getType() ~= "crate" then
		print("invalid item, non-crate by", player, "item id", crateItemId)
		RemoteEvents.NotifyOpenCrateStatus:FireClient(player, false)
		return
	end

	local crate = item :: Types.Crate

	local distance = ((player.Character :: any).HumanoidRootPart.Position - crate:getPart().Position).Magnitude
	if distance > Constants.OPEN_CRATE_DISTANCE * 1.1 then
		print("player tried to open crate but too far away", player, distance)
		RemoteEvents.NotifyOpenCrateStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyOpenCrateStatus:FireClient(player, true)

	crate:notifyShouldOpen()
end

function GameController.trySetRidingItemCFrame(self: GameController, player: Player, itemId: any, time: any, cframe: any, playerRelativeToDragonCFrame: any): ()
	if not Validate.isItemIdForPlayer(player, itemId) then
		--print("invalid riding item by", player, "item id", itemId)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item
	if item:getType() ~= "shadowDragon" then
		--print("invalid riding item type by", player, "item id", itemId, "type", item:getItemData():getType())
		return
	end

	-- assign player cframe, so server and other players know where they are
	-- (when player is welded to a part and that part is moved, the client doesn't update the server if the server doesn't know about that part,
	-- which is the case here with shadow dragons)
	self:getPlayerData(player):notifyRidingItemCFrame(cframe, playerRelativeToDragonCFrame)

	-- assign dragon cframe
	local dragon = item :: Types.ShadowDragon
	dragon:trySetRidingItemCFrame(time, cframe)
end

function GameController.tryShootFireballAtCrop(self: GameController, player: Player, cropItemId: any): ()
	--print("got try shoot fireball at crop player", player, "of item id", cropItemId)

	if not Validate.isItemIdForOtherPlayer(player, cropItemId) then
		print("invalid item id by", player, "item id", cropItemId)
		RemoteEvents.NotifyShootFireballAtCropStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(cropItemId) :: Types.Item
	if item:getType() ~= "crop" then
		print("invalid item, non-crop by", player, "item id", cropItemId)
		RemoteEvents.NotifyShootFireballAtCropStatus:FireClient(player, false)
		return
	end

	local crop = item :: Types.Crop

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot shoot fireball at crop when not riding by", player)
		RemoteEvents.NotifyShootFireballAtCropStatus:FireClient(player, false)
		return
	end

	if not crop:isPlayerCloseEnoughToShootFireballAtCrop(player) then
		RemoteEvents.NotifyShootFireballAtCropStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyShootFireballAtCropStatus:FireClient(player, true)

	dragon:notifyShouldShootFireballAtCrop(crop)
end

function GameController.tryShootFireballAtCritter(self: GameController, player: Player, critterObjectId: any): ()
	--print("got try shoot fireball at critter player", player, "of object id", critterObjectId)

	if not Validate.isCritterObjectId(critterObjectId) then
		--print("invalid object id by", player, "object id", nodeObjectId)
		-- this can happen when old ones killed / new ones created
		RemoteEvents.NotifyShootFireballAtCritterStatus:FireClient(player, false)
		return
	end

	local critter = islandManager:getCritterByObjectId(critterObjectId)

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot shoot fireball at critter when not riding when not riding by", player)
		RemoteEvents.NotifyShootFireballAtCritterStatus:FireClient(player, false)
		return
	end

	if not critter:isPlayerCloseEnoughToShootFireballAtCritter(player) then
		RemoteEvents.NotifyShootFireballAtCritterStatus:FireClient(player, false)
		return
	end

	RemoteEvents.NotifyShootFireballAtCritterStatus:FireClient(player, true)

	dragon:notifyShouldShootFireballAtCritter(critter)
end

function GameController.tryChargeUpRidingDragon(self: GameController, player: Player): ()
	--print("got try charge up riding dragon player", player)

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot charge up dragon when not riding by", player)
		return
	end

	if not dragon:canChargeUp() then
		print("cannot charge up dragon when not under client control", player)
		return
	end

	dragon:notifyShouldChargeUp()
end

function GameController.tryPutAwayRidingDragon(self: GameController, player: Player): ()
	--print("got try put away riding dragon player", player)

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		print("cannot charge up dragon when not riding by", player)
		return
	end

	if not dragon:getItemData().mixins.pickup then
		print("cannot pick up dragon that is not configured to be picked up", player)
		return
	end

	if not dragon:isClientControlling() then
		--print("cannot pick up dragon that is server controlled", player)
		return
	end

	if not dragon:isInFreeFlyZone() then
		--print("cannot put away dragon outside free fly zone", player)
		return
	end

	rideMixin:stopPlayerRiding(player)

	dragon:putInBackpack()
end

function GameController.tryEquipAbility(self: GameController, player: Player, ability: any): ()
	--print("got try equip ability for player", player, ability)

	if not Abilities.validateAbility(ability) then
		print("invalid ability", player, ability)
		return
	end

	local playerData = self:getPlayerData(player)
	if not playerData:canEquipAbility(ability) then
		-- client should prevent this from happening unless there are bugs,
		-- so we don't bother showing an error
		print("player data says cannot equip", player, ability)
		RemoteEvents.NotifyEquipAbilityStatus:FireClient(player, false)
		return
	end

	-- check price
	-- legacy (2026-august-20): abilities used to cost per-element gems; now they cost coins
	-- (old gem cost * 10, see Abilities.getEquipCoinCostForAbility) from the unified balance.
	-- local gemCount = Abilities.getEquipGemCountForAbility(ability)
	-- local primaryElement = Abilities.getPrimaryElementForAbility(ability)
	-- local playerAttributesKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)
	-- local playerGemCount = playerAttributesManager:get(player, playerAttributesKeyGems)
	-- if gemCount > playerGemCount then
	-- 	--print("player does not have enough gems to equip ability", player, ability, gemCount, playerGemCount)
	-- 	local abilityName = Abilities.getDisplayNameForAbility(ability)
	-- 	self:sendSystemMessageToPlayer(player, string.format("You do not have enough gems to equip %s", abilityName))
	-- 	RemoteEvents.NotifyEquipAbilityStatus:FireClient(player, false)
	-- 	return
	-- end
	--
	-- -- pay the price
	-- playerAttributesManager:subtractWholeNumber(player, playerAttributesKeyGems, gemCount)

	local coinCost = Abilities.getEquipCoinCostForAbility(ability)
	if playerAttributesManager:get(player, PlayerAttributeKeys.COINS) < coinCost then
		local abilityName = Abilities.getDisplayNameForAbility(ability)
		self:sendSystemMessageToPlayer(player, string.format("You do not have enough coins to equip %s", abilityName))
		RemoteEvents.NotifyEquipAbilityStatus:FireClient(player, false)
		return
	end

	-- pay the price
	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.COINS, coinCost)

	playerData:equipAbility(ability)

	--print("success equipping", player, ability)

	RemoteEvents.NotifyEquipAbilityStatus:FireClient(player, true)

	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
end

function GameController.tryUnequipAbility(self: GameController, player: Player, ability: any): ()
	--print("got try unequip ability for player", player, ability)

	if not Abilities.validateAbility(ability) then
		print("invalid ability", player, ability)
		return
	end

	local playerData = self:getPlayerData(player)
	if not playerData:canUnequipAbility(ability) then
		print("player data says cannot unequip", player, ability)
		return
	end

	playerData:unequipAbility(ability)

	--print("success unequipping", player, ability)

	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
end

function GameController.tryEquipDragon(self: GameController, player: Player, itemId: any, stableSlotIndex: any): ()
	if not Validate.isItemIdForPlayer(player, itemId) then
		print("invalid itemId for equip dragon", player, itemId)
		return
	end

	if not Validate.isInteger(stableSlotIndex) then
		print("invalid stable slot index for equip dragon", player, stableSlotIndex)
		return
	end

	stableManager:tryEquipDragon(player, itemId, stableSlotIndex)
end

function GameController.tryUnequipDragon(self: GameController, player: Player, stableSlotIndex: any): ()
	if not Validate.isInteger(stableSlotIndex) then
		print("invalid stable slot index for unequip dragon", player, stableSlotIndex)
		return
	end

	stableManager:tryUnequipDragon(player, stableSlotIndex)
end

function GameController.trySetFtueStep(self: GameController, player: Player, stepName: any): ()
	--print("got try set ftue next step for player", player)

	if stepName == nil then
		if ftueManager:trySetComplete(player) then
			--print("starting first session offer", player)
			firstSessionOfferManager:startOffer(player)
		end
		return
	end

	if not FtueSteps.validateStepName(stepName) then
		print("invalid ftue step name", player, stepName)
		return
	end

	ftueManager:trySetStepName(player, stepName)
end

function GameController.tryTriggerContextualFtue(self: GameController, player: Player, hintId: any): ()
	contextualFtueManager:tryTrigger(player, hintId)
end

function GameController.tryRedeemFirstSessionOffer(self: GameController, player: Player): ()
	--print("got try redeem first session offer for player", player)

	if not firstSessionOfferManager:canRedeem(player) then
		return
	end

	firstSessionOfferManager:redeem(player)

	-- status?

	return
end

function GameController.tryRequestBeginTrade(self: GameController, player: Player, partnerPlayerName: any): ()
	--print("got request begin trade", player, partnerPlayerName)

	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	if player.Name == partnerPlayerName then
		-- can't trade with yourself
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if tradeManager:isPlayerTrading(player) then
		print("rejected trade; player is already trading", player)
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	if tradeManager:isPlayerTrading(partnerPlayer) then
		self:sendSystemMessageToPlayer(
			player,
			string.format("%s is already trading with someone else", partnerPlayer.Name)
		)
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	local partnerPlayerData = self:getPlayerData(partnerPlayer)
	if not partnerPlayerData:getOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED) then
		print("cannot send request to player with option off")
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	if partnerPlayerData:isInFtue() then
		self:sendSystemMessageToPlayer(player, string.format("%s in not yet eligible to trade", partnerPlayerName))
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	local playerData = self:getPlayerData(player)
	playerData:incrementTradeRequestCount()
	if playerData:getTradeRequestCount() > 5 then
		self:sendSystemMessageToPlayer(player, "You have sent too many trade requests; wait a minute")
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	if not self:isTradingEnabled() then
		RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, false)
		return
	end

	RemoteEvents.NotifyRequestBeginTradeStatus:FireClient(player, partnerPlayerName, true)

	tradeManager:beginTradeRequest(player, partnerPlayer)

	RemoteEvents.NotifyBeginTradeRequested:FireClient(partnerPlayer, player.Name)

	analyticsManager:logEvent(player, analyticsManager.Events.SendTradeRequest, {})
end

function GameController.tryRespondBeginTrade(self: GameController, player: Player, partnerPlayerName: any, doesAccept: any): ()
	--print("got respond begin trade", player, partnerPlayerName, doesAccept)

	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	if not Validate.isBoolean(doesAccept) then
		return
	end

	if player.Name == partnerPlayerName then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if not tradeManager:haveTradeRequest(partnerPlayer, player) then
		print("cannot respond to trade request that does not exist", partnerPlayer, player)
		if doesAccept then
			-- if they accepted, cancel it for them
			RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		end
		return
	end

	if doesAccept then
		tradeManager:acceptTradeRequest(partnerPlayer, player)
	else
		tradeManager:declineTradeRequest(partnerPlayer, player)
	end

	RemoteEvents.NotifyBeginTradeStatus:FireClient(partnerPlayer, player.Name, doesAccept)

	if doesAccept then
		analyticsManager:logEvent(player, analyticsManager.Events.AcceptTradeRequest, {})
	else
		analyticsManager:logEvent(player, analyticsManager.Events.DeclineTradeRequest, {})
	end
end

function GameController.tryLockTradeOffer(self: GameController, player: Player, partnerPlayerName: any, playerOffer: any): ()
	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if not tradeManager:arePlayersInTrade(player, partnerPlayer) then
		print("cannot lock trade offer when not trading", player, partnerPlayer)
		RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		return
	end

	if not Validate.isTableShape(playerOffer, TRADE_OFFER_TABLE_SHAPE) then
		print("invalid offer given to try lock trade offer", player, playerOffer)
		return
	end

	if #playerOffer.itemDescriptors > tradeManager:getMaxItemCount() then
		print("invalid offer too many items given to try lock trade offer", player, playerOffer)
		return
	end

	for _, itemDescriptor in playerOffer.itemDescriptors do
		local itemId = itemDescriptor.itemId
		local count = itemDescriptor.count
		if not Validate.isItemIdForPlayer(player, itemId) then
			print("invalid offer to try lock trade offer with itemId not for player", player, itemId)
			tradeManager:cancelTradeAndNotify(player, partnerPlayer)
			return
		end
		-- isItemIdForPlayer above guarantees the item exists
		local item = itemManager:getItemById(itemId) :: Types.Item
		if item:getCount() < count then
			print(
				"invalid offer to try lock trade offer with count too high",
				player,
				itemId,
				item:getItemName(),
				item:getCount(),
				count
			)
			tradeManager:cancelTradeAndNotify(player, partnerPlayer)
			return
		end
	end

	if not tradeManager:canModifyOffer(player, partnerPlayer) then
		print("cannot modify offer when in the wrong state", player, partnerPlayer)
		tradeManager:cancelTradeAndNotify(player, partnerPlayer)
		return
	end

	tradeManager:setOffer(player, partnerPlayer, playerOffer)

	local partnerOffer = {
		itemDescriptors = tradeManager:getRecreateItemDescriptors(playerOffer.itemDescriptors),
	}

	RemoteEvents.NotifyTradePartnerOffer:FireClient(partnerPlayer, player.Name, partnerOffer)
end

function GameController.tryRemoveTradeOffer(self: GameController, player: Player, partnerPlayerName: any): ()
	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if not tradeManager:arePlayersInTrade(player, partnerPlayer) then
		print("cannot remove trade offer when not trading", player, partnerPlayer)
		RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		return
	end

	if not tradeManager:canModifyOffer(player, partnerPlayer) then
		print("cannot modify offer when in the wrong state", player, partnerPlayer)
		tradeManager:cancelTradeAndNotify(player, partnerPlayer)
		return
	end

	tradeManager:setOffer(player, partnerPlayer, nil)

	RemoteEvents.NotifyTradePartnerRemoveOffer:FireClient(partnerPlayer, player.Name)
end

function GameController.tryAcceptTrade(self: GameController, player: Player, partnerPlayerName: any): ()
	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if not tradeManager:arePlayersInTrade(player, partnerPlayer) then
		print("cannot accept trade when not trading", player, partnerPlayer)
		RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		return
	end

	if not tradeManager:canAccept(player, partnerPlayer) then
		print("cannot accept trade when in the wrong state", player, partnerPlayer)
		tradeManager:cancelTradeAndNotify(player, partnerPlayer)
		return
	end

	tradeManager:accept(player, partnerPlayer)

	RemoteEvents.NotifyTradePartnerAccepted:FireClient(partnerPlayer, player.Name)
end

function GameController.tryConfirmTrade(self: GameController, player: Player, partnerPlayerName: any): ()
	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if not tradeManager:arePlayersInTrade(player, partnerPlayer) then
		print("cannot confirm trade when not trading", player, partnerPlayer)
		RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		return
	end

	if not tradeManager:canConfirm(player, partnerPlayer) then
		print("cannot confirm trade when in the wrong state", player, partnerPlayer)
		tradeManager:cancelTradeAndNotify(player, partnerPlayer)
		return
	end

	if not self:isTradingEnabled() then
		return
	end

	tradeManager:confirm(player, partnerPlayer)

	RemoteEvents.NotifyTradePartnerConfirmed:FireClient(partnerPlayer, player.Name)
end

function GameController.tryCancelTrade(self: GameController, player: Player, partnerPlayerName: any): ()
	if not Validate.isPlayerNameOnServer(partnerPlayerName) then
		return
	end

	-- the name was validated to be on this server just above, so the lookup cannot miss
	local partnerPlayer = self:getPlayerByName(partnerPlayerName) :: Player

	if
		not tradeManager:arePlayersInTrade(player, partnerPlayer)
		and not tradeManager:arePlayersInRequestTrade(player, partnerPlayer)
	then
		print("cannot cancel trade when not trading", player, partnerPlayer)
		RemoteEvents.NotifyCancelTrade:FireClient(player, partnerPlayerName)
		return
	end

	tradeManager:cancelTrade(player, partnerPlayer)

	RemoteEvents.NotifyCancelTrade:FireClient(partnerPlayer, player.Name)
end

function GameController.tryLogAnalyticsEvent(self: GameController, player: Player, eventName: any, properties: any): ()
	if not Validate.isString(eventName) then
		return
	end

	if not Validate.isTable(properties) then
		return
	end

	if not Validate.isTableBelowSize(properties, 10) then
		return
	end

	analyticsManager:tryLogClientEvent(player, eventName, properties)
end

function GameController.trySubmitCode(self: GameController, player: Player, rawCode: any): ()
	if not Validate.isString(rawCode) then
		return
	end

	if string.len(rawCode) > codeManager:getMaxCodeLength() then
		print("player sent code too long", player, rawCode)
		return
	end

	-- remove whitespace, all caps
	-- extra parentheses force only one return value, discarding the rest of gsub's results
	local code = string.upper((string.gsub(rawCode, "%s+", "")))

	codeManager:tryApplyCode(player, code)
end

function GameController.trySetBackpackIndex(self: GameController, player: Player, itemId: any, index: number?): ()
	if not Validate.isItemIdForPlayer(player, itemId) then
		print("invalid item by", player, "item id", itemId)
		return
	end

	if not index or not Validate.isValueType(index, "positiveNumber") then
		print("invalid backpack index from player", player, index)
		return
	end

	if index > 10000 then
		print("invalid backpack index too large from player", player, index)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item
	item:setBackpackIndex(index)

	--print("setting backpack index", item, "index", index)
end

function GameController.tryOpenChest(self: GameController, player: Player, objectId: number, heldItemId: any): ()
	if not Validate.isChestObjectId(objectId) then
		--print("invalid object id by", player, "object id", objectId)
		--RemoteEvents.NotifyMineWhileRidingStatus:FireClient(player, false)
		return
	end

	local chest = islandManager:getChestByObjectId(objectId)

	if not Validate.isItemIdForPlayer(player, heldItemId) then
		print("bad parameter to tryOpenChest, held item id", player, heldItemId)
		--RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	if not Validate.isPlayerHoldingItemId(player, heldItemId) then
		print("bad parameter to try open chest, not holding item id", player, heldItemId)
		--RemoteEvents.NotifyMergeBeginStatus:FireClient(player, false)
		return
	end

	-- the id was validated above, so the item exists
	local item = itemManager:getItemById(heldItemId) :: Types.Item
	if item:getType() ~= "key" then
		--print("invalid non-key type by", player, "item id", heldItemId, "type", item:getItemData():getType())
		return
	end

	if not chest:canKeyOpen(item) then
		return
	end

	if not chest:isPlayerCloseEnoughToOpen(player) then
		return
	end

	if not chest:isClosed() then
		return
	end

	chest:notifyShouldOpen(item)
end

function GameController.tryUnlockVanityComponent(self: GameController, player: Player, vanityPlacement: any, vanityComponentName: any): ()
	--print("player trying to unlock vanity component", player, vanityPlacement, vanityComponentName)

	if not plotsManager:validateVanityPlacement(vanityPlacement) then
		warn("invalid vanity placement", player, vanityPlacement)
		return
	end

	if not plotsManager:validateVanityComponentName(vanityComponentName) then
		warn("invalid vanity component name", player, vanityComponentName)
		return
	end

	local playerData = self:getPlayerData(player)

	if not playerData:isVanityComponentLocked(vanityComponentName) then
		print("cannot unlock vanity component that is not locked", vanityComponentName)
		return
	end

	-- see if we have a blueprint
	local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
	local itemName = vanityComponentData.blueprintName
	local isUnlockable = playerData:doesPlayerHaveItemCount(itemName, 1)
	if not isUnlockable then
		print("player does not have blueprint to unlock vanity component", player, vanityComponentName)
		return
	end

	local blueprint = playerData:getItemForPlayer(itemName)

	playerData:unlockVanityComponent(vanityComponentName)
	blueprint:reduceCount(1)

	playerData:equipVanityComponentAtPlacement(vanityPlacement, vanityComponentName)
end

function GameController.tryEquipVanityComponent(self: GameController, player: Player, vanityPlacement: any, vanityComponentName: any): ()
	--print("player trying to equip vanity component", player, vanityPlacement, vanityComponentName)

	if not plotsManager:validateVanityPlacement(vanityPlacement) then
		warn("invalid vanity placement", player, vanityPlacement)
		return
	end

	if not plotsManager:validateVanityComponentName(vanityComponentName) then
		warn("invalid vanity component name", player, vanityComponentName)
		return
	end

	local playerData = self:getPlayerData(player)
	if not playerData:isVanityComponentUnlocked(vanityComponentName) then
		print("cannot equip vanity component that is not unlocked", vanityComponentName)
		return
	end

	playerData:equipVanityComponentAtPlacement(vanityPlacement, vanityComponentName)
end

function GameController.tryUnequipVanityPlacement(self: GameController, player: Player, vanityPlacement: any): ()
	--print("player trying to unequip vanity placement", player, vanityPlacement)

	if not plotsManager:validateVanityPlacement(vanityPlacement) then
		warn("invalid vanity placement", player, vanityPlacement)
		return
	end

	local playerData = self:getPlayerData(player)
	playerData:unequipVanityPlacement(vanityPlacement)
end

function GameController.tryBuyVanityArea(self: GameController, player: Player, vanityArea: any): ()
	--print("player trying to buy vanity area", player, vanityArea)

	if not enums.validateValue(enums.VanityAreas, vanityArea) then
		return
	end

	local playerData = self:getPlayerData(player)
	local vanityAreaState = playerData:getVanityAreaState(vanityArea)
	if vanityAreaState == enums.VanityAreaState.UNLOCKED then
		return
	end
	if vanityAreaState ~= enums.VanityAreaState.LOCKED then
		warn("unknown vanity area state", player, vanityArea, vanityAreaState)
		return
	end

	local coins = vanityAreasData.unlockPurchase[vanityArea].coins
	if not coins then
		warn("no coin value found for vanity area", vanityArea)
		return
	end

	if playerAttributesManager:get(player, PlayerAttributeKeys.COINS) < coins then
		self:sendSystemMessageToPlayer(
			player,
			string.format(
				"Your don't have enough coins to unlock %s",
				tostring(enums.getPublicName(enums.VanityAreas, vanityArea))
			)
		)
		return
	end

	playerData:unlockVanityArea(vanityArea)
	playerAttributesManager:subtractWholeNumber(player, PlayerAttributeKeys.COINS, coins)
end

function GameController.tryCheckGroup(self: GameController, player: Player): ()
	--print("player trying to check group", player)

	local playerData = self:getPlayerData(player)
	playerData:updateCommunityGroupData()
end

function GameController.tryPlaceLuckBillboardForPlayer(self: GameController, player: Player): ()
	local playerData = self:getPlayerData(player)
	if not playerData.hasClaimedGroupLuck then
		RemoteEvents.NotifyShowLuckBillboard:FireClient(player)
	end
end

function GameController.tryClaimLuckBillboard(self: GameController, player: Player): ()
	local playerData = self:getPlayerData(player)
	playerData:updateCommunityGroupData()
	local isInGroup = playerData.isInCommunityGroup
	if isInGroup then
		playerData.hasClaimedGroupLuck = true
	end
	RemoteEvents.NotifyLuckBillboardResult:FireClient(player, isInGroup)
end

function GameController.tryClaimWelcomeBackGift(self: GameController, player: Player): ()
	--print("player trying to claim welcome back gift", player)

	local playerData = self:getPlayerData(player)
	playerData:tryClaimWelcomeBackGift()
end

function GameController.tryClaimIndexReward(self: GameController, player: Player, category: any, scope: any, chainKey: any, tierIndex: any): ()
	if not self:isIndexEnabled() then
		return
	end

	local playerData = self:getPlayerData(player)

	local isSuccess = indexManager:tryClaimReward(player, playerData, category, scope, chainKey, tierIndex)

	local tierId = nil
	local milestoneViewModels = nil
	if isSuccess then
		milestoneViewModels = indexManager:getMilestones(playerData, category, scope, chainKey)
		local claimedViewModel = milestoneViewModels[tierIndex]
		tierId = claimedViewModel and claimedViewModel.tierId
	end

	RemoteEvents.NotifyClaimIndexRewardStatus:FireClient(
		player,
		isSuccess,
		category,
		scope,
		chainKey,
		tierId,
		milestoneViewModels
	)
end

function GameController.tryRefreshIndexData(self: GameController, player: Player): ()
	if not self:isIndexEnabled() then
		return
	end

	local playerData = self:getPlayerData(player)

	local refreshedData = indexManager:refreshIndexData(player, playerData)
	if not refreshedData then
		return
	end

	RemoteEvents.NotifyIndexDataRefreshed:FireClient(player, refreshedData)
end

function GameController.addRemoteEventHandler(self: GameController, remoteEventName: string, funcName: string): ()
	self.remoteEventMetrics[remoteEventName] = {
		count = 0,
		elapsedTime = 0,
	}

	RemoteEvents[remoteEventName].OnServerEvent:Connect(function(...)
		--print("got remote func call", remoteEventName)
		self.remoteEventMetrics[remoteEventName].count += 1

		local beginTime = os.clock()

		local func = (self :: any)[funcName] :: (GameController, ...any) -> ()

		if func then
			func(self, ...)
		end

		local endTime = os.clock()
		local elapsedTime = endTime - beginTime
		self.remoteEventMetrics[remoteEventName].elapsedTime += elapsedTime
	end)
end

function GameController.getRemoteEventMetrics(self: GameController): any
	return self.remoteEventMetrics
end

function GameController.listenToRemoteEvents(self: GameController): ()
	-- move these into subdir with event handlers eventually; for now, functions here

	self:addRemoteEventHandler("TryDevTool", "tryDevTool")
	self:addRemoteEventHandler("TryCustomerTool", "tryCustomerTool")
	self:addRemoteEventHandler("TryBuyItemName", "tryBuyItemName")
	self:addRemoteEventHandler("TryBuyMaxItemName", "tryBuyMaxItemName")
	self:addRemoteEventHandler("TryMergeItemsWithHeldItem", "tryMergeItemsWithHeldItem")
	self:addRemoteEventHandler("TryMergeItemsWithRidingItem", "tryMergeItemsWithRidingItem")
	-- legacy/dormant (2026-august-20): gem-selling removed, see trySellGems definition
	-- self:addRemoteEventHandler("TrySellGems", "trySellGems")
	self:addRemoteEventHandler("TrySummonDragonToEat", "trySummonDragonToEat")
	self:addRemoteEventHandler("TryEatWhileRiding", "tryEatWhileRiding")
	self:addRemoteEventHandler("TryPickupItem", "tryPickupItem")
	self:addRemoteEventHandler("TrySetOption", "trySetOption")
	self:addRemoteEventHandler("TrySummonDragonToOpen", "trySummonDragonToOpen")
	self:addRemoteEventHandler("TryClaimCrystal", "tryClaimCrystal")
	self:addRemoteEventHandler("TryBeginRideDragon", "tryBeginRideDragon")
	self:addRemoteEventHandler("TryEndRideDragon", "tryEndRideDragon")
	self:addRemoteEventHandler("TryMarkInstantOpenCrystal", "tryMarkInstantOpenCrystal")
	self:addRemoteEventHandler("TrySummonDragonToMine", "trySummonDragonToMine")
	self:addRemoteEventHandler("TryMineWhileRiding", "tryMineWhileRiding")
	self:addRemoteEventHandler("TryOpenPack", "tryOpenPack")
	self:addRemoteEventHandler("TryOpenCrate", "tryOpenCrate")
	self:addRemoteEventHandler("TrySetRidingItemCFrame", "trySetRidingItemCFrame")
	self:addRemoteEventHandler("TryShootFireballAtCrop", "tryShootFireballAtCrop")
	self:addRemoteEventHandler("TryShootFireballAtCritter", "tryShootFireballAtCritter")
	self:addRemoteEventHandler("TryChargeUpRidingDragon", "tryChargeUpRidingDragon")
	self:addRemoteEventHandler("TryPutAwayRidingDragon", "tryPutAwayRidingDragon")
	self:addRemoteEventHandler("TryEquipAbility", "tryEquipAbility")
	self:addRemoteEventHandler("TryUnequipAbility", "tryUnequipAbility")
	self:addRemoteEventHandler("TryEquipDragon", "tryEquipDragon")
	self:addRemoteEventHandler("TryUnequipDragon", "tryUnequipDragon")
	self:addRemoteEventHandler("TrySetFtueStep", "trySetFtueStep")
	self:addRemoteEventHandler("TryTriggerContextualFtue", "tryTriggerContextualFtue")
	self:addRemoteEventHandler("TryRedeemFirstSessionOffer", "tryRedeemFirstSessionOffer")
	self:addRemoteEventHandler("TryRequestBeginTrade", "tryRequestBeginTrade")
	self:addRemoteEventHandler("TryRespondBeginTrade", "tryRespondBeginTrade")
	self:addRemoteEventHandler("TryLockTradeOffer", "tryLockTradeOffer")
	self:addRemoteEventHandler("TryRemoveTradeOffer", "tryRemoveTradeOffer")
	self:addRemoteEventHandler("TryAcceptTrade", "tryAcceptTrade")
	self:addRemoteEventHandler("TryConfirmTrade", "tryConfirmTrade")
	self:addRemoteEventHandler("TryCancelTrade", "tryCancelTrade")
	self:addRemoteEventHandler("TryLogAnalyticsEvent", "tryLogAnalyticsEvent")
	self:addRemoteEventHandler("TrySubmitCode", "trySubmitCode")
	self:addRemoteEventHandler("TrySetBackpackIndex", "trySetBackpackIndex")
	self:addRemoteEventHandler("TryOpenChest", "tryOpenChest")
	self:addRemoteEventHandler("TryUnlockVanityComponent", "tryUnlockVanityComponent")
	self:addRemoteEventHandler("TryClaimIndexReward", "tryClaimIndexReward")
	self:addRemoteEventHandler("TryRefreshIndexData", "tryRefreshIndexData")
	self:addRemoteEventHandler("TryEquipVanityComponent", "tryEquipVanityComponent")
	self:addRemoteEventHandler("TryUnequipVanityPlacement", "tryUnequipVanityPlacement")
	self:addRemoteEventHandler("TryBuyVanityArea", "tryBuyVanityArea")
	self:addRemoteEventHandler("TryCheckGroup", "tryCheckGroup")
	self:addRemoteEventHandler("TryClaimWelcomeBackGift", "tryClaimWelcomeBackGift")
	self:addRemoteEventHandler("TryClaimLuckBillboard", "tryClaimLuckBillboard")
end

function GameController.processPollTimer(self: GameController): ()
	self.pollCount += 1

	local prevPollTime = self.latestPollTime
	self.latestPollTime = workspace:GetServerTimeNow()
	local elapsedSec = self.latestPollTime - prevPollTime

	local doResetTradeRequestCount = (self.pollCount % 60) == 0

	-- go through every crop getting eaten and make progress on it
	for _, crop in itemManager:getCropsGettingEaten() do
		local player = crop:getPlayer()
		local playerData = self:getPlayerData(player)
		if not playerData or not playerData:hasProfile() then
			continue
		end

		crop:tryStepGetEaten()
	end

	-- go through every idle crop and let them grow
	for _, crop in itemManager:getGrowingCrops() do
		local player = crop:getPlayer()
		local playerData = self:getPlayerData(player)
		if not playerData or not playerData:hasProfile() then
			continue
		end

		crop:tryGrow(elapsedSec)
	end

	for _, dragon in itemManager:getAllDragons() do
		local player = dragon:getPlayer()
		local playerData = self:getPlayerData(player)
		if not playerData or not playerData:hasProfile() then
			continue
		end

		dragon:tryStepUpdateStaminaAndFreeFlyZone()
	end

	for player, playerData in self.playerDatas do
		if not playerData:hasProfile() then
			continue
		end

		playerData:updatePlayerIsInPlot()

		incomeManager:tickPlayer(player, playerData, elapsedSec)

		if doResetTradeRequestCount then
			playerData:resetTradeRequestCount()
		end
	end

	for _, gem in itemManager:getAllGems() do
		local player = gem:getPlayer()
		local playerData = self:getPlayerData(player)
		if not playerData or not playerData:hasProfile() then
			return
		end

		gem:checkVacuum()
	end

	itemManager:checkItemsFallingTooLow()
end

function GameController.createPollTimer(self: GameController): ()
	--print("creating poll timer")
	self.pollTimer = Timer.new(1, function()
		local isSuccess, errorMessage = pcall(function()
			self:processPollTimer()
		end)
		if not isSuccess then
			warn("pollTimer error", errorMessage)
		end

		self:createPollTimer()
	end)
end

function GameController.run(self: GameController, deltaTime: number): ()
	for _, player in playersService:GetPlayers() do
		local playerData = self:getPlayerData(player)
		if not playerData then
			continue
		end

		playerData:checkPlayerFallingTooLow()
	end
end

function GameController.initCollision(self: GameController): ()
	physicsService:RegisterCollisionGroup(Constants.GEMS_COLLISION_GROUP)
	physicsService:RegisterCollisionGroup(Constants.NO_COLLIDE_GEMS_COLLISION_GROUP)

	physicsService:CollisionGroupSetCollidable(
		Constants.GEMS_COLLISION_GROUP,
		Constants.NO_COLLIDE_GEMS_COLLISION_GROUP,
		false
	)
end

function GameController.notifyUpdateGameConfigSnapshot(self: GameController): ()
	for player, playerData in self.playerDatas do
		playerData:notifyUpdateGameConfigSnapshot()
	end
end

function GameController.refreshGameConfig(self: GameController): ()
	self.gameConfigSnapshot:Refresh()
	self:notifyUpdateGameConfigSnapshot()
end

function GameController.loadGameConfig(self: GameController): ()
	local success, configSnapshot = pcall(function()
		return configService:GetConfigAsync()
	end)

	if success and configSnapshot then
		self.gameConfigSnapshot = configSnapshot

		configSnapshot.UpdateAvailable:Connect(function()
			print("config update available, refreshing")
			self:refreshGameConfig()
		end)
	else
		-- Handle failure (use fallback values, log error, etc.)
		local err = configSnapshot
		warn("Failed to load config, using default values", err)
		task.delay(5, function()
			print("trying to load config again")
			self:loadGameConfig()
		end)
	end
end

function GameController.getConfigValue(self: GameController, key: string): any
	if not (GameConfigKeys :: { [string]: string })[key] then
		warn("unknown config key", key)
		return nil
	end

	local value
	if self.gameConfigSnapshot then
		value = self.gameConfigSnapshot:GetValue(key)
	end

	if value == nil then
		-- we have a config value setup, but it's not in the production config
		warn("config key", key, "is missing in the config snapshot we have; using default value")
		return defaultGameConfigSnapshot[key]
	end

	return value
end

function GameController.isTradingEnabled(self: GameController): boolean
	return self:getConfigValue(GameConfigKeys.tradingEnabled)
end

function GameController.areChestIslandsEnabled(self: GameController): boolean
	return self:getConfigValue(GameConfigKeys.chestIslandsEnabled)
end

function GameController.isIndexEnabled(self: GameController): boolean
	-- indexEnabled is not yet registered in the remote ConfigService, so read the code-side
	-- default directly to avoid spamming "config value not found" warnings.
	return defaultGameConfigSnapshot[GameConfigKeys.indexEnabled]
end

function GameController.init(self: GameController): ()
	self.playerStore = ProfileStore.New(storageManager:getProfileDataStoreName(), PlayerData.getDefaultSaveData())

	self:loadGameConfig()

	analyticsManager:init()

	plotsManager:init()

	objectDataStore:init()

	gameDataVerifier:verifyAll()

	lootTableManager:init()

	self:initCollision()

	game.RunService.PreSimulation:Connect(function(deltaTime)
		self:run(deltaTime)
	end)

	game:BindToClose(function()
		print("server shutting down, waiting for", self.waitExitCount, "remaining things")
		while self.waitExitCount > 0 do
			task.wait()
		end

		print("server shutting down, removing", #playersService:GetPlayers(), "players")
		for player, playerData in self.playerDatas do
			self:processPlayerRemove(player)
		end
		if self.pollTimer then
			self.pollTimer:cancel()
		end
	end)

	buyStoreManager:init()
	codeManager:init()
	tradeManager:init()
	mutationStoreManager:init()
	vanityStoreManager:init()
	islandManager:init()
	stableManager:init()

	processReceipt:init()
	serverListener:init()

	self:listenToRemoteEvents()

	self:listenToPlayerEvents()

	self:createPollTimer()
end

function GameController.new(): GameController
	local self: GameController = setmetatable({
		random = Random.new(),

		gameConfig = nil,

		pollTimer = nil,
		latestPollTime = workspace:GetServerTimeNow(),
		pollCount = 0,

		playerDatas = {},

		waitExitCount = 0,

		remoteEventMetrics = {},
	} :: GameControllerFields, GameController)

	playersService.CharacterAutoLoads = false

	return self
end

-- this exists to avoid circular references on startup
local function initClasses(gameController: GameController): ()
	-- make sure everything in global scope gets run first, then we call init on everything
	task.wait()

	-- every module's deferred cross-singleton reference is handed in here instead of being
	-- require()d inside initClass, which keeps the static require graph acyclic for the type
	-- checker (all of these singletons were already loaded by this module's own requires above)
	local deps = {
		gameController = gameController,
		itemManager = itemManager,
		islandManager = islandManager,
		mutationStoreManager = mutationStoreManager,
		vanityStoreManager = vanityStoreManager,
	}

	Validate.initClass(deps)

	analyticsManager.initClass(deps)
	devTools.initClass(deps)
	customerTools.initClass(deps)
	indexManager.initClass(deps)
	islandManager.initClass(deps)
	plotsManager.initClass(deps)
	lootTableManager.initClass(deps)

	Item.initClass(deps)
	NumberItem.initClass(deps)

	Crop.initClass(deps)
	ShadowDragon.initClass(deps)
	Gem.initClass(deps)
	Crystal.initClass(deps)
	Pack.initClass(deps)
	Crate.initClass(deps)

	Node.initClass(deps)
	Chest.initClass(deps)
	Critter.initClass(deps)

	ItemMover.initClass(deps)
	PlayerData.initClass(deps)
	stableManager.initClass(deps)
	starterOfferManager.initClass(deps)
	ftueManager.initClass(deps)
	contextualFtueManager.initClass(deps)
	firstSessionOfferManager.initClass(deps)

	buyStoreManager.initClass(deps)
	codeManager.initClass(deps)
	tradeManager.initClass(deps)
	mutationStoreManager.initClass(deps)
	vanityStoreManager.initClass(deps)

	-- SellMixin and VerticalMixin no longer have an initClass, so the mixinData loop is gone
	mergeMixin.initClass(deps)
	pickupMixin.initClass(deps)
	rideMixin.initClass(deps)

	processReceipt.initClass(deps)
	-- this was previously a colon call, which passed serverListener itself as an ignored argument
	serverListener.initClass(deps)

	gameController:init()
end

local singleton = GameController.new()

itemManager.initMixins(mixinData)

local init = coroutine.wrap(function()
	initClasses(singleton)
end)
init()

return singleton
