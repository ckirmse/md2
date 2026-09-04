--!strict

local DevTools = {}
DevTools.__index = DevTools

local analyticsManager = require("./AnalyticsManager")
local buyStoreManager = require("./BuyStoreManager")
local contextualFtueManager = require("./ContextualFtueManager")
local vanityStoreManager = require("./VanityStoreManager")
local Types = require("./Types")
local gameController: Types.GameController
local indexManager = require("./IndexManager")
local itemManager = require("./ItemManager")
local mergeMixin = require("./MergeMixin")
local playerAttributesManager = require("./PlayerAttributesManager")
local plotsManager = require("./PlotsManager")
local rideMixin = require("./RideMixin")
local starterOfferManager = require("./StarterOfferManager")
local storageManager = require("./StorageManager")
local tradeManager = require("./TradeManager")
local Validate = require("./Validate")
local weatherManager = require("./WeatherManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")

local progressionData = require("@game/ServerScriptService/GameData/Control/Progression")
local startData = require("@game/ServerScriptService/GameData/Control/Start")

type DevToolsFields = {}

export type DevTools = typeof(setmetatable({} :: DevToolsFields, DevTools))

function DevTools.dumpServerTradingState(self: DevTools, player: Player)
	tradeManager:dumpState()
end

function DevTools.dumpIndexState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index unlocked items for", player)
	for itemName in playerData:getIndexDiscoveredItems() do
		print(itemName)
	end

	print("Index unlocked mutations for", player)
	for mutation in playerData:getIndexDiscoveredMutations() do
		print(enums.getPublicName(enums.Mutations, mutation))
	end
end

function DevTools.grantIndexStatBuff(self: DevTools, player: Player, attributeName: any, amount: any)
	local playerData = gameController:getPlayerData(player)
	playerData:grantIndexStatBuff(attributeName, amount)
end

function DevTools.dumpIndexStatBuffs(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index stat buffs for", player)
	for attributeName, buffAmount in playerData.indexStatBuffs do
		print(attributeName, "buff", buffAmount, "live value", playerData:getPlayerVariable(attributeName))
	end
end

function DevTools.grantIndexMutationChanceBuff(self: DevTools, player: Player, amount: any)
	local playerData = gameController:getPlayerData(player)
	playerData:grantIndexMutationChanceBuff(amount)
end

function DevTools.dumpIndexMutationChanceBuff(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	print("Index mutation chance buff for", player, playerData:getIndexMutationChancePercent())
	print("  time luck", playerData:getTimeLuckPercent())
	print("  friend luck", playerData:getFriendLuckPercent())
	print("  group luck", playerData:getGroupLuckPercent())
	print("  total luck / mutation chance", playerData:getLuckPercent())
end

function DevTools.tryClaimIndexReward(self: DevTools, player: Player, category: any, scope: any, chainKey: any, tierIndex: any)
	gameController:tryClaimIndexReward(player, category, scope, chainKey, tierIndex)
end

function DevTools.notifyIndexDataReset(self: DevTools, player: Player)
	RemoteEvents.NotifyIndexData:FireClient(player, indexManager:getFullIndexDataForPlayer(player))
end

function DevTools.resetIndexData(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexData()
	self:notifyIndexDataReset(player)
end

function DevTools.resetIndexRewards(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexRewards()
	self:notifyIndexDataReset(player)
end

function DevTools.resetIndexMutationData(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetIndexMutationData()
	self:notifyIndexDataReset(player)
end

function DevTools.discoverSpecificMutation(self: DevTools, player: Player, mutationTier: any)
	local playerData = gameController:getPlayerData(player)
	indexManager:notifyMutationDiscoveredIfNew(player, playerData, mutationTier)
	print("index discovered specific mutation", player, enums.getPublicName(enums.Mutations, mutationTier))
end

function DevTools.dumpIndexChains(self: DevTools, player: Player, category: any)
	print("Index chains for category", category)
	for chainIndex, chain in indexManager:getCategoryChains(category) do
		print(chainIndex, chain.chainKey, chain.itemNames or chain.abilities or chain.mutationTiers)
	end
end

function DevTools.dumpIndexMilestones(self: DevTools, player: Player, category: any, scope: any, chainKey: any)
	local playerData = gameController:getPlayerData(player)

	print("Index milestones for", category, scope, chainKey)
	for _, milestone in indexManager:getMilestones(playerData, category, scope, chainKey) do
		print(
			"tier", milestone.tierIndex,
			"percent", milestone.displayPercent,
			"threshold", milestone.threshold,
			"claimed", milestone.isClaimed,
			"claimable", milestone.isClaimable,
			"tierId", milestone.tierId
		)
	end
end

function DevTools.discoverIndexItemsForCategory(self: DevTools, player: Player, category: any, percent: any)
	local playerData = gameController:getPlayerData(player)

	local chains = indexManager:getCategoryChains(category)
	if #chains == 0 then
		warn("no discoverable items for index category", category)
		return
	end

	percent = math.clamp(percent, 0, 100)

	local newlyDiscoveredCount = 0
	local discoveredThisRun = 0
	for _, chain in chains do
		if chain.itemNames then
			local chainCount = math.ceil(#chain.itemNames * percent / 100)
			for i = 1, chainCount do
				local itemName = chain.itemNames[i]
				if not playerData:hasDiscoveredIndexItem(itemName) then
					newlyDiscoveredCount += 1
				end
				indexManager:notifyItemDiscoveredIfNew(player, playerData, itemName)
				discoveredThisRun += 1
			end
		elseif chain.mutationTiers then
			local chainCount = math.ceil(#chain.mutationTiers * percent / 100)
			for i = 1, chainCount do
				local mutation = chain.mutationTiers[i]
				if not playerData:hasDiscoveredIndexMutation(mutation) then
					newlyDiscoveredCount += 1
				end
				indexManager:notifyMutationDiscoveredIfNew(player, playerData, mutation)
				discoveredThisRun += 1
			end
		end
	end

	local totalDiscovered = 0
	for _ in playerData:getIndexDiscoveredItems() do
		totalDiscovered += 1
	end

	local totalDiscoveredMutations = 0
	for _ in playerData:getIndexDiscoveredMutations() do
		totalDiscoveredMutations += 1
	end

	print("index discover complete", player, category, percent .. "% per chain", "newly discovered", newlyDiscoveredCount, "of", discoveredThisRun, "total discovered", totalDiscovered, "total discovered mutations", totalDiscoveredMutations)
end

function DevTools.resetCoins(self: DevTools, player: Player)
	playerAttributesManager:set(player, PlayerAttributeKeys.COINS, startData.coins)
end

function DevTools.getCoins(self: DevTools, player: Player, amount: any)
	if not amount or amount < 1 then
		print("invalid coin amount to get", amount)
		return
	end
	amount = math.floor(amount)

	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, amount)
end

function DevTools.getGems(self: DevTools, player: Player, amount: any)
	if not amount or amount < 1 then
		print("invalid gem amount to get", amount)
		return
	end
	amount = math.floor(amount)

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end

		local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)

		playerAttributesManager:addWholeNumber(player, gemsKey, amount)
	end

end

function DevTools.dumpGems(self: DevTools, player: Player)
	print("Gems in wallet for", player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local gemsKey = Elements.getGemsKeyForPrimaryElement(primaryElement)
		print(" ", enums.getPublicName(enums.PrimaryElements, primaryElement), playerAttributesManager:get(player, gemsKey))
	end

	print("Gems on the ground for", player)
	for _, item in itemManager:getItemsOnGroundByUserId(player.UserId) do
		if item:getType() ~= "gem" then
			continue
		end

		local gem = item :: Types.NumberItem
		print(" ", item:getItemName(), "count", gem:getCount())
	end
end

function DevTools.resetPrimaryElementProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local xp = 0
		local playerAttributeKeyXp = Elements.getXpKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerAttributeKeyXp, xp)

		local level = 1
		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerAttributeKeyLevel, level)

		local playerDataKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerDataKeyIsUnlocked, primaryElement == enums.PrimaryElements.NATURE)

		local playerDataKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)
		playerAttributesManager:set(player, playerDataKeyGems, 0)
	end

	playerData:updateLevelsVisuals()

	playerData:trySetOption(PlayerOptionKeys.MERGE_ALL_ENABLED, false)
	RemoteEvents.NotifySetOptions:FireClient(player,
		{
			[PlayerOptionKeys.MERGE_ALL_ENABLED] = playerData:getOption(PlayerOptionKeys.MERGE_ALL_ENABLED),
		}
	)
	playerData:updatePlayerFeaturesInGuiData()

	playerData:resetAbilityStatuses()
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())

	playerData:updatePlayerVariables()
end

function DevTools.resetPurchasedSlotUnlocks(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetPurchasedSlotUnlocks()
end

function DevTools.addXp(self: DevTools, player: Player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end
		local xpDiff = 500
		gameController:addPrimaryElementXpToPlayer(player, primaryElement, xpDiff, (player.Character :: any).HumanoidRootPart)
	end
end

function DevTools.addLevel(self: DevTools, player: Player)
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = playerAttributesManager:get(player, isUnlockedKey)
		if not isUnlocked then
			continue
		end

		local playerAttributeKeyXp = Elements.getXpKeyForPrimaryElement(primaryElement)
		local xp = playerAttributesManager:get(player, playerAttributeKeyXp)

		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		local level = playerAttributesManager:get(player, playerAttributeKeyLevel)

		local isMaxLevel = (progressionData.nextLevelXp[level] == nil)
		if isMaxLevel then
			continue
		end

		local nextLevelXp = progressionData.nextLevelXp[level]
		local xpDiff = math.max(0, nextLevelXp - xp)

		gameController:addPrimaryElementXpToPlayer(player, primaryElement, xpDiff, (player.Character :: any).HumanoidRootPart)
	end
end

function DevTools.resetAllItems(self: DevTools, player: Player)
	itemManager:removeAllItemsForPlayer(player)
end

function DevTools.eraseSaveData(self: DevTools, player: Player)
	local slot = 0
	storageManager:erasePlayerGame(player, slot)
end

function DevTools.setIfSaveOnExit(self: DevTools, player: Player, doSaveOnExit: any)
	local playerData = gameController:getPlayerData(player)
	playerData:setIfSaveOnExit(doSaveOnExit)
end

function DevTools.loadSaveData(self: DevTools, player: Player, slot: any)
	self:resetCoins(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	local playerData = gameController:getPlayerData(player)


	local success, saveData = storageManager:loadPlayerGame(player, slot)
	if not success then
		playerData:setIfSaveOnExit(false)
		gameController:sendSystemMessageToPlayer(player, "Unsuccessful loading save state")
		return
	end

	print("loaded save data:", saveData)

	playerData:loadSaveData(saveData)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())
end

function DevTools.saveData(self: DevTools, player: Player, slot: any)
	local playerData = gameController:getPlayerData(player)

	local saveData = playerData:getSaveData()

	print("saving player to slot", slot)
	storageManager:savePlayerGame(player, saveData, slot)
end

function DevTools.loadSaveDataGlobal(self: DevTools, player: Player, globalName: any)
	self:resetCoins(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	local playerData = gameController:getPlayerData(player)

	local success, saveData = storageManager:loadPlayerGameGlobal(player, globalName)
	if not success then
		gameController:sendSystemMessageToPlayer(player, "Unsuccessful loading save state")
		playerData:setIfSaveOnExit(false)
		return
	end

	print("loaded save data:", saveData)

	playerData:loadSaveData(saveData)

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())

end

function DevTools.saveDataGlobal(self: DevTools, player: Player, globalName: any)
	local playerData = gameController:getPlayerData(player)

	local saveData = playerData:getSaveData()

	print("saving player to global name", globalName)
	storageManager:savePlayerGameGlobal(player, saveData, globalName)
end

function DevTools.addGemPile(self: DevTools, player: Player)
	local plotIndex = plotsManager:getPlotIndexByUserId(player.UserId) :: number

	local random = Random.new()
	for i = 1, 10 do
		local rawPlotPosition = Vector3.new(-10 + random:NextNumber(-3, 3), 0, -50 + random:NextNumber(-3, 3))
		local groundPosition = plotsManager:getGroundPositionFromPlotPosition(rawPlotPosition, plotIndex)
		local position = groundPosition + Vector3.new(0, i, 0)
		local item = itemManager:createItem("Green Gem", player.UserId)
		if not item then
			continue
		end
		local obj = item:getObj()
		obj.Position = position
		obj.Parent = workspace
	end
end

function DevTools.createItem(self: DevTools, player: Player, itemName: any)
	local playerData = gameController:getPlayerData(player)

	local item = itemManager:createItem(itemName, player.UserId)
	if not item then
		warn("unable to create item", itemName)
		return
	end

	local itemData = item:getItemData()
	if itemData.mixins.pickup then
		item:equip()
	else
		local position = (player.Character :: any).HumanoidRootPart.Position
		position += Vector3.new(0, 10, 0)

		item:getObj():PivotTo(CFrame.new(position))
		item:getObj().Parent = workspace

		if item.type == "shadowDragon" then
			-- have it pick a good height and go there
			local dragon = item :: Types.ShadowDragon
			dragon:notifyShouldMoveToIdleAtCurrentLocation()
		end
	end


	playerData:notifyItemReceived(item)

	analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
		{
			objectName = item:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
			rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
			itemType = item:getType(),
			acquisitionSource = "devTool",
		}
	)
end

function DevTools.createItemCount(self: DevTools, player: Player, itemName: any, count: any)
	count = math.clamp(count, 1, 1000)
	for i = 1, count do
		self:createItem(player, itemName)
	end
end

function DevTools.setVanityComponentNameAtPlacement(self: DevTools, player: Player, vanityPlacement: any, vanityComponentName: any)
	local playerData = gameController:getPlayerData(player)
	playerData:equipVanityComponentAtPlacement(vanityPlacement, vanityComponentName)
end

function DevTools.resetAllVanity(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetAllVanity()
end

function DevTools.restockBuyStoreRandom(self: DevTools, player: Player)
	buyStoreManager:restockRandom()
end

function DevTools.resetVanityDiscount(self: DevTools, player: Player)
	vanityStoreManager:resetDiscountForPlayer(player)
end

function DevTools.resetStarterOfferProgress(self: DevTools, player: Player)
	starterOfferManager:resetStarterOfferProgressForPlayer(player)
end

function DevTools.refillNodes(self: DevTools, player: Player)
	gameController:refillNodes()
end

function DevTools.restockIslands(self: DevTools, player: Player)
	gameController:restockIslands()
end

function DevTools.restockFixedIslands(self: DevTools, player: Player, islandName: any)
	gameController:restockFixedIslands(islandName)
end

function DevTools.setMutation(self: DevTools, player: Player, itemId: any, mutation: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot mutate item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item

	if not enums.isValidValue(enums.Mutations, mutation) then
		warn("invalid mutation, ignoring", mutation)
		return
	end

	if not itemManager:isMutationCapableType(item:getType()) then
		print("cannot set mutation of a non-mutatemod item", item)
		return
	end

	local mitem = item :: Types.MItem
	mitem:setMutation(mutation)
end

function DevTools.toggleModification(self: DevTools, player: Player, itemId: any, modification: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot modify item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item
	if not enums.isValidValue(enums.Modifications, modification) then
		warn("invalid modification, ignoring", modification)
		return
	end

	if not itemManager:isMutationCapableType(item:getType()) then
		print("cannot set modification of a non-mutatemod item", item)
		return
	end

	local mitem = item :: Types.MItem
	mitem:toggleModification(modification)
end

function DevTools.activateCrystal(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	local itemId = playerData:tryGetBestInstantOpenCrystalItemId(math.huge)
	if not itemId then
		print("no crystals to instant open")
		return
	end

	local item = itemManager:getItemById(itemId) :: Types.Crystal?
	if item then
		item:finishOpeningSuccessfully()
	end
end

function DevTools.resetFullPlayerState(self: DevTools, player: Player)
	self:resetCoins(player)
	self:resetPrimaryElementProgress(player)
	self:resetPurchasedSlotUnlocks(player)
	self:resetAllItems(player)
	self:resetStarterOfferProgress(player)
	self:restartFtueProgress(player)
	self:resetFirstSessionOfferState(player)
	self:resetAllVanity(player)

	self:resetCodesRedeemed(player)
	self:resetContextualFtueState(player)
	self:resetIndexData(player)

	local playerData = gameController:getPlayerData(player)
	playerData:resetStats()
	playerData:resetLuckBillboard()

	gameController:notifyPlayerLevelChanged(player)

	RemoteEvents.NotifyAllAttributes:FireClient(player, playerAttributesManager:getClientAttributesForPlayer(player))
	RemoteEvents.NotifyAbilityStatuses:FireClient(player, playerData:getAbilityStatuses())
end

function DevTools.resetCodesRedeemed(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)
	playerData:resetCodesRedeemed()
end

function DevTools.destroyItem(self: DevTools, player: Player, itemId: any)
	if not Validate.isItemIdForPlayer(player, itemId) then
		warn("dev tool cannot destroy item not owned by this player", itemId, player)
		return
	end

	-- isItemIdForPlayer above guarantees the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item

	local itemName = item:getItemName()
	local itemType = item:getType()
	local primaryElement = item:getItemData().primaryElement
	local rarity = item:getItemData().rarity

	itemManager:destroyItem(item)

	analyticsManager:logEvent(player, analyticsManager.Events.LoseItem,
		{
			objectName = itemName,
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
			rarity = enums.getPublicName(enums.Rarity, rarity),
			itemType = itemType,
			lossSource = "devTool",
		}
	)
end

function DevTools.addStamina(self: DevTools, player: Player)
	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if dragon then
		dragon:setOverrideMaxStamina(5000)
	end
end

function DevTools.setupStandardMerge(self: DevTools, player: Player, itemId: any)
	local item = itemManager:getItemById(itemId)

	local isEnhanced = false
	mergeMixin:createItemsToMergeWithItem(player, item, isEnhanced)
end

function DevTools.setupEnhancedMerge(self: DevTools, player: Player, itemId: any)
	local item = itemManager:getItemById(itemId)

	local isEnhanced = true
	mergeMixin:createItemsToMergeWithItem(player, item, isEnhanced)
end

function DevTools.fullyGrowCrops(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:growAllCrops()
end

function DevTools.goToIsland(self: DevTools, player: Player)
	local socialNode = gameController:getClosestNodeToPlayer(player)
	if not socialNode then
		return
	end

	local socialNodePosition = socialNode:getObj():GetPivot().Position
	local position = socialNodePosition + Vector3.new(0, 5, 0)

	local ridingDragon = if rideMixin:isPlayerRiding(player) then rideMixin:tryGetRidingDragonForPlayer(player) else nil
	if ridingDragon then
		ridingDragon:getObj():PivotTo(CFrame.new(position))
	else
		(player.Character :: any).HumanoidRootPart:PivotTo(CFrame.new(position))
	end
end

function DevTools.setEatFast(self: DevTools, player: Player, doEatFast: any)
	local playerData = gameController:getPlayerData(player)

	playerData:setDevToolSetting("eatFast", doEatFast)
end

function DevTools.goToPlot(self: DevTools, player: Player, plotIndex: any)
	-- a missing character or unknown plot crashed here before typing too
	(player.Character :: Model):PivotTo((PlotHelpers.getPlotCFrame(plotIndex) :: CFrame) + Vector3.new(0, 5, 0))
end

function DevTools.setUseBillboards(self: DevTools, player: Player, doUseBillboards: any)
	itemManager:setUseBillboards(doUseBillboards)
end

function DevTools.activateWeather(self: DevTools, player: Player, weatherName: any)
	weatherManager:beginWeatherName(weatherName, 60)
	weatherManager:sendWeatherAllPlayers()
end

function DevTools.deactivateWeather(self: DevTools, player: Player, weatherName: any)
	weatherManager:endWeatherName(weatherName)
	weatherManager:sendWeatherAllPlayers()
end

function DevTools.unlockPrimaryElement(self: DevTools, player: Player, primaryElement: any)
	local playerData = gameController:getPlayerData(player)

	playerData:unlockPrimaryElementIfNeeded(primaryElement)
end

function DevTools.lockPrimaryElement(self: DevTools, player: Player, primaryElement: any)
	local playerData = gameController:getPlayerData(player)

	local playerDataKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
	playerAttributesManager:set(player, playerDataKeyIsUnlocked, false)

	playerData:updateLevelsVisuals()
end

function DevTools.resetFtueProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetFtueProgress()

	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
end

function DevTools.restartFtueProgress(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:restartFtueProgress()

	RemoteEvents.NotifyFtueProgress:FireClient(player, playerData:getFtueProgress())
end

function DevTools.triggerContextualFtue(self: DevTools, player: Player, hintId: any)
	contextualFtueManager:tryTrigger(player, hintId)
end

function DevTools.resetContextualFtueState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetContextualFtueState()
end

function DevTools.resetFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetFirstSessionOfferState()

	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, playerData:getFirstSessionOfferState())
end

function DevTools.restartFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:restartFirstSessionOfferState()
end

function DevTools.setRedeemableFirstSessionOfferState(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:setRedeemableFirstSessionOfferState()
end


function DevTools.getRemoteEventMetrics(self: DevTools, player: Player)
	local remoteEventMetrics = gameController:getRemoteEventMetrics()

	RemoteEvents.NotifyRemoteEventMetrics:FireClient(player, remoteEventMetrics)
end

function DevTools.setPlayerVanityState(self: DevTools, player: Player, playerVanityState: any)
	if not enums.validateValue(enums.PlayerVanityState, playerVanityState) then
		print("invalid player vanity state", player, playerVanityState)
		return
	end

	local playerData = gameController:getPlayerData(player)

	playerData:setVanityState(playerVanityState)

end

function DevTools.resetPromptGroupTime(self: DevTools, player: Player)
	local playerData = gameController:getPlayerData(player)

	playerData:resetPromptGroupTime()
end

function DevTools.new(): DevTools
	local self: DevTools = setmetatable({} :: DevToolsFields, DevTools)

	return self
end

function DevTools.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = DevTools.new()

return singleton
