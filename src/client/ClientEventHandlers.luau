--!strict

local ClientEventHandlers = {}
ClientEventHandlers.__index = ClientEventHandlers

local collectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientAbilityStore = require("./ClientAbilityStore")
local clientAudioManager = require("./ClientAudioManager")
local clientBuyStore = require("./ClientBuyStore")
local clientClaimableCrystalManager = require("./ClientClaimableCrystalManager")
local clientConsumableCropManager = require("./ClientConsumableCropManager")
local clientContextualFtueManager = require("./ClientContextualFtueManager")
local clientCustomerTools = require("./ClientCustomerTools")
local clientDevTools = require("./ClientDevTools")
--local clientDragonManager = nil -- prevent circular reference by not initializing here
local clientExpansionTeleporter = require("./ClientExpansionTeleporter")
local clientFtueManager = require("./ClientFtueManager")
local clientFirstSessionOfferManager = require("./ClientFirstSessionOfferManager")
local clientIndexManager = require("./ClientIndexManager")
local clientMergeController = require("./ClientMergeController")
local clientMutationStore = require("./ClientMutationStore")
local clientNetopsTools = require("./ClientNetopsTools")
local clientNewBlueprintManager = require("./ClientNewBlueprintManager")
local clientNewMutationItemManager = require("./ClientNewMutationItemManager")
local clientNodeManager = require("./ClientNodeManager")
local clientOpenableCrateManager = require("./ClientOpenableCrateManager")
local clientOpenablePackManager = require("./ClientOpenablePackManager")
local clientOptionsManager = require("./ClientOptionsManager")
local clientPlayerManager = require("./ClientPlayerManager")
local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local clientPremiumStore = require("./ClientPremiumStore")
local clientLuckBillboardManager = require("./ClientLuckBillboardManager")
local clientPromptGroupManager = require("./ClientPromptGroupManager")
local clientRideController = require("./ClientRideController")
local clientSellStore = require("./ClientSellStore")
local clientTradePlayerList = require("./ClientTradePlayerList")
local clientTradeRequestedOverlay = require("./ClientTradeRequestedOverlay")
local clientTradingManager = require("./ClientTradingManager")
local clientWeatherManager = require("./ClientWeatherManager")
local clientWelcomeBackManager = require("./ClientWelcomeBackManager")
local clientXpDisplayManager = require("./ClientXpDisplayManager")
local screenGuiManager = require("./ScreenGuiManager")
local teleporters = require("./Teleporters")

local bufferedInitData: any = nil
local onInitDataReceived: any = nil

RemoteEvents.NotifyInit.OnClientEvent:Connect(function(initData)
	print("ClientEventHandlers: NotifyInit buffered at module scope (before init)")
	bufferedInitData = initData

	if onInitDataReceived then
		local initReceivedCallback = onInitDataReceived
		onInitDataReceived = nil
		task.spawn(initReceivedCallback, initData)
	end
end)

-- network message handlers

type ClientEventHandlersFields = {

}

export type ClientEventHandlers = typeof(setmetatable({} :: ClientEventHandlersFields, ClientEventHandlers))

function ClientEventHandlers.getOrWaitForObject(self: ClientEventHandlers, itemId: any)
	for _, obj in collectionService:GetTagged(Tags.ITEM) do
		if obj:GetAttribute(Attributes.ITEM_ID) == itemId then
			return obj
		end
	end

	-- on startup especially this can happen, but I've found it pretty rare as of 2025-october-7
	-- probably with multiple players it'll happen a lot more

	--print("WAITING for obj, wanted to see this", itemId)

	local event = Instance.new("BindableEvent")

	local instanceAddedConnect: RBXScriptConnection
	instanceAddedConnect = collectionService:GetInstanceAddedSignal(Tags.ITEM):Connect(function(obj)
		--print("obj added", obj)
		if obj:GetAttribute(Attributes.ITEM_ID) == itemId then
			--print("INSTANCE ADDED OF ITEM ID WE WERE WAITING FOR", itemId)
			instanceAddedConnect:Disconnect()

			event:Fire(obj)
		end
	end)

	return event.Event:Wait()
end

function ClientEventHandlers.init(self: ClientEventHandlers)
	--clientDragonManager = require("./ClientDragonManager")

	local function processInitData(initData: any)
		--print("client init received")

		local plotIndex = initData.plotIndex
		if not plotIndex then
			warn("NotifyInit: plotIndex is nil — home button and luck billboard will not work")
		end
		teleporters:setPlotIndex(plotIndex)

		task.spawn(function()
			clientExpansionTeleporter:handleNotifyInit(plotIndex)
		end)

		local plotCFrame = initData.plotCFrame
		if not plotCFrame then
			warn("NotifyInit: plotCFrame is nil — home button will not work")
		end
		teleporters:setPlotCFrame(plotCFrame)

		-- initialize some UI based on our data

		local buyStoreData = initData.buyStoreData
		if not buyStoreData then
			warn("NotifyInit: buyStoreData is nil — shop will not work")
		end
		clientBuyStore:setBuyStoreData(buyStoreData)

		local clientWeatherDatas = initData.clientWeatherDatas
		clientWeatherManager:setClientWeatherDatas(clientWeatherDatas)

		local devToolSettings = initData.devToolSettings
		if devToolSettings then
			clientDevTools:init(devToolSettings)
		end

		local options = initData.options
		clientOptionsManager:setData(options)

		local abilityStatuses = initData.abilityStatuses
		clientAbilityStore:setPlayerAbilityStatuses(abilityStatuses)

		local starterOfferData = initData.starterOfferData
		clientPremiumStore:initStarterOfferData(starterOfferData)

		local ftueProgress = initData.ftueProgress
		clientFtueManager:setFtueProgress(ftueProgress)

		local firstSessionOfferState = initData.firstSessionOfferState
		clientFirstSessionOfferManager:setFirstSessionOfferState(firstSessionOfferState)

		clientAudioManager:updateBackgroundMusicEnabled()
		clientAudioManager:updateBackgroundSoundEffectsEnabled()
		clientAudioManager:updateMainSoundEffectsEnabled()

		if initData.showLuckBillboard then
			clientLuckBillboardManager:showBillboard()
		end
	end

	if bufferedInitData then
		print("ClientEventHandlers: NotifyInit was buffered — processing now")
		task.spawn(processInitData, bufferedInitData)
	else
		print("ClientEventHandlers: waiting for NotifyInit")
		onInitDataReceived = processInitData
	end

	RemoteEvents.NotifyAllAttributes.OnClientEvent:Connect(function(playerAttributes)
		clientPlayerAttributesManager:setAll(playerAttributes)

		screenGuiManager:resetPlayerAttributeValues()
	end)

	RemoteEvents.NotifySystemMessage.OnClientEvent:Connect(function(systemMessage)
		--print("client received system message", systemMessage)

		screenGuiManager:showSystemMessage(systemMessage)
	end)

	RemoteEvents.NotifyMergeBeginStatus.OnClientEvent:Connect(function(isSuccess, consecutiveMergeCount, bestMutation)
		--print("client received merge begin status", isSuccess, consecutiveMergeCount, bestMutation)
		clientMergeController:notifyMergeBeginStatus(isSuccess, consecutiveMergeCount, bestMutation)
	end)

	RemoteEvents.NotifyMergeEnd.OnClientEvent:Connect(function()
		--print("client received merge end")
		clientMergeController:notifyMergeEnd()
	end)

	RemoteEvents.NotifySellStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received sell status", isSuccess)
		clientSellStore:notifySellStatus(isSuccess)
	end)

	RemoteEvents.NotifySummonDragonToEatStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received summon dragon to eat status", isSuccess)
		clientConsumableCropManager:notifySummonDragonToEatStatus(isSuccess)
	end)

	RemoteEvents.NotifyEatWhileRidingStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received eat while riding status", isSuccess)
		clientConsumableCropManager:notifyEatWhileRidingStatus(isSuccess)
	end)

	RemoteEvents.NotifyBuyStoreUpdate.OnClientEvent:Connect(function(buyStoreData, showUser)
		clientBuyStore:setBuyStoreData(buyStoreData)
		if showUser then
			screenGuiManager:showSystemMessage("Plant and Dragon shop restocked")
		end
	end)

	RemoteEvents.NotifyWeatherUpdate.OnClientEvent:Connect(function(clientWeatherDatas)
		--print("weather update", clientWeatherDatas)
		clientWeatherManager:setClientWeatherDatas(clientWeatherDatas)
	end)

	RemoteEvents.NotifyPlayerAttributeChange.OnClientEvent:Connect(function(playerDataKey, value)
		local prevValue = clientPlayerAttributesManager:get(playerDataKey)
		clientPlayerAttributesManager:set(playerDataKey, value)

		if playerDataKey == PlayerAttributeKeys.COINS then
			screenGuiManager:notifyCoinValueChange(prevValue, value)
			clientBuyStore:notifyPlayerCoinsChanged()
		elseif
			playerDataKey == PlayerAttributeKeys.IS_UNLOCKED_FIRE
			or playerDataKey == PlayerAttributeKeys.IS_UNLOCKED_NATURE
			or playerDataKey == PlayerAttributeKeys.IS_UNLOCKED_WATER
			or playerDataKey == PlayerAttributeKeys.IS_UNLOCKED_AIR
		then
			-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
			-- screenGuiManager:resetGems()
		elseif
			playerDataKey == PlayerAttributeKeys.LEVEL_FIRE
			or playerDataKey == PlayerAttributeKeys.LEVEL_NATURE
			or playerDataKey == PlayerAttributeKeys.LEVEL_WATER
			or playerDataKey == PlayerAttributeKeys.LEVEL_AIR
		then
			clientBuyStore:notifyPlayerLevelChanged()
			clientAbilityStore:notifyPlayerLevelChanged()
		elseif
			playerDataKey == PlayerAttributeKeys.XP_FIRE
			or playerDataKey == PlayerAttributeKeys.XP_NATURE
			or playerDataKey == PlayerAttributeKeys.XP_WATER
			or playerDataKey == PlayerAttributeKeys.XP_AIR
		then
			-- pass
		elseif
			playerDataKey == PlayerAttributeKeys.GEMS_FIRE
			or playerDataKey == PlayerAttributeKeys.GEMS_NATURE
			or playerDataKey == PlayerAttributeKeys.GEMS_WATER
			or playerDataKey == PlayerAttributeKeys.GEMS_AIR
		then
			local primaryElement = Elements.getPrimaryElementByGemsKey(playerDataKey)
			-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
			-- screenGuiManager:notifyGemsValueChange(primaryElement, prevValue, value)

			clientFtueManager:notifyGemsValueChange(primaryElement, prevValue, value)
		else
			--print("client doesn't know or care about update to playerDataKey", playerDataKey)
		end
	end)

	RemoteEvents.NotifyXpGrant.OnClientEvent:Connect(function(primaryElement, xpDiff, position)
		--print("client should show xp diff +", xpDiff, "at", position)

		clientXpDisplayManager:addXpTextDisplay(primaryElement, xpDiff, position)
	end)

	RemoteEvents.NotifyLevelGrant.OnClientEvent:Connect(function(primaryElement, level)
		--print("client should show new level", level)

		local primaryElementName = enums.getPublicName(enums.PrimaryElements, primaryElement) :: string

		local color = utils.get2DColorForPrimaryElement(primaryElement)
		local colorStr = color:ToHex()

		screenGuiManager:showSystemMessage(
			string.format('You are now level %i in <font color="#%s">%s</font>', level, colorStr, primaryElementName)
		)
	end)

	RemoteEvents.NotifyClaimCrystalStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received claim crystal status", isSuccess)
		clientClaimableCrystalManager:notifyClaimCrystalStatus(isSuccess)
	end)

	RemoteEvents.NotifySummonDragonToMineStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received summon dragon to mine status", isSuccess)
		clientNodeManager:notifySummonDragonToMineStatus(isSuccess)
	end)

	RemoteEvents.NotifyMineWhileRidingStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received mine while riding status", isSuccess)
		clientRideController:notifyMineWhileRidingStatus(isSuccess)
	end)

	RemoteEvents.NotifyShootFireballAtCropStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received shoot fireball at crop status", isSuccess)
		clientRideController:notifyShootFireballAtCropStatus(isSuccess)
	end)

	RemoteEvents.NotifyShootFireballAtCritterStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received shoot fireball at critter status", isSuccess)
		clientRideController:notifyShootFireballAtCritterStatus(isSuccess)
	end)

	RemoteEvents.NotifyBuyStatus.OnClientEvent:Connect(function(isSuccess, purchases)
		--print("client received buy status", isSuccess, purchases)
		clientBuyStore:notifyBuyStatus(isSuccess, purchases)
	end)

	RemoteEvents.NotifyBuyMaxStatus.OnClientEvent:Connect(function(successCount, purchases)
		--print("client received buy max status", successCount, purchases)
		clientBuyStore:notifyBuyMaxStatus(successCount, purchases)
	end)

	RemoteEvents.NotifyOpenPackStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received open pack status", isSuccess)
		clientOpenablePackManager:notifyOpenPackStatus(isSuccess)
	end)

	RemoteEvents.NotifyOpenCrateStatus.OnClientEvent:Connect(function(isSuccess)
		clientOpenableCrateManager:notifyOpenCrateStatus(isSuccess)
	end)

	RemoteEvents.NotifyStopRiding.OnClientEvent:Connect(function()
		--print("client received stop riding")
		clientRideController:notifyStopRiding()
	end)

	RemoteEvents.NotifyAbilityStatuses.OnClientEvent:Connect(function(abilityStatuses)
		--print("got new ability statuses")

		clientAbilityStore:notifyAbilityStatuses(abilityStatuses)
		clientIndexManager:notifyAbilityStatuses(abilityStatuses)
	end)

	RemoteEvents.NotifyIndexData.OnClientEvent:Connect(function(indexData)
		clientIndexManager:notifyIndexData(indexData)
	end)

	RemoteEvents.NotifyIndexItemDiscovered.OnClientEvent:Connect(function(category, chainKey, itemName)
		clientIndexManager:notifyItemDiscovered(category, chainKey, itemName)
	end)

	RemoteEvents.NotifyIndexMutationDiscovered.OnClientEvent:Connect(function(mutationTier)
		clientIndexManager:notifyMutationDiscovered(mutationTier)
	end)

	RemoteEvents.NotifyClaimIndexRewardStatus.OnClientEvent:Connect(function(isSuccess, category, scope, chainKey, tierId, milestoneViewModels)
		clientIndexManager:notifyClaimStatus(isSuccess, category, scope, chainKey, tierId, milestoneViewModels)
	end)

	RemoteEvents.NotifyIndexDataRefreshed.OnClientEvent:Connect(function(refreshedData)
		clientIndexManager:notifyIndexDataRefreshed(refreshedData)
	end)

	RemoteEvents.NotifyIndexHasClaimableReward.OnClientEvent:Connect(function()
		clientIndexManager:notifyHasClaimableReward()
	end)

	RemoteEvents.NotifyCustomerToolData.OnClientEvent:Connect(function(messageText, userId, userName, customerData)
		clientCustomerTools:notifyData(messageText, userId, userName, customerData)
	end)

	RemoteEvents.NotifyPlayerRidingStatus.OnClientEvent:Connect(function(userId, isRiding)
		clientPlayerManager:notifyUserRidingStatus(userId, isRiding)
	end)

	RemoteEvents.NotifyEquipAbilityStatus.OnClientEvent:Connect(function(isSuccess)
		--print("got equip ability status", isSuccess)

		clientAbilityStore:notifyEquipAbilityStatus(isSuccess)
	end)

	RemoteEvents.NotifyUpdatePurchasedSlotUnlocks.OnClientEvent:Connect(function()
		--print("got update purchased slot unlock")

		clientAbilityStore:notifyUpdatePurchasedSlotUnlocks()
	end)

	RemoteEvents.NotifyEndStarterOffer.OnClientEvent:Connect(function()
		--print("got end starter offer data")

		clientPremiumStore:notifyEndStarterOffer()
	end)

	RemoteEvents.NotifyFtueProgress.OnClientEvent:Connect(function(ftueProgress)
		--print("got ftue progress")

		clientFtueManager:setFtueProgress(ftueProgress)
	end)

	RemoteEvents.NotifyContextualFtueTriggered.OnClientEvent:Connect(function(hintId)
		clientContextualFtueManager:notifyHintTriggered(hintId)
	end)

	RemoteEvents.NotifyRemoteEventMetrics.OnClientEvent:Connect(function(remoteEventMetrics)
		clientNetopsTools:notifyRemoteEventMetrics(remoteEventMetrics)
	end)

	RemoteEvents.NotifyBeginRideDragonStatus.OnClientEvent:Connect(function(isSuccess)
		--print("client received begin ride dragon status", isSuccess)
		clientRideController:notifyBeginRideDragonStatus(isSuccess)
	end)

	RemoteEvents.NotifyTrySetRidingCFrameRejected.OnClientEvent:Connect(function(ridingCFrame)
		print("client received set riding cframe rejected", ridingCFrame)
		clientRideController:notifyTrySetRidingCFrameRejected(ridingCFrame)
	end)

	RemoteEvents.NotifyFirstSessionOfferState.OnClientEvent:Connect(function(firstSessionOfferState)
		--print("got first session offer state")

		clientFirstSessionOfferManager:setFirstSessionOfferState(firstSessionOfferState)
	end)

	RemoteEvents.NotifyRequestBeginTradeStatus.OnClientEvent:Connect(function(playerName, isSuccess)
		--print("client received request begin trade status", playerName, isSuccess)

		clientTradePlayerList:notifyRequestBeginTradeStatus(playerName, isSuccess)
	end)
	RemoteEvents.NotifyBeginTradeRequested.OnClientEvent:Connect(function(playerName)
		--print("got begin trade requested")

		clientTradeRequestedOverlay:notifyBeginTradeRequested(playerName)
		clientTradePlayerList:notifyBeginTradeRequested()
	end)

	RemoteEvents.NotifyBeginTradeStatus.OnClientEvent:Connect(function(playerName, doesAccept)
		--print("got begin trade status")

		clientTradingManager:notifyBeginTradeStatus(playerName, doesAccept)
	end)

	RemoteEvents.NotifyTradePartnerOffer.OnClientEvent:Connect(function(playerName, partnerOffer)
		--print("got trade partner offer")

		clientTradingManager:notifyTradePartnerOffer(playerName, partnerOffer)
	end)

	RemoteEvents.NotifyTradePartnerRemoveOffer.OnClientEvent:Connect(function(playerName)
		--print("got trade partner remove offer")

		clientTradingManager:notifyTradePartnerRemoveOffer(playerName)
	end)

	RemoteEvents.NotifyTradePartnerAccepted.OnClientEvent:Connect(function(playerName)
		--print("got trade partner accepted")

		clientTradingManager:notifyTradePartnerAccepted(playerName)
	end)

	RemoteEvents.NotifyTradePartnerConfirmed.OnClientEvent:Connect(function(playerName)
		--print("got trade partner confirmed")

		clientTradingManager:notifyTradePartnerConfirmed(playerName)
	end)

	RemoteEvents.NotifyCancelTrade.OnClientEvent:Connect(function(playerName)
		--print("got cancel trade")

		clientTradeRequestedOverlay:notifyCancelTrade(playerName)
		clientTradingManager:notifyCancelTrade(playerName)
	end)

	RemoteEvents.NotifyTradeComplete.OnClientEvent:Connect(function(playerName)
		--print("got trade complete")

		clientTradingManager:notifyTradeComplete(playerName)
	end)

	RemoteEvents.NotifyBlueprintFanfare.OnClientEvent:Connect(function(itemName, rarity)
		--print("got blueprint fanfare")

		clientNewBlueprintManager:notifyNewBlueprint(itemName, rarity)
	end)

	RemoteEvents.NotifyItemRevealFanfare.OnClientEvent:Connect(
		function(text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition)
			clientNewMutationItemManager:notifyNewMutationItem(
				text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition
			)
		end
	)

	RemoteEvents.NotifyMutationStorePurchase.OnClientEvent:Connect(
		function(text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition)
			--print("got mutation store purchase")

			clientMutationStore:notifyMutationStorePurchase(
				text,
				templatePath,
				mutation,
				mutationSurfaceAppearanceName,
				cameraPosition
			)
		end
	)

	RemoteEvents.NotifyPromptGroup.OnClientEvent:Connect(function()
		--print("got prompt group")

		clientPromptGroupManager:notifyPromptGroup()
	end)

	RemoteEvents.NotifyShowLuckBillboard.OnClientEvent:Connect(function()
		clientLuckBillboardManager:showBillboard()
	end)

	RemoteEvents.NotifyLuckBillboardResult.OnClientEvent:Connect(function(isInGroup)
		--print("got luck billboard result", isInGroup)

		clientLuckBillboardManager:notifyLuckBillboardResult(isInGroup)
	end)

	RemoteEvents.NotifyIsInPlot.OnClientEvent:Connect(function(isInPlot)
		--print("got is in plot")

		clientMergeController:notifyIsInPlot(isInPlot)
	end)

	RemoteEvents.NotifySetOptions.OnClientEvent:Connect(function(options)
		--print("got options")

		clientOptionsManager:setData(options)
	end)

	RemoteEvents.NotifyWelcomeBackGift.OnClientEvent:Connect(function(coinCount)
		--print("got welcomeBackGift")

		clientWelcomeBackManager:beginDialog(coinCount)
	end)
end

function ClientEventHandlers.new(): ClientEventHandlers
	local self = setmetatable({} :: ClientEventHandlersFields, ClientEventHandlers)

	return self
end

local singleton = ClientEventHandlers.new()

return singleton
