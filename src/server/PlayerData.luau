--!strict

local PlayerData = {}
PlayerData.__index = PlayerData

local playersService = game:GetService("Players")
local tweenService = game:GetService("TweenService")

local Types = require("./Types")
local contextualFtueManager = require("./ContextualFtueManager")
local Crystal = require("./Crystal")
local firstSessionOfferManager = require("./FirstSessionOfferManager")
local ftueManager = require("./FtueManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager = require("./ItemManager")
local objectDataStore = require("./ObjectDataStore")
local plotsManager = require("./PlotsManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Gnomes = GameAssets:WaitForChild("Gnomes")
local Level = workspace:WaitForChild("Level")
local ClonedPlotElements = Level:WaitForChild("ClonedPlotElements")

local Abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local GameConfigKeys = require("@game/ReplicatedStorage/Shared/GameConfigKeys")
local indexCatalog = require("@game/ReplicatedStorage/Shared/IndexCatalog")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local abilityValuesData = require("@game/ServerScriptService/GameData/Control/AbilityValues")
local crystalTimeData = require("@game/ServerScriptService/GameData/Control/CrystalTime")
local capacityData = require("@game/ServerScriptService/GameData/Control/Capacity")
local luckData = require("@game/ServerScriptService/GameData/Control/Luck")
local offlineHarvestingData = require("@game/ServerScriptService/GameData/Control/OfflineHarvesting")
local progressionData = require("@game/ServerScriptService/GameData/Control/Progression")
local vanityAreasData = require("@game/ServerScriptService/GameData/Control/VanityAreas")

local analyticsManager = require("./AnalyticsManager")
local indexManager = require("./IndexManager")
local playerAttributesManager = require("./PlayerAttributesManager")
local rideMixin = require("./RideMixin")
local Timer = require("./Timer")
local Validate = require("./Validate")
local mutationStoreManager = require("./MutationStoreManager")
local vanityStoreManager = require("./VanityStoreManager")
local weatherDataStore = require("./WeatherDataStore")

local ADMIN_GROUP_ID = 571203718

local COMMUNITY_GROUP_ID = 114515609

local CAPACITY_SIGN_NAME = "CapacitySign"

-- nearly all of this state is heterogeneous persisted save data, so the fields stay untyped
type PlayerDataFields = {
	player: Player,
	profile: any,
	saveOnExit: boolean,
	canUseDevTools: boolean,
	sessionStartTime: number,
	stats: any,
	options: any,
	playerVariables: any,
	devToolSettings: any,
	friendUserIds: any,
	instantOpenCrystalItemIds: any,
	abilityStatuses: any,
	stableSlots: any,
	totalDragonPower: number,
	ftueProgress: any,
	contextualFtueState: any,
	firstSessionOfferState: any,
	starterOfferProgress: any,
	buyStorePurchases: any,
	codesRedeemed: any,
	mergeData: any,
	ridingItemId: any,
	latestRidingItemId: any,
	playerRelativeToDragonCFrame: any,
	isInPlot: boolean,
	isInCommunityGroup: boolean,
	hasClaimedGroupLuck: boolean,
	luckTimer: any,
	latestPromptGroupTime: number,
	tradeRequestCount: number,
	pendingWelcomeBackCoinCount: number,
	purchasedSlotUnlocks: any,
	vanityState: any,
	vanityPlacements: any,
	vanityComponentStates: any,
	vanityAreaStates: any,
	indexDiscoveredItems: any,
	indexDiscoveredMutations: any,
	indexClaimedRewards: any,
	indexStatBuffs: any,
	indexMutationChancePercent: number,
	lastIndexRefreshTime: number,
	hasBackfilledBlueprintIndex: boolean,
}

export type PlayerData = typeof(setmetatable({} :: PlayerDataFields, PlayerData))

local function vanityComponentNameCompare(a: any, b: any): boolean
	local vanityComponentDataA = plotsManager:getVanityComponentDataByName(a)
	local vanityComponentDataB = plotsManager:getVanityComponentDataByName(b)
	if vanityComponentDataA.rarity < vanityComponentDataB.rarity then
		return true
	end
	if vanityComponentDataA.rarity > vanityComponentDataB.rarity then
		return false
	end

	return a < b
end

local function devToolItemCompare(a: any, b: any): boolean
	local itemDataA = objectDataStore:getObjectDataByName(a)
	local itemDataB = objectDataStore:getObjectDataByName(b)
	if itemDataA.primaryElement and itemDataB.primaryElement then
		if
			Elements.getSortIndexForPrimaryElement(itemDataA.primaryElement)
			< Elements.getSortIndexForPrimaryElement(itemDataB.primaryElement)
		then
			return true
		end
		if
			Elements.getSortIndexForPrimaryElement(itemDataA.primaryElement)
			> Elements.getSortIndexForPrimaryElement(itemDataB.primaryElement)
		then
			return false
		end
	end

	-- check by level
	if itemDataA.level and itemDataB.level then
		if itemDataA.level < itemDataB.level then
			return true
		end
		if itemDataA.level > itemDataB.level then
			return false
		end
	end

	-- check crop vs dragon
	if itemDataA.type == "crop" and itemDataB.type ~= "crop" then
		return true
	end
	if itemDataA.type ~= "crop" and itemDataB.type == "crop" then
		return false
	end

	-- last gasp to distinguish them
	return a < b
end

local function devToolIslandCompare(a: any, b: any): boolean
	return a < b
end

function PlayerData.setIfSaveOnExit(self: PlayerData, saveOnExit: any)
	self.saveOnExit = saveOnExit
end

function PlayerData.shouldSaveOnExit(self: PlayerData)
	return self.saveOnExit
end

function PlayerData.hasDevToolAccess(self: PlayerData)
	return self.canUseDevTools
end

function PlayerData.getPlayerMaxCapacity(self: PlayerData)
	local maxCapacity = capacityData.itemCapacitySoftMax

	-- check expansions
	local expansionVanityAreas = PlotHelpers.getExpansionVanityAreas()
	for _, vanityArea in expansionVanityAreas do
		if not capacityData.vanityAreaCapacity[vanityArea] then
			continue
		end

		maxCapacity += capacityData.vanityAreaCapacity[vanityArea]
	end

	return maxCapacity
end

function PlayerData.getPlayerCapacityUsed(self: PlayerData)
	local itemPlotCapacityUsed = 0

	local items = itemManager:getItemsOnGroundByUserId(self.player.UserId)
	for _, item in items do
		local capacityCost = item:getCapacityCost()
		itemPlotCapacityUsed += capacityCost
	end

	return itemPlotCapacityUsed
end

function PlayerData.updateCapacityDisplay(self: PlayerData)
	local Level = workspace:WaitForChild("Level")

	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)

	local maxCapacity = self:getPlayerMaxCapacity()
	local itemPlotCapacityUsed = self:getPlayerCapacityUsed()

	--print("plot capacity", itemPlotCapacityUsed, maxCapacity)

	local fillFrac = math.min(1, itemPlotCapacityUsed / maxCapacity)

	-- a missing capacity sign crashed here before typing too
	local capacitySign: any =
		utils.findFirstDescendantWithNameAndAttribute(Level, CAPACITY_SIGN_NAME, Attributes.INDEX, plotIndex)
	capacitySign:SetAttribute("CapacityUsed", itemPlotCapacityUsed)
	capacitySign:SetAttribute("CapacityMax", maxCapacity)

	-- a malformed capacity sign crashed here before typing too, so the casts keep that behavior
	local fill = utils.findFirstDescendant(capacitySign, "Fill") :: GuiObject
	fill.Size = UDim2.new(UDim.new(fillFrac, 0), fill.Size.Y)

	local fillBack = utils.findFirstDescendant(capacitySign, "Back") :: Instance
	local fillBorder = utils.findFirstDescendant(fillBack, "UIStroke") :: UIStroke

	local color
	if fillFrac < 0.6 then
		color = Color3.fromRGB(0, 249, 0)
	elseif fillFrac < 0.9 then
		color = Color3.fromRGB(255, 147, 0)
	else
		color = Color3.fromRGB(255, 38, 0)
	end

	local tweenInfo = TweenInfo.new(0.3)
	local goal: any
	local tween

	goal = { BackgroundColor3 = color }
	tween = tweenService:Create(fill, tweenInfo, goal)
	tween:Play()

	goal = { Color = color }
	tween = tweenService:Create(fillBorder, tweenInfo, goal)
	tween:Play()
end

function PlayerData.notifyItemAddedToWorkspace(self: PlayerData, item: any)
	self:updateCapacityDisplay()
end

function PlayerData.notifyItemRemovedFromWorkspace(self: PlayerData, item: any)
	self:updateCapacityDisplay()
end

function PlayerData.isAtOrAboveCapacity(self: PlayerData)
	local maxCapacity = self:getPlayerMaxCapacity()
	local itemPlotCapacityUsed = self:getPlayerCapacityUsed()
	return itemPlotCapacityUsed >= maxCapacity
end

function PlayerData.notifyItemReceived(self: PlayerData, receivedItem: any)
	-- receivedItem could have gotten merged into a number item we already had, so look it up;
	-- if the player doesn't have it yet, then the receivedItem is on its way there
	local item = self:getItemForPlayer(receivedItem.itemName) or receivedItem

	if item:getType() == "key" or item:getType() == "blueprint" then
		self:unlockPlayerVanityStateIfNeeded()
	end

	if item:getType() == "blueprint" then
		indexManager:notifyItemDiscoveredIfNew(self.player, self, item:getItemName())

		-- we now check to see if it's a new one to fanfare
		if item:getCount() == 1 then
			-- see what it unlocks and if it's already unlocked
			local vanityComponentName = plotsManager:getVanityComponentNameForBlueprintName(item:getItemName())
			if vanityComponentName then
				if self:isVanityComponentLocked(vanityComponentName) then
					-- just got our first blueprint of something that's locked
					RemoteEvents.NotifyBlueprintFanfare:FireClient(
						self.player,
						item:getItemData().displayName,
						item:getItemData().rarity
					)
				end
			else
				warn("got a blueprint that has no vanity component", self.player, item:getItemName())
			end
		end
	end

	-- unlock element if needed
	local primaryElement = item:getItemData().primaryElement
	if primaryElement and primaryElement ~= enums.PrimaryElements.NONE then
		self:unlockPrimaryElementIfNeeded(primaryElement)
	end

	-- contextual FTUE: explain flying the first time the player receives a level 4+ dragon
	local level = item:getItemData().level
	if item:getType() == "shadowDragon" and level and level >= 4 then
		contextualFtueManager:tryTrigger(self.player, "flyingUnlocked")
	end
end

function PlayerData.notifyReceivedMutation(self: PlayerData)
	local now = workspace:GetServerTimeNow()

	-- no need to prompt, they're in the group
	if self.isInCommunityGroup then
		return
	end

	-- only prompt to join community once per 24 hours
	if (now - self.latestPromptGroupTime) < 24 * 60 * 60 then
		return
	end

	self.latestPromptGroupTime = now

	RemoteEvents.NotifyPromptGroup:FireClient(self.player)

	analyticsManager:logEvent(self.player, analyticsManager.Events.PromptGroup, {})
end

function PlayerData.isLocationInPlotOrUnlockedExpansions(self: PlayerData, location: Vector3)
	local isPositionSafe = false

	-- check expansions
	local expansionVanityAreas = PlotHelpers.getExpansionVanityAreas()
	for _, vanityArea in expansionVanityAreas do
		if self.vanityAreaStates[vanityArea] == enums.VanityAreaState.UNLOCKED then
			if not plotsManager:isPositionInExpansionXZByUserId(location, vanityArea, self.player.UserId) then
				continue
			end

			isPositionSafe = true
			break
		end
	end

	if plotsManager:isPositionInMainPlotXZByUserId(location, self.player.UserId) then
		isPositionSafe = true
	end

	return isPositionSafe
end

function PlayerData.doAllowActivateItem(self: PlayerData, item: any): boolean
	local maxCapacity = self:getPlayerMaxCapacity()
	local itemPlotCapacityUsed = self:getPlayerCapacityUsed()

	--print("capacity used at", itemPlotCapacityUsed, "max", maxCapacity)

	-- if it's a held item, its position is useful. If it's still in the backpack, then it's trash (level 4+ dragons can't be held)
	-- so we check the player's position instead (this is a change on 2026-june-18)
	if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local position = (self.player.Character :: any).HumanoidRootPart.Position
	local isPositionSafe = self:isLocationInPlotOrUnlockedExpansions(position)

	if not isPositionSafe then
		gameController:sendSystemMessageToPlayer(self.player, "You can only place objects in your own plot")
		return false
	end

	if itemPlotCapacityUsed >= maxCapacity then
		gameController:sendSystemMessageToPlayer(self.player, "Your plot is too full to put anything else in it")
		return false
	end

	return true
end

function PlayerData.getTotalLevel(self: PlayerData)
	local totalLevel = 0

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local primaryElementData = Elements.getDataForPrimaryElement(primaryElement) :: any

		if not playerAttributesManager:get(self.player, primaryElementData.isUnlockedKey) then
			continue
		end

		local level = playerAttributesManager:get(self.player, primaryElementData.levelKey)
		totalLevel += level
	end

	return totalLevel
end

function PlayerData.updateLeaderboardData(self: PlayerData)
	local totalLevel = self:getTotalLevel()

	-- missing leaderstats crashed here before typing too
	local leaderstats: any = self.player:FindFirstChild("leaderstats")
	local totalLevelStat = leaderstats:FindFirstChild("Total Level")
	if totalLevelStat then
		totalLevelStat.Value = totalLevel
	else
		totalLevelStat = Instance.new("IntValue")
		totalLevelStat.Name = "Total Level"
		totalLevelStat.Value = totalLevel
		totalLevelStat.Parent = leaderstats
	end
end

function PlayerData.initLeaderboardData(self: PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = self.player
end

function PlayerData.initLuck(self: PlayerData)
	self:createLuckTimerIfNeeded()
end

function PlayerData.createLuckTimerIfNeeded(self: PlayerData)
	local _, rangeEndTime = self:getLuckTimeRange()
	if rangeEndTime then
		--print("making timer", rangeEndTime - workspace:getServerTimeNow())
		self.luckTimer = Timer.new(rangeEndTime - workspace:GetServerTimeNow(), function()
			--print("timer went off")
			self.luckTimer = nil

			local isSuccess, errorMessage = pcall(function()
				self:updateLuckInGuiData()
			end)
			if not isSuccess then
				warn("luckTimer error", errorMessage)
			end

			self:createLuckTimerIfNeeded()
		end)
	end
end

function PlayerData.getTimeLuckPercent(self: PlayerData)
	local sessionSec = workspace:GetServerTimeNow() - self.sessionStartTime
	local timeLuck = 0
	for _, sessionTimeData in luckData.sessionTime do
		if sessionSec < sessionTimeData.duration then
			break
		end

		timeLuck = sessionTimeData.percent
	end

	return timeLuck
end

function PlayerData.getFriendLuckPercent(self: PlayerData)
	local friendLuck = luckData.percentPerFriend * utils.getTableSize(self.friendUserIds)

	return math.min(friendLuck, luckData.maxFriendLuckPercent)
end

function PlayerData.getGroupLuckPercent(self: PlayerData)
	local groupLuck = 0
	if self.isInCommunityGroup then
		groupLuck = 30
	end

	return groupLuck
end

function PlayerData.getIndexMutationChancePercent(self: PlayerData)
	return self.indexMutationChancePercent
end

function PlayerData.getLuckPercent(self: PlayerData)
	local totalLuck = self:getTimeLuckPercent() + self:getFriendLuckPercent() + self:getGroupLuckPercent() + self:getIndexMutationChancePercent()

	return totalLuck
end

function PlayerData.getLuckTimeRange(self: PlayerData)
	local sessionSec = workspace:GetServerTimeNow() - self.sessionStartTime
	local beginTime = self.sessionStartTime
	local endTime
	for _, sessionTimeData in luckData.sessionTime do
		if sessionSec < sessionTimeData.duration then
			endTime = self.sessionStartTime + sessionTimeData.duration
			break
		end

		beginTime = self.sessionStartTime + sessionTimeData.duration
	end

	if not endTime then
		beginTime = nil :: any
	end

	--print("luck time range", beginTime, endTime)

	return beginTime, endTime
end

function PlayerData.updateCommunityGroupData(self: PlayerData)
	local isSuccess, result = pcall(function()
		return self.player:IsInGroupAsync(COMMUNITY_GROUP_ID)
	end)

	local isInCommunityGroup
	if isSuccess then
		isInCommunityGroup = result
	else
		isInCommunityGroup = false
	end

	self.isInCommunityGroup = isInCommunityGroup

	self:updateLuckInGuiData()
end

function PlayerData.initGroupData(self: PlayerData)
	local rank = (self.player :: any):GetRankInGroup(ADMIN_GROUP_ID)
	--local role = self.player:GetRoleInGroup(ADMIN_GROUP_ID)
	--print(self.player.Name .. " is " .. role .. " (Rank: " .. rank .. ")")
	self.canUseDevTools = (rank >= 254)

	-- TODO: remove this call once LuckBillboard feature is fully shipped and validated.
	-- The community group buff is now gated behind the player explicitly pressing the
	-- Claim button on the LuckBillboard. Restoring isInCommunityGroup for returning
	-- claimers is handled in loadSaveData() via the hasClaimedGroupLuck flag instead.
	--self:updateCommunityGroupData()
end

-- returns true iff anything changed
function PlayerData.unlockProperAbilitiesForPrimaryElement(self: PlayerData, primaryElement: any)
	local anyAbilitiesUnlocked = false

	local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
	local level = playerAttributesManager:get(self.player, playerAttributeKeyLevel)

	local abilities = Abilities.getAbilitiesSortedByPrimaryElement(primaryElement)

	for _, ability in abilities do
		local abilityStatus = self.abilityStatuses[ability]
		if not abilityStatus then
			self.abilityStatuses[ability] = enums.AbilityStatus.LOCKED
			abilityStatus = self.abilityStatuses[ability]
		end

		if abilityStatus == enums.AbilityStatus.LOCKED then
			local unlockLevel = Abilities.getUnlockLevelForAbility(ability)
			if level >= unlockLevel then
				self.abilityStatuses[ability] = enums.AbilityStatus.UNLOCKED
				gameController:sendSystemMessageToPlayer(
					self.player,
					"You have unlocked access to a new skill. See the Dragon Master!"
				)
				anyAbilitiesUnlocked = true
			end
		end
	end
	return anyAbilitiesUnlocked
end

function PlayerData.updateLevelsVisuals(self: PlayerData)
	local Level = workspace:WaitForChild("Level")

	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)

	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		local primaryElementData = Elements.getDataForPrimaryElement(primaryElement) :: any

		local affinityInstance = utils.findFirstDescendantWithNameAndAttribute(
			Level,
			primaryElementData.instanceName,
			Attributes.INDEX,
			plotIndex
		)
		if not affinityInstance then
			warn("cannot find affinity instance element", primaryElementData.instanceName)
			continue
		end

		if not playerAttributesManager:get(self.player, primaryElementData.isUnlockedKey) then
			utils.setPropertyTreeClassName(affinityInstance, "SurfaceGui", "Enabled", false)
			utils.setPropertyTreeClassName(affinityInstance, "ParticleEmitter", "Enabled", false)

			continue
		end

		utils.setPropertyTreeClassName(affinityInstance, "SurfaceGui", "Enabled", true)
		utils.setPropertyTreeClassName(affinityInstance, "ParticleEmitter", "Enabled", true)

		local level = playerAttributesManager:get(self.player, primaryElementData.levelKey)
		local nextLevelXp = progressionData.nextLevelXp[level]

		-- missing labels crashed here before typing too
		local levelLabel: any = utils.findFirstDescendant(affinityInstance, "LevelLabel")
		levelLabel.Text = string.format("Level %i", level)
		local xpLabel: any = utils.findFirstDescendant(affinityInstance, "XpLabel")
		if nextLevelXp then
			xpLabel.Text =
				string.format("%i/%i", playerAttributesManager:get(self.player, primaryElementData.xpKey), nextLevelXp)
		else
			xpLabel.Text = string.format("%i", playerAttributesManager:get(self.player, primaryElementData.xpKey))
		end
	end

	self:updateLeaderboardData()
end

function PlayerData.updateVanityStateVisuals(self: PlayerData)
	if not gameController:areChestIslandsEnabled() then
		return
	end

	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)

	if self.vanityState == enums.PlayerVanityState.LOCKED then
		local gnomeEmpty: any = utils.findFirstDescendantWithTagAndAttribute(
			ClonedPlotElements,
			Tags.VANITY_GNOME_LOCKED,
			Attributes.INDEX,
			plotIndex
		)
		if not gnomeEmpty then
			local GnomeMainPlotEmpty = Gnomes:WaitForChild("GnomeMainPlotEmpty")
			gnomeEmpty = GnomeMainPlotEmpty:Clone()
		end
		local gnome: any = utils.findFirstDescendantWithTagAndAttribute(
			ClonedPlotElements,
			Tags.VANITY_GNOME_UNLOCKED,
			Attributes.INDEX,
			plotIndex
		)
		if gnome then
			gnome:Destroy()
		end

		-- put the box in place
		local gnomeAnchor = utils.findFirstDescendantWithTagAndAttribute(
			workspace,
			Tags.VANITY_GNOME_ATTACHMENT,
			Attributes.INDEX,
			plotIndex
		)
		local cframe = (gnomeAnchor :: any).WorldCFrame
		gnomeEmpty:PivotTo(cframe)
		gnomeEmpty:SetAttribute(Attributes.OBJECT_ID, gameController:getNextObjectId())
		gnomeEmpty:SetAttribute(Attributes.INDEX, plotIndex)
		gnomeEmpty:SetAttribute(Attributes.USER_ID, self.player.UserId)
		gnomeEmpty:AddTag(Tags.VANITY_GNOME_LOCKED)
		gnomeEmpty.Parent = ClonedPlotElements -- this causes the gnome to be destroyed later in plotsManager
	elseif self.vanityState == enums.PlayerVanityState.UNLOCKED then
		local gnomeEmpty: any = utils.findFirstDescendantWithTagAndAttribute(
			ClonedPlotElements,
			Tags.VANITY_GNOME_LOCKED,
			Attributes.INDEX,
			plotIndex
		)
		if gnomeEmpty then
			gnomeEmpty:Destroy()
		end

		local gnome: any = utils.findFirstDescendantWithTagAndAttribute(
			ClonedPlotElements,
			Tags.VANITY_GNOME_UNLOCKED,
			Attributes.INDEX,
			plotIndex
		)
		if not gnome then
			local GnomeMainPlot = Gnomes:WaitForChild("GnomeMainPlot")
			gnome = GnomeMainPlot:Clone()
		end

		-- put the gnome in place
		local gnomeAnchor = utils.findFirstDescendantWithTagAndAttribute(
			workspace,
			Tags.VANITY_GNOME_ATTACHMENT,
			Attributes.INDEX,
			plotIndex
		)
		local cframe = (gnomeAnchor :: any).WorldCFrame
		gnome:PivotTo(cframe)
		gnome:SetAttribute(Attributes.OBJECT_ID, gameController:getNextObjectId())
		gnome:SetAttribute(Attributes.INDEX, plotIndex)
		gnome:SetAttribute(Attributes.USER_ID, self.player.UserId)
		gnome:AddTag(Tags.VANITY_GNOME_UNLOCKED)
		gnome.Parent = ClonedPlotElements -- this causes the gnome to be destroyed later in plotsManager
	else
		warn("unknown player vanity state", self.player, self.vanityState)
		return
	end
end

function PlayerData.unlockPrimaryElementIfNeeded(self: PlayerData, primaryElement: any)
	if primaryElement == enums.PrimaryElements.NONE then
		return
	end

	local playerDataKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
	if playerAttributesManager:get(self.player, playerDataKeyIsUnlocked) then
		-- already unlocked
		return
	end

	playerAttributesManager:set(self.player, playerDataKeyIsUnlocked, true)

	-- contextual FTUE: explain the multi-element system the first time a second element (Fire or Water) unlocks
	if primaryElement == enums.PrimaryElements.FIRE or primaryElement == enums.PrimaryElements.WATER then
		contextualFtueManager:tryTrigger(self.player, "unlockElement")
	end

	local primaryElementName = enums.getPublicName(enums.PrimaryElements, primaryElement)

	local color = utils.get2DColorForPrimaryElement(primaryElement)
	local colorStr = color:ToHex()

	gameController:sendSystemMessageToPlayer(
		self.player,
		string.format('You have unlocked access to <font color="#%s">%s</font>', colorStr, tostring(primaryElementName))
	)

	self:updateLevelsVisuals()
end

function PlayerData.addPrimaryElementXp(self: PlayerData, primaryElement: any, xpDiff: any, position: Vector3)
	local playerAttributeKeyXp = Elements.getXpKeyForPrimaryElement(primaryElement)
	local xp = playerAttributesManager:get(self.player, playerAttributeKeyXp)
	xp += xpDiff

	local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
	local level = playerAttributesManager:get(self.player, playerAttributeKeyLevel)

	local isMaxLevel = (progressionData.nextLevelXp[level] == nil)
	if isMaxLevel then
		return
	end

	local nextLevelXp = progressionData.nextLevelXp[level]

	--print("player", player, "element", primaryElement, "level", level, "next level xp", nextLevelXp)

	if nextLevelXp and xp >= nextLevelXp then
		xp -= nextLevelXp

		isMaxLevel = (progressionData.nextLevelXp[level + 1] == nil)
		if isMaxLevel then
			xp = 0
		end

		-- set new xp
		playerAttributesManager:set(self.player, playerAttributeKeyXp, xp)

		-- set new level
		playerAttributesManager:addWholeNumber(self.player, playerAttributeKeyLevel, 1)
		local newLevel = playerAttributesManager:get(self.player, playerAttributeKeyLevel)
		RemoteEvents.NotifyLevelGrant:FireClient(self.player, primaryElement, newLevel)

		if newLevel == Constants.LEVEL_TO_UNLOCK_ABILITY_SLOT and not self.purchasedSlotUnlocks[primaryElement] then
			gameController:sendSystemMessageToPlayer(
				self.player,
				"You have unlocked an additional slot for skills. See the Dragon Master!"
			)
		end

		self:updatePlayerVariablesFromLevels()

		gameController:notifyPlayerLevelChanged(self.player)

		analyticsManager:logEvent(self.player, analyticsManager.Events.GainLevel, {
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
			xp = xpDiff,
		})

		if self:unlockProperAbilitiesForPrimaryElement(primaryElement) then
			RemoteEvents.NotifyAbilityStatuses:FireClient(self.player, self:getAbilityStatuses())

			-- contextual FTUE: explain abilities the first time any ability unlocks (level 5 in any element)
			contextualFtueManager:tryTrigger(self.player, "unlockAbility")
		end

		self:updatePlayerFeaturesInGuiData()

		-- contextual FTUE: explain Fuse All the first time it unlocks (level 10 Nature)
		if self:canMergeAll() then
			contextualFtueManager:tryTrigger(self.player, "unlockFuseAll")
		end
	else
		-- set new xp; level didn't change
		playerAttributesManager:set(self.player, playerAttributeKeyXp, xp)
	end

	RemoteEvents.NotifyXpGrant:FireClient(self.player, primaryElement, xpDiff, position)

	-- if needed, in the future we can break this down to only update what changed
	self:updateLevelsVisuals()
end

function PlayerData.growAllCrops(self: PlayerData)
	-- give grow time credit at least, for now
	for _, crop in itemManager:getCropsOnGroundForUserId(self.player.UserId) do
		if not crop:isGrowing() then
			continue
		end
		crop:growFull()
	end
end

function PlayerData.checkPlayerFallingTooLow(self: PlayerData)
	if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local playerY = (self.player.Character :: any).HumanoidRootPart.Position.Y
	if playerY < Constants.MIN_PLAYER_Y then
		if self.ridingItemId then
			--print("player went too low while riding", self.player)
			rideMixin:stopPlayerRiding(self.player)
			-- this disconnects the player from the dragon, but then the dragon head seems to teleport to a reasonable Y
			-- and the body eventually follows, as of 2025-november-11
		end

		local recoveryPosition = plotsManager:getPlotItemRecoveryPositionByUserId(self.player.UserId)
		if not recoveryPosition then
			-- no plot assigned yet (join initialization is still yielding on DataStores) or it
			-- was just released; nowhere to recover to, and this check runs every frame so we
			-- just try again once the plot exists
			return
		end

		local newPosition = recoveryPosition + Vector3.new(0, 5, 0);
		(self.player.Character :: any).HumanoidRootPart:PivotTo(CFrame.new(newPosition));
		(self.player.Character :: any).HumanoidRootPart.Velocity = Vector3.zero
	end
end

function PlayerData.getIsInPlot(self: PlayerData)
	return self.isInPlot
end

function PlayerData.updatePlayerIsInPlot(self: PlayerData)
	if not self.player.Character or not self.player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local playerPosition = (self.player.Character :: any).HumanoidRootPart.Position

	local isInPlot = self:isLocationInPlotOrUnlockedExpansions(playerPosition)
	if isInPlot == self.isInPlot then
		return
	end

	self.isInPlot = isInPlot
	if self.isInPlot then
		--print("player just entered plot area", self.player)
		local dragons = itemManager:getDragonsOnGroundForUserId(self.player.UserId)
		for _, dragon in dragons do
			dragon:notifyPlayerReturnedToPlot()
		end
	else
		--print("player just left plot area", self.player)
		-- don't care
	end

	RemoteEvents.NotifyIsInPlot:FireClient(self.player, self.isInPlot)
end

function PlayerData.setRiding(self: PlayerData, itemId: any, playerRelativeToDragonCFrame: any)
	if itemId then
		self.latestRidingItemId = itemId
	end

	self.ridingItemId = itemId
	self.playerRelativeToDragonCFrame = playerRelativeToDragonCFrame
	--print("player relative to riding item is", playerRelativeToDragonCFrame, "position", playerRelativeToDragonCFrame.Position)

	RemoteEvents.NotifyPlayerRidingStatus:FireAllClients(self.player.UserId, itemId ~= nil)
end

function PlayerData.getRidingItemId(self: PlayerData)
	return self.ridingItemId
end

function PlayerData.getLatestRidingItemId(self: PlayerData)
	return self.latestRidingItemId
end

function PlayerData.notifyRidingItemCFrame(self: PlayerData, cframe: CFrame, playerRelativeToDragonCFrame: any)
	if playerRelativeToDragonCFrame then
		self.playerRelativeToDragonCFrame = playerRelativeToDragonCFrame
	end

	if not self.playerRelativeToDragonCFrame then
		return
	end

	local playerCFrame = cframe * self.playerRelativeToDragonCFrame;
	--print("given riding position", cframe.Position, "player becomes", playerCFrame)
	(self.player.Character :: any).HumanoidRootPart:PivotTo(playerCFrame)
end

function PlayerData.getRidingPlayerRelativeToDragonCFrame(self: PlayerData)
	return self.playerRelativeToDragonCFrame
end

function PlayerData.getMergeData(self: PlayerData)
	return self.mergeData
end

function PlayerData.setMergeData(self: PlayerData, data: any)
	self.mergeData = data
end

function PlayerData.incrementStat(self: PlayerData, statName: any)
	self:addToStat(statName, 1)
end

function PlayerData.addToStat(self: PlayerData, statName: any, count: number)
	if not self.stats[statName] then
		warn("invalid stat name", statName)
		return
	end
	if count <= 0 then
		warn("invalid stat count to add, must be positive", statName, count)
		return
	end

	self.stats[statName] += count
end

function PlayerData.resetStats(self: PlayerData)
	self:setDefaultStats()
end

function PlayerData.resetLuckBillboard(self: PlayerData)
	self.hasClaimedGroupLuck = false
	self.isInCommunityGroup = false
	self:updateLuckInGuiData()
end

function PlayerData.setDefaultStats(self: PlayerData)
	self.stats.creationTime = math.floor(workspace:GetServerTimeNow())
	self.stats.sessions = 1
	self.stats.totalPlaySec = 0
	self.stats.cropMerges = 0
	self.stats.dragonMerges = 0
	self.stats.crystalMerges = 0
	self.stats.nodesMined = 0
	self.stats.dragonsFed = 0
	self.stats.crittersShot = 0
end

function PlayerData.getCreationTime(self: PlayerData)
	return self.stats.creationTime
end

function PlayerData.getSessionCount(self: PlayerData)
	return self.stats.sessions
end

function PlayerData.getTotalPlaySec(self: PlayerData)
	return self.stats.totalPlaySec
end

function PlayerData.doesPlayerHaveItemCount(self: PlayerData, itemName: any, count: number)
	local items = itemManager:getItemsNotOnGroundByUserId(self.player.UserId)
	for _, item in items do
		if item:getItemName() ~= itemName then
			continue
		end
		if item:getCount() >= count then
			return true
		end
	end

	return false
end

function PlayerData.getItemForPlayer(self: PlayerData, itemName: any): Types.Item?
	local items = itemManager:getItemsNotOnGroundByUserId(self.player.UserId)
	for _, item in items do
		if item:getItemName() ~= itemName then
			continue
		end

		return item
	end

	return nil
end

function PlayerData.getStableSlots(self: PlayerData): any
	return self.stableSlots
end

function PlayerData.getStableDragonInSlot(self: PlayerData, stableSlotIndex: number): number?
	return self.stableSlots[stableSlotIndex]
end

function PlayerData.getTotalDragonPower(self: PlayerData): number
	return self.totalDragonPower
end

function PlayerData.recomputeTotalDragonPower(self: PlayerData)
	local total = 0

	for _, itemId in self.stableSlots do
		local item = itemManager:getItemById(itemId)
		if not item or item:getType() ~= "shadowDragon" then
			continue
		end

		total += (item :: Types.ShadowDragon):getPower()
	end

	self.totalDragonPower = total
	playerAttributesManager:set(self.player, PlayerAttributeKeys.TOTAL_DRAGON_POWER, total)
end

function PlayerData.setStableDragonInSlot(self: PlayerData, stableSlotIndex: number, itemId: number)
	self.stableSlots[stableSlotIndex] = itemId
	self:recomputeTotalDragonPower()
end

function PlayerData.clearStableSlot(self: PlayerData, stableSlotIndex: number)
	self.stableSlots[stableSlotIndex] = nil
	self:recomputeTotalDragonPower()
end

function PlayerData.getAbilityStatuses(self: PlayerData)
	return self.abilityStatuses
end

function PlayerData.resetAbilityStatuses(self: PlayerData)
	self:setDefaultAbilityStatuses()
end

function PlayerData.setDefaultAbilityStatuses(self: PlayerData)
	self.abilityStatuses = {}
	for _, ability in enums.getAllValues(enums.Abilities) do
		self.abilityStatuses[ability] = enums.AbilityStatus.LOCKED
	end
end

function PlayerData.setPlayerVariable(self: PlayerData, attributeName: any, value: any)
	self.playerVariables[attributeName] = value

	-- many player variables from abilities aren't needed by client
	-- maybe should make a PlayerVariables source file that would centralize this for non-ability ones too
	if Abilities.doAbilitiesControlAttributeName(attributeName) then
		if not Abilities.getIsClientForAttributeName(attributeName) then
			return
		end
	end

	local splendidDataFolder: any = (self.player :: any).PlayerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	local playerVariables = splendidDataFolder:FindFirstChild(Constants.PLAYER_VARIABLES_NAME)

	playerVariables:SetAttribute(attributeName, value)
end

function PlayerData.getPlayerVariable(self: PlayerData, attributeName: any)
	return self.playerVariables[attributeName]
end

function PlayerData.updatePlayerVariablesFromAbilities(self: PlayerData)
	local attributeNames = Abilities.getAttributeNames()
	for _, attributeName in attributeNames do
		if not abilityValuesData[attributeName] then
			warn("missing ability values game data for", attributeName)
			continue
		end

		local variable = abilityValuesData[attributeName].default
		if not variable then
			warn("missing default value for ability attribute", attributeName)
			continue
		end

		for _, ability in Abilities.getAbilitiesForAttributeName(attributeName) do
			if self.abilityStatuses[ability] ~= enums.AbilityStatus.EQUIPPED then
				continue
			end

			local value = abilityValuesData[attributeName][ability]
			if not value then
				warn("invalid ability data for", attributeName, ability, self.player)
				continue
			end

			variable = value
			break
		end
		--print("setting variable ", attributeName, variable)
		self:setPlayerVariable(attributeName, variable)
	end
end

function PlayerData.updatePlayerVariablesFromLevels(self: PlayerData)
	local unlockedAbilitySlotCount = Constants.BASE_ABILITY_SLOTS

	local lockedSlotsStr = ""

	for _, primaryElement in Elements.getPrimaryElementsSorted() do
		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		local level = playerAttributesManager:get(self.player, playerAttributeKeyLevel)
		if level >= Constants.LEVEL_TO_UNLOCK_ABILITY_SLOT or self.purchasedSlotUnlocks[primaryElement] then
			unlockedAbilitySlotCount += 1
		else
			if lockedSlotsStr ~= "" then
				lockedSlotsStr = lockedSlotsStr .. " "
			end
			lockedSlotsStr = lockedSlotsStr
				.. string.format("%i %i", primaryElement, Constants.LEVEL_TO_UNLOCK_ABILITY_SLOT)
		end
	end

	self:setPlayerVariable(Attributes.UNLOCKED_ABILITY_SLOTS, unlockedAbilitySlotCount)
	self:setPlayerVariable(Attributes.UNLOCKABLE_ABILITY_SLOT_DATA, lockedSlotsStr)
end

function PlayerData.updatePlayerVariablesFromIndexRewards(self: PlayerData)
	for attributeName, buffAmount in self.indexStatBuffs do
		local baseValue = self:getPlayerVariable(attributeName)
		if baseValue ~= nil and typeof(baseValue) ~= "number" then
			warn("index stat buff attribute is not numeric, skipping", attributeName, self.player)
			continue
		end

		self:setPlayerVariable(attributeName, (baseValue or 0) + buffAmount)
	end
end

function PlayerData.updatePlayerVariables(self: PlayerData)
	local splendidDataFolder: any = (self.player :: any).PlayerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)

	local playerVariables = splendidDataFolder:FindFirstChild(Constants.PLAYER_VARIABLES_NAME)
	if not playerVariables then
		playerVariables = Instance.new("Part")
		playerVariables.Name = Constants.PLAYER_VARIABLES_NAME
		playerVariables.Parent = splendidDataFolder
	end

	self.playerVariables = {}

	self:updatePlayerVariablesFromAbilities()
	self:updatePlayerVariablesFromLevels()
	self:updatePlayerVariablesFromIndexRewards()
end

function PlayerData.canEquipAbility(self: PlayerData, ability: any)
	local countEquipped = 0
	for ability, status in self.abilityStatuses do
		if status ~= enums.AbilityStatus.EQUIPPED then
			continue
		end
		countEquipped += 1
	end

	local unlockedAbilitySlotCount = self:getPlayerVariable(Attributes.UNLOCKED_ABILITY_SLOTS)

	if countEquipped >= unlockedAbilitySlotCount then
		local replaceAbility = Abilities.getReplaceAbilityForAbility(ability)
		if not replaceAbility or self.abilityStatuses[replaceAbility] ~= enums.AbilityStatus.EQUIPPED then
			return false
		end
		-- we're full, but equipping this new ability will replace an old one, so that's OK
	end

	if self.abilityStatuses[ability] == enums.AbilityStatus.EQUIPPED then
		return false
	end

	if self.abilityStatuses[ability] == enums.AbilityStatus.LOCKED then
		return false
	end

	return true
end

function PlayerData.equipAbility(self: PlayerData, ability: any)
	self.abilityStatuses[ability] = enums.AbilityStatus.EQUIPPED

	local ancestorAbility = ability
	while true do
		ancestorAbility = Abilities.getReplaceAbilityForAbility(ancestorAbility)
		if not ancestorAbility then
			break
		end

		self.abilityStatuses[ancestorAbility] = enums.AbilityStatus.REPLACED
	end

	self:updatePlayerVariables()

	analyticsManager:logEvent(self.player, analyticsManager.Events.EquipAbility, {
		ability = enums.getPublicName(enums.Abilities, ability),
	})
end

function PlayerData.canUnequipAbility(self: PlayerData, ability: any)
	if self.abilityStatuses[ability] ~= enums.AbilityStatus.EQUIPPED then
		return false
	end

	return true
end

function PlayerData.unequipAbility(self: PlayerData, ability: any)
	self.abilityStatuses[ability] = enums.AbilityStatus.UNLOCKED

	self:updatePlayerVariables()

	analyticsManager:logEvent(self.player, analyticsManager.Events.UnequipAbility, {
		ability = enums.getPublicName(enums.Abilities, ability),
		primaryElement = enums.getPublicName(enums.PrimaryElements, Abilities.getPrimaryElementForAbility(ability)),
	})
end

function PlayerData.setPurchasedSlotUnlock(self: PlayerData, primaryElement: any)
	self.purchasedSlotUnlocks[primaryElement] = true

	self:updatePlayerVariablesFromLevels()

	RemoteEvents.NotifyUpdatePurchasedSlotUnlocks:FireClient(self.player)
end

function PlayerData.resetPurchasedSlotUnlocks(self: PlayerData)
	self.purchasedSlotUnlocks = {}

	self:updatePlayerVariablesFromLevels()

	RemoteEvents.NotifyUpdatePurchasedSlotUnlocks:FireClient(self.player)
end

function PlayerData.markInstantOpenCrystalItemId(self: PlayerData, itemId: any)
	table.insert(self.instantOpenCrystalItemIds, itemId)
end

function PlayerData.tryGetBestInstantOpenCrystalItemId(self: PlayerData, durationSec: any)
	for _, crystalItemId in self.instantOpenCrystalItemIds do
		local crystal = itemManager:getItemById(crystalItemId) :: Types.Crystal?
		if not crystal then
			continue
		end
		if not crystal:isOpening() then
			continue
		end
		local remainingOpeningSec = crystal:getRemainingOpeningSec() or 0
		if remainingOpeningSec <= durationSec then
			--print("found marked crystal", crystalItemId, remainingOpeningSec)
			return crystalItemId
		end
	end

	local crystals: { Crystal.Crystal } = itemManager:getOpeningCrystalsForUserId(self.player.UserId)
	-- opening crystals always have a remaining opening time, so the fallbacks cannot trigger
	table.sort(crystals, function(a: Crystal.Crystal, b: Crystal.Crystal): boolean
		return (a:getRemainingOpeningSec() or 0) > (b:getRemainingOpeningSec() or 0)
	end)

	--print("looking through other crystals", crystals)
	for _, crystal in crystals do
		if (crystal:getRemainingOpeningSec() or 0) > durationSec then
			continue
		end

		--print("found one", crystal:getItemId(), crystal:getRemainingOpeningSec())
		return crystal:getItemId()
	end

	return nil
end

function PlayerData.getDefaultVanityComponentStates(self: PlayerData)
	local vanityComponentStates = {}

	local vanityComponentNames
	vanityComponentNames = plotsManager:getAllMainPlotInnerNames()
	for _, name in vanityComponentNames do
		vanityComponentStates[name] = enums.VanityComponentState.LOCKED
	end

	vanityComponentNames = plotsManager:getAllMainPlotOuterNames()
	for _, name in vanityComponentNames do
		vanityComponentStates[name] = enums.VanityComponentState.LOCKED
	end

	vanityComponentNames = plotsManager:getAllFenceNames()
	for _, name in vanityComponentNames do
		vanityComponentStates[name] = enums.VanityComponentState.LOCKED
	end

	vanityComponentNames = plotsManager:getAllExpansionInnerNames()
	for _, name in vanityComponentNames do
		vanityComponentStates[name] = enums.VanityComponentState.LOCKED
	end

	vanityComponentNames = plotsManager:getAllExpansionOuterNames()
	for _, name in vanityComponentNames do
		vanityComponentStates[name] = enums.VanityComponentState.LOCKED
	end

	return vanityComponentStates
end

function PlayerData.mergeVanityComponentStatesWithDefault(self: PlayerData, vanityComponentStates: any)
	local retval = self:getDefaultVanityComponentStates()

	for name, state in vanityComponentStates do
		if state ~= enums.VanityComponentState.LOCKED then
			-- migration 2026-may-23 dev only
			state = enums.VanityComponentState.UNLOCKED
		end

		retval[name] = state
	end

	return retval
end

function PlayerData.getNonDefaultVanityComponentStates(self: PlayerData)
	local retval = {}

	for name, state in self.vanityComponentStates do
		if state == enums.VanityComponentState.LOCKED then
			continue
		end

		retval[name] = state
	end

	return retval
end

function PlayerData.getDefaultVanityPlacements(self: PlayerData)
	return {}
end

function PlayerData.getDefaultVanityAreaStates(self: PlayerData)
	local vanityAreaStates = {}

	for _, vanityArea in enums.getAllValues(enums.VanityAreas) do
		vanityAreaStates[vanityArea] = enums.VanityAreaState.LOCKED
	end

	vanityAreaStates[enums.VanityAreas.MAIN_PLOT] = enums.VanityAreaState.UNLOCKED
	vanityAreaStates[enums.VanityAreas.MAIN_PLOT_FENCE] = enums.VanityAreaState.UNLOCKED

	return vanityAreaStates
end

function PlayerData.isVanityComponentLocked(self: PlayerData, vanityComponentName: any)
	return self.vanityComponentStates[vanityComponentName] == enums.VanityComponentState.LOCKED
end

function PlayerData.isVanityComponentUnlocked(self: PlayerData, vanityComponentName: any)
	return self.vanityComponentStates[vanityComponentName] == enums.VanityComponentState.UNLOCKED
end

function PlayerData.unlockVanityComponent(self: PlayerData, vanityComponentName: any)
	self.vanityComponentStates[vanityComponentName] = enums.VanityComponentState.UNLOCKED

	self:updateVanityDataInGuiData()

	analyticsManager:logEvent(self.player, analyticsManager.Events.UnlockVanityComponent, {
		objectName = vanityComponentName,
	})
end

function PlayerData.equipVanityComponentAtPlacement(self: PlayerData, vanityPlacement: any, vanityComponentName: any)
	self.vanityPlacements[vanityPlacement] = vanityComponentName

	self:updateVanityPlacementDataInGuiData()

	plotsManager:equipVanityComponentForPlayerAtPlacement(self.player, vanityPlacement, vanityComponentName)
end

function PlayerData.unequipVanityPlacement(self: PlayerData, vanityPlacement: any)
	self.vanityPlacements[vanityPlacement] = nil

	self:updateVanityPlacementDataInGuiData()

	plotsManager:unequipVanityPlacementForPlayer(self.player, vanityPlacement)
end

function PlayerData.syncDefaultExpansionVanityAreaIfNeeded(self: PlayerData, vanityArea: any)
	-- ensure inner and outer exist for this expansion

	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)
	if not plotIndex then
		warn("no plot index for user", self.player.UserId)
		return
	end

	local innerVanityPlacement
	local outerVanityPlacement
	if vanityArea == enums.VanityAreas.EXPANSION_1 then
		innerVanityPlacement = enums.VanityPlacements.EXPANSION_1_INNER
		outerVanityPlacement = enums.VanityPlacements.EXPANSION_1_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_2 then
		innerVanityPlacement = enums.VanityPlacements.EXPANSION_2_INNER
		outerVanityPlacement = enums.VanityPlacements.EXPANSION_2_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_3 then
		innerVanityPlacement = enums.VanityPlacements.EXPANSION_3_INNER
		outerVanityPlacement = enums.VanityPlacements.EXPANSION_3_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_4 then
		innerVanityPlacement = enums.VanityPlacements.EXPANSION_4_INNER
		outerVanityPlacement = enums.VanityPlacements.EXPANSION_4_OUTER
	else
		warn("unknown vanity area", vanityArea)
		return
	end

	if not self.vanityPlacements[innerVanityPlacement] then
		-- show default because no special vanity configured
		plotsManager:restoreExpansionInner(plotIndex, innerVanityPlacement)
	end

	if not self.vanityPlacements[outerVanityPlacement] then
		-- show default because no special vanity configured
		plotsManager:restoreExpansionOuter(plotIndex, outerVanityPlacement)
	end
end

-- executes after loading all of the vanity data for the player
function PlayerData.syncVanityToWorld(self: PlayerData)
	-- go through unlockable areas first
	for vanityArea, vanityAreaState in self.vanityAreaStates do
		if vanityArea == enums.VanityAreas.MAIN_PLOT then
			-- already handled in plotsManager; always unlocked
			continue
		end
		if vanityArea == enums.VanityAreas.MAIN_PLOT_FENCE then
			-- no default, don't care
			continue
		end

		if vanityAreaState ~= enums.VanityAreaState.UNLOCKED then
			continue
		end

		self:syncDefaultExpansionVanityAreaIfNeeded(vanityArea)
	end

	-- equip all custom vanity components

	for vanityPlacement, vanityComponentName in self.vanityPlacements do
		self:equipVanityComponentAtPlacement(vanityPlacement, vanityComponentName)
	end
end

function PlayerData.unlockPlayerVanityStateIfNeeded(self: PlayerData)
	if self.vanityState == enums.PlayerVanityState.UNLOCKED then
		return
	end

	gameController:sendSystemMessageToPlayer(self.player, "A gnome has jumped into the hole by your plot")

	self:setVanityState(enums.PlayerVanityState.UNLOCKED)
end

function PlayerData.setVanityState(self: PlayerData, vanityState: any)
	self.vanityState = vanityState

	self:updateVanityStateVisuals()
end

function PlayerData.getVanityAreaState(self: PlayerData, vanityArea: any)
	return self.vanityAreaStates[vanityArea]
end

function PlayerData.unlockVanityArea(self: PlayerData, vanityArea: any)
	if not self.vanityAreaStates[vanityArea] then
		warn("cannot unlock vanity area we don't have a state", self.player, vanityArea)
	end

	self.vanityAreaStates[vanityArea] = enums.VanityAreaState.UNLOCKED

	self:updateVanityAreaDataInGuiData()

	-- show the default inner and outer of the island in the world
	self:syncDefaultExpansionVanityAreaIfNeeded(vanityArea)

	-- vanity areas can add capacity
	self:updateCapacityDisplay()

	local vanityAreaName = enums.getPublicName(enums.VanityAreas, vanityArea)
	analyticsManager:logEvent(self.player, analyticsManager.Events.UnlockVanityArea, {
		objectName = vanityAreaName,
	})
end

function PlayerData.resetAllVanity(self: PlayerData)
	self.vanityState = enums.PlayerVanityState.LOCKED

	self.vanityComponentStates = self:getDefaultVanityComponentStates()

	for vanityPlacement, _ in self.vanityPlacements do
		plotsManager:unequipVanityPlacementForPlayer(self.player, vanityPlacement)
	end

	self.vanityPlacements = self:getDefaultVanityPlacements()

	self.vanityAreaStates = self:getDefaultVanityAreaStates()

	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)
	if plotIndex then
		plotsManager:removeAllVanity(plotIndex)
	end

	self:updateVanityDataInGuiData()
	self:updateVanityPlacementDataInGuiData()

	self:updateVanityStateVisuals()
end

function PlayerData.tryClaimWelcomeBackGift(self: PlayerData)
	if self.pendingWelcomeBackCoinCount == 0 then
		return false
	end

	local coinCount = self.pendingWelcomeBackCoinCount
	self.pendingWelcomeBackCoinCount = 0

	playerAttributesManager:addWholeNumber(self.player, PlayerAttributeKeys.COINS, coinCount)

	return true
end

function PlayerData.tryDeliverDoubleWelcomeBackGift(self: PlayerData)
	if self.pendingWelcomeBackCoinCount == 0 then
		return false
	end

	local coinCount = 2 * self.pendingWelcomeBackCoinCount
	self.pendingWelcomeBackCoinCount = 0

	playerAttributesManager:addWholeNumber(self.player, PlayerAttributeKeys.COINS, coinCount)

	return true
end

function PlayerData.processOfflineTime(self: PlayerData, durationSec: any)
	--print("giving credit to player", self.player, "for offline seconds", durationSec)

	-- give grow time credit
	for _, crop in itemManager:getCropsOnGroundForUserId(self.player.UserId) do
		if not crop:isGrowing() then
			continue
		end
		crop:addGrowTime(durationSec)
	end

	local dragons = itemManager:getAvailableDragonsToEatForPlayer(self.player)
	local crops = itemManager:getCropsOnGroundForUserId(self.player.UserId)

	-- calculate offline harvesting, element by element

	local totalGemCount = 0
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end

		-- find highest level dragon and crop of the element; without both, player gets nothing in this element
		local bestDragon = nil
		for _, dragon in dragons do
			local dragonItemData = dragon:getItemData()
			if dragonItemData.primaryElement ~= primaryElement then
				continue
			end
			if not dragonItemData.eat then
				continue
			end

			if not bestDragon then
				bestDragon = dragon
				continue
			end
			if dragonItemData.level > bestDragon:getItemData().level then
				bestDragon = dragon
			end
		end
		if not bestDragon then
			continue
		end

		local bestCrop = nil
		for _, crop in crops do
			local cropItemData = crop:getItemData()
			if cropItemData.primaryElement ~= primaryElement then
				continue
			end
			if not cropItemData.food then
				continue
			end
			if not bestCrop then
				bestCrop = crop
				continue
			end
			if cropItemData.level > bestCrop:getItemData().level then
				bestCrop = crop
			end
		end
		if not bestCrop then
			continue
		end

		local totalSteps, maxCountPerStep = gameController:calculateEatingSteps(bestDragon, bestCrop)
		local eatingSec = totalSteps * maxCountPerStep
		local growSec = bestCrop:getItemData().food.growMin * 60
		local cycleSec = eatingSec + growSec

		local singleEventGemCount = gameController:calculateGemsForHarvest(bestDragon, bestCrop)

		local efficiencyRate = offlineHarvestingData.efficiencyRate
		local maxDurationSec = self:getPlayerVariable(Attributes.OFFLINE_HARVESTING_MAX_DURATION)

		local eventCount = math.floor((efficiencyRate * math.min(durationSec, maxDurationSec)) / cycleSec)

		local gemCount = math.ceil(singleEventGemCount * eventCount)

		--print("offline progression gems based on", enums.getName(enums.PrimaryElements, primaryElement), bestDragon:getItemName(), bestCrop:getItemName(), "offline time", durationSec)
		--print("single event gem count", singleEventGemCount, "cycle sec", cycleSec, "event count", eventCount, "total gems", gemCount)

		totalGemCount += gemCount

		analyticsManager:logEvent(self.player, analyticsManager.Events.OfflineGems, {
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
			gemsSpawned = gemCount,
		})
	end

	if totalGemCount > 0 then
		-- here we go:
		-- save our pending coins
		-- tell client about it
		-- wait for client to tell us

		self.pendingWelcomeBackCoinCount = totalGemCount * 10
		RemoteEvents.NotifyWelcomeBackGift:FireClient(self.player, self.pendingWelcomeBackCoinCount)
	end
end

function PlayerData.loadOptions(self: PlayerData, options: any)
	self.options = options

	-- set default options if any are unset
	if self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED] == nil then
		self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED] = true
	end

	if self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED] == nil then
		self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED] = true
	end

	if self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED] == nil then
		self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED] = true
	end

	if self.options[PlayerOptionKeys.POTATO_MODE_ENABLED] == nil then
		self.options[PlayerOptionKeys.POTATO_MODE_ENABLED] = false
	end

	if self.options[PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED] == nil then
		self.options[PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED] = true
	end

	if self.options[PlayerOptionKeys.MERGE_ALL_ENABLED] == nil then
		self.options[PlayerOptionKeys.MERGE_ALL_ENABLED] = false
	end
end

function PlayerData.loadSaveData(self: PlayerData, saveData: any)
	local offlineElapsedSec = 0

	local timeSaveData = saveData and saveData.saveTime or nil
	if timeSaveData then
		offlineElapsedSec = math.max(0, math.floor(workspace:GetServerTimeNow() - saveData.saveTime))
	end

	local playerSaveData = saveData and saveData.player or nil
	playerAttributesManager:loadSaveData(self.player, playerSaveData)

	local vanityStateSaveData = saveData and saveData.vanityState or nil
	if vanityStateSaveData then
		self.vanityState = vanityStateSaveData
	else
		self.vanityState = enums.PlayerVanityState.LOCKED
	end

	self:updateVanityStateVisuals()

	local vanityComponentStatesSaveData = saveData and saveData.vanityComponentStates or nil
	if vanityComponentStatesSaveData then
		self.vanityComponentStates = self:mergeVanityComponentStatesWithDefault(vanityComponentStatesSaveData)
	else
		self.vanityComponentStates = self:getDefaultVanityComponentStates()
	end

	self:updateVanityDataInGuiData()

	local vanityPlacementsSaveData = saveData and saveData.vanityPlacements or nil
	if vanityPlacementsSaveData then
		self.vanityPlacements = {}
		for vanityPlacementStr, vanityComponentName in vanityPlacementsSaveData do
			local vanityPlacement = tonumber(vanityPlacementStr)
			if not enums.validateValue(enums.VanityPlacements, vanityPlacement) then
				print("ignoring vanity placement that no longer exists", vanityPlacement)
				continue
			end
			self.vanityPlacements[vanityPlacement] = vanityComponentName
		end
	else
		-- this used to be a dot call that passed no self; the method does not use self, so behavior is unchanged
		self.vanityPlacements = self:getDefaultVanityPlacements()
	end

	self:updateVanityPlacementDataInGuiData()

	local vanityAreaStatesSaveData = saveData and saveData.vanityAreaStates or nil
	if vanityAreaStatesSaveData then
		self.vanityAreaStates = {}
		for vanityAreaStr, vanityAreaState in vanityAreaStatesSaveData do
			local vanityArea = tonumber(vanityAreaStr)
			if not enums.validateValue(enums.VanityAreas, vanityArea) then
				print("ignoring vanity area that no longer exists", vanityArea)
				continue
			end
			self.vanityAreaStates[vanityArea] = vanityAreaState
		end
	else
		self.vanityAreaStates = self:getDefaultVanityAreaStates()
	end

	self:updateVanityAreaDataInGuiData()

	self:syncVanityToWorld()

	-- vanity needs to cemo before items because vanity islands can hold items

	local itemsSaveData = saveData and saveData.items or nil
	if itemsSaveData then
		itemManager:loadDataForPlayer(self.player, itemsSaveData, offlineElapsedSec)
	else
		-- pass
	end

	self:updateLevelsVisuals()

	local statsSaveData = saveData and saveData.stats or nil
	if statsSaveData then
		self:setDefaultStats()
		for key, value in saveData.stats do
			self.stats[key] = value
		end
		self:incrementStat("sessions")
	else
		self:setDefaultStats()
	end

	local playerAttributes = playerAttributesManager:getClientAttributesForPlayer(self.player)
	RemoteEvents.NotifyAllAttributes:FireClient(self.player, playerAttributes)

	local abilitiesSaveData = saveData and saveData.abilityStatuses or nil
	if abilitiesSaveData then
		self.abilityStatuses = {}
		for abilityStr, abilityStatus in abilitiesSaveData do
			local ability = tonumber(abilityStr)
			if not Abilities.validateAbility(ability) then
				print("ignoring ability that no longer exists", ability)
				continue
			end
			self.abilityStatuses[ability] = abilityStatus
		end
	else
		self:setDefaultAbilityStatuses()
	end

	-- if any new abilities were implemented since the last time the player was here, unlock them
	for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end
		self:unlockProperAbilitiesForPrimaryElement(primaryElement)
	end

	local purchasedSlotUnlocksSaveData = saveData and saveData.purchasedSlotUnlocks or nil
	if purchasedSlotUnlocksSaveData then
		for primaryElementStr, value in purchasedSlotUnlocksSaveData do
			self.purchasedSlotUnlocks[tonumber(primaryElementStr)] = value
		end
	else
		self.purchasedSlotUnlocks = {}
	end

	local starterOfferProgressSaveData = saveData and saveData.starterOfferProgress or nil
	if starterOfferProgressSaveData then
		self.starterOfferProgress = starterOfferProgressSaveData
	else
		self.starterOfferProgress = {}
	end

	local buyStorePurchasesSaveData = saveData and saveData.buyStorePurchases or nil
	if buyStorePurchasesSaveData then
		-- a record from a past era is fine to load as-is; getBuyStorePurchaseCountsForEra discards it on first read
		self.buyStorePurchases = buyStorePurchasesSaveData
	else
		self.buyStorePurchases = { era = 0, counts = {} }
	end

	local ftueProgressSaveData = saveData and saveData.ftueProgress or nil
	if ftueProgressSaveData then
		self.ftueProgress = ftueManager:mapFtueProgressFromSaveData(ftueProgressSaveData)
	else
		self.ftueProgress = ftueManager:getDefaultFtueProgress()
	end

	local firstSessionOfferStateSaveData = saveData and saveData.firstSessionOfferState or nil
	if firstSessionOfferStateSaveData then
		self.firstSessionOfferState =
			firstSessionOfferManager:mapFirstSessionOfferStateFromSaveData(self.player, firstSessionOfferStateSaveData)
	else
		self.firstSessionOfferState = firstSessionOfferManager:getDefaultFirstSessionOfferState()
	end

	local codesRedeemedSaveData = saveData and saveData.codesRedeemed or nil
	if codesRedeemedSaveData then
		self.codesRedeemed = codesRedeemedSaveData
	else
		self.codesRedeemed = {}
	end

	local indexDiscoveredItemsSaveData = saveData and saveData.indexDiscoveredItems or nil
	if indexDiscoveredItemsSaveData then
		self.indexDiscoveredItems = indexDiscoveredItemsSaveData
	else
		self.indexDiscoveredItems = {}
	end

	local indexClaimedRewardsSaveData = saveData and saveData.indexClaimedRewards or nil
	if indexClaimedRewardsSaveData then
		self.indexClaimedRewards = indexClaimedRewardsSaveData
	else
		self.indexClaimedRewards = {}
	end

	local indexStatBuffsSaveData = saveData and saveData.indexStatBuffs or nil
	if indexStatBuffsSaveData then
		self.indexStatBuffs = indexStatBuffsSaveData
	else
		self.indexStatBuffs = {}
	end

	self.indexMutationChancePercent = (saveData and saveData.indexMutationChancePercent) or 0

	local indexDiscoveredMutationsSaveData = saveData and saveData.indexDiscoveredMutations or nil
	if indexDiscoveredMutationsSaveData then
		self.indexDiscoveredMutations = {}
		for mutationStr in indexDiscoveredMutationsSaveData do
			local mutation = tonumber(mutationStr)
			if not enums.isValidValue(enums.Mutations, mutation) then
				print("ignoring mutation that no longer exists", mutation)
				continue
			end
			self.indexDiscoveredMutations[mutation] = true
		end
	else
		self.indexDiscoveredMutations = {}
	end

	self:updatePlayerVariables()

	self.hasBackfilledBlueprintIndex = (saveData and saveData.hasBackfilledBlueprintIndex) or false
	self:backfillBlueprintIndexDiscoveryIfNeeded()

	local indexData = indexManager:getFullIndexDataForPlayer(self.player)
	RemoteEvents.NotifyIndexData:FireClient(self.player, indexData)

	local contextualFtueStateSaveData = saveData and saveData.contextualFtueState or nil
	if contextualFtueStateSaveData then
		self.contextualFtueState = contextualFtueStateSaveData
	else
		self.contextualFtueState = self:getDefaultContextualFtueState()
	end

	local latestPromptGroupTimeSaveData = saveData and saveData.latestPromptGroupSaveTime or nil
	if latestPromptGroupTimeSaveData then
		self.latestPromptGroupTime = latestPromptGroupTimeSaveData
	else
		self.latestPromptGroupTime = 0
	end

	self.hasClaimedGroupLuck = (saveData and saveData.hasClaimedGroupLuck) or false
	if self.hasClaimedGroupLuck then
		self.isInCommunityGroup = true
		self:updateLuckInGuiData()
	end

	self:updatePlayerFeaturesInGuiData()

	-- "big" progress done here--some items need to do their own progress earlier
	self:processOfflineTime(offlineElapsedSec)
end

function PlayerData.trySetOption(self: PlayerData, playerOptionKey: any, value: any)
	if playerOptionKey == PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value
		return true
	end

	if playerOptionKey == PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value
		return true
	end

	if playerOptionKey == PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value
		return true
	end

	if playerOptionKey == PlayerOptionKeys.POTATO_MODE_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value
		return true
	end

	if playerOptionKey == PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value

		gameController:notifyPlayerReceiveTradeRequestsOptionChanged(self.player)

		return true
	end

	if playerOptionKey == PlayerOptionKeys.MERGE_ALL_ENABLED then
		if not Validate.isBoolean(value) then
			warn("invalid option value", playerOptionKey, value)
			return false
		end

		self.options[playerOptionKey] = value
		return true
	end

	print("player sent unknown option", self.player, playerOptionKey, value)
	return false
end

function PlayerData.getStarterOfferProgress(self: PlayerData)
	return self.starterOfferProgress
end

function PlayerData.setStarterOfferProgress(self: PlayerData, starterOfferProgress: any)
	self.starterOfferProgress = starterOfferProgress
end

-- buy store purchase counts (itemName -> count bought) for the given restock era; the record
-- lazily replaces itself whenever the era changes, so counts from an old era (or an old
-- session) never apply. The returned table is live: callers mutate it to record purchases,
-- and ProfileStore persists it with the rest of the save on its normal cadence.
function PlayerData.getBuyStorePurchaseCountsForEra(self: PlayerData, era: number): any
	if self.buyStorePurchases.era ~= era then
		self.buyStorePurchases = { era = era, counts = {} }
	end
	return self.buyStorePurchases.counts
end

function PlayerData.getFtueProgress(self: PlayerData)
	return self.ftueProgress
end

function PlayerData.setFtueProgress(self: PlayerData, ftueProgress: any)
	self.ftueProgress = ftueProgress
end

function PlayerData.resetFtueProgress(self: PlayerData)
	self:setFtueProgress(ftueManager:getDisabledFtueProgress())
end

function PlayerData.restartFtueProgress(self: PlayerData)
	self:setFtueProgress(ftueManager:getDefaultFtueProgress())
end

function PlayerData.isInFtue(self: PlayerData)
	return ftueManager:isInFtue(self.ftueProgress)
end

function PlayerData.getFirstSessionOfferState(self: PlayerData)
	return self.firstSessionOfferState
end

function PlayerData.setFirstSessionOfferState(self: PlayerData, firstSessionOfferState: any)
	self.firstSessionOfferState = firstSessionOfferState
end

function PlayerData.resetFirstSessionOfferState(self: PlayerData)
	self:setFirstSessionOfferState(firstSessionOfferManager:getDefaultFirstSessionOfferState())
end

function PlayerData.restartFirstSessionOfferState(self: PlayerData)
	self:setFirstSessionOfferState(firstSessionOfferManager:getDefaultFirstSessionOfferState())
	firstSessionOfferManager:startOffer(self.player)
end

function PlayerData.setRedeemableFirstSessionOfferState(self: PlayerData)
	self:setFirstSessionOfferState(firstSessionOfferManager:getDefaultFirstSessionOfferState())
	firstSessionOfferManager:setRedeemable(self.player)
end

function PlayerData.hasCodeRedeemed(self: PlayerData, code: any)
	for _, codeRedeemData in self.codesRedeemed do
		if codeRedeemData.codeName ~= code then
			continue
		end

		return true
	end

	return false
end

function PlayerData.addCodeRedeemed(self: PlayerData, code: any)
	table.insert(self.codesRedeemed, {
		codeName = code,
		time = math.floor(workspace:GetServerTimeNow()),
	})
end

function PlayerData.resetCodesRedeemed(self: PlayerData)
	self.codesRedeemed = {}
end

function PlayerData.hasDiscoveredIndexItem(self: PlayerData, itemName: any)
	return self.indexDiscoveredItems[itemName] == true
end

function PlayerData.markIndexItemDiscovered(self: PlayerData, itemName: any)
	self.indexDiscoveredItems[itemName] = true
end

function PlayerData.getIndexDiscoveredItems(self: PlayerData)
	return self.indexDiscoveredItems
end

function PlayerData.hasClaimedIndexReward(self: PlayerData, tierId: any)
	return self.indexClaimedRewards[tierId] == true
end

function PlayerData.markIndexRewardClaimed(self: PlayerData, tierId: any)
	self.indexClaimedRewards[tierId] = true
end

function PlayerData.grantIndexStatBuff(self: PlayerData, attributeName: any, amount: any)
	self.indexStatBuffs[attributeName] = (self.indexStatBuffs[attributeName] or 0) + amount
	self:updatePlayerVariables()
end

function PlayerData.grantIndexMutationChanceBuff(self: PlayerData, amount: any)
	if typeof(amount) ~= "number" then
		warn("invalid index mutation chance buff amount, skipping", amount, self.player)
		return
	end

	self.indexMutationChancePercent += amount
	self:updateLuckInGuiData()
end

function PlayerData.backfillBlueprintIndexDiscoveryIfNeeded(self: PlayerData)
	if self.hasBackfilledBlueprintIndex then
		return
	end

	for _, chain in indexManager:getCategoryChains(indexCatalog.Category.BLUEPRINTS) do
		for _, itemName in chain.itemNames do
			local isOwned = itemManager:getItemCountByUserIdAndName(self.player.UserId, itemName) > 0

			local vanityComponentName = plotsManager:getVanityComponentNameForBlueprintName(itemName)
			local isUnlocked = vanityComponentName ~= nil and not self:isVanityComponentLocked(vanityComponentName)

			if isOwned or isUnlocked then
				indexManager:notifyItemDiscoveredIfNew(self.player, self, itemName)
			end
		end
	end

	self.hasBackfilledBlueprintIndex = true
end

function PlayerData.hasDiscoveredIndexMutation(self: PlayerData, mutationTier: any)
	return self.indexDiscoveredMutations[mutationTier] == true
end

function PlayerData.markIndexMutationDiscovered(self: PlayerData, mutationTier: any)
	self.indexDiscoveredMutations[mutationTier] = true
end

function PlayerData.getIndexDiscoveredMutations(self: PlayerData)
	return self.indexDiscoveredMutations
end

function PlayerData.tryConsumeIndexRefreshCooldown(self: PlayerData)
	local now = workspace:GetServerTimeNow()

	if (now - self.lastIndexRefreshTime) < 1 then
		return false
	end

	self.lastIndexRefreshTime = now
	return true
end

function PlayerData.resetIndexData(self: PlayerData)
	self.indexDiscoveredItems = {}
	self.indexClaimedRewards = {}
	self.indexDiscoveredMutations = {}
	self.indexStatBuffs = {}
	self.indexMutationChancePercent = 0
end

function PlayerData.resetIndexRewards(self: PlayerData)
	self.indexClaimedRewards = {}
	self.indexStatBuffs = {}
	self.indexMutationChancePercent = 0
	self:updatePlayerVariables()
end

function PlayerData.resetIndexMutationData(self: PlayerData)
	self.indexDiscoveredMutations = {}
end

function PlayerData.getDefaultContextualFtueState(self: PlayerData)
	return { triggered = {} }
end

function PlayerData.hasTriggeredContextualFtue(self: PlayerData, id: any)
	return self.contextualFtueState.triggered[id] == true
end

function PlayerData.markContextualFtueTriggered(self: PlayerData, id: any)
	self.contextualFtueState.triggered[id] = true
end

function PlayerData.resetContextualFtueState(self: PlayerData)
	self.contextualFtueState = self:getDefaultContextualFtueState()
end

function PlayerData.getTradeRequestCount(self: PlayerData)
	return self.tradeRequestCount
end

function PlayerData.resetTradeRequestCount(self: PlayerData)
	self.tradeRequestCount = 0
end

function PlayerData.incrementTradeRequestCount(self: PlayerData)
	self.tradeRequestCount += 1
end

function PlayerData.resetPromptGroupTime(self: PlayerData)
	self.latestPromptGroupTime = 0
end

function PlayerData.canMergeAll(self: PlayerData)
	local level = playerAttributesManager:get(self.player, PlayerAttributeKeys.LEVEL_NATURE)
	local isMergeAllUnlocked = (level >= Constants.MERGE_ALL_UNLOCK_LEVEL)

	return isMergeAllUnlocked
end

function PlayerData.getSaveData(self: PlayerData): any
	self:addToStat("totalPlaySec", math.ceil(workspace:GetServerTimeNow() - self.sessionStartTime))

	local saveData = {}
	saveData.saveTime = workspace:GetServerTimeNow()
	saveData.player = playerAttributesManager:getSaveDataForPlayer(self.player)
	saveData.items = itemManager:getSaveDataForPlayer(self.player)
	saveData.stats = self.stats
	saveData.abilityStatuses = self.abilityStatuses
	saveData.purchasedSlotUnlocks = self.purchasedSlotUnlocks
	saveData.starterOfferProgress = self.starterOfferProgress
	saveData.buyStorePurchases = self.buyStorePurchases
	saveData.ftueProgress = self.ftueProgress
	saveData.firstSessionOfferState = self.firstSessionOfferState
	saveData.codesRedeemed = self.codesRedeemed
	saveData.contextualFtueState = self.contextualFtueState
	saveData.indexDiscoveredItems = self.indexDiscoveredItems
	saveData.indexClaimedRewards = self.indexClaimedRewards
	saveData.indexDiscoveredMutations = self.indexDiscoveredMutations
	saveData.indexStatBuffs = self.indexStatBuffs
	saveData.indexMutationChancePercent = self.indexMutationChancePercent
	saveData.hasBackfilledBlueprintIndex = self.hasBackfilledBlueprintIndex
	saveData.vanityState = self.vanityState
	saveData.vanityComponentStates = self:getNonDefaultVanityComponentStates()
	saveData.vanityPlacements = self.vanityPlacements
	saveData.vanityAreaStates = self.vanityAreaStates
	saveData.latestPromptGroupTime = self.latestPromptGroupTime
	saveData.hasClaimedGroupLuck = self.hasClaimedGroupLuck

	return saveData
end

function PlayerData.getOptions(self: PlayerData)
	return self.options
end

function PlayerData.getOption(self: PlayerData, playerOptionKey: any)
	return self.options[playerOptionKey]
end

function PlayerData.getDevToolSettings(self: PlayerData)
	return self.devToolSettings
end

function PlayerData.setDevToolSetting(self: PlayerData, name: any, value: any)
	self.devToolSettings[name] = value
end

-- setup data that goes only to this one client
function PlayerData.initPlayerGuiData(self: PlayerData)
	local splendidDataFolder = Instance.new("ScreenGui")
	splendidDataFolder.Name = Constants.SPLENDID_DATA_NAME
	splendidDataFolder.ResetOnSpawn = false

	-- add all sellable items
	local sellStoreDataFolder = Instance.new("Folder")
	sellStoreDataFolder.Name = "SellStore"
	sellStoreDataFolder.Parent = splendidDataFolder

	local itemNames = gameController:getAllSellableItemNames()
	for _, itemName in itemNames do
		local itemData = objectDataStore:getObjectDataByName(itemName)

		local sellableItem = Instance.new("Part")
		sellableItem.Name = itemData.name
		sellableItem:SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)
		sellableItem:SetAttribute(Attributes.SELL_NAME, itemData.mixins.sell.name)
		sellableItem:SetAttribute(Attributes.COINS, itemData.mixins.sell.coins)
		sellableItem:SetAttribute(Attributes.ASSET_ID, itemData.mixins.sell.previewAssetId)
		sellableItem:SetAttribute(Attributes.COLOR, utils.get2DColorForPrimaryElement(itemData.primaryElement))
		sellableItem.Parent = sellStoreDataFolder
	end

	local gemsDataFolder = Instance.new("Folder")
	gemsDataFolder.Name = "Gems"
	gemsDataFolder.Parent = splendidDataFolder

	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		local itemName = Elements.getGemItemNameForPrimaryElement(primaryElement)
		local itemData = objectDataStore:getObjectDataByName(itemName)

		local gemData = Instance.new("Part")
		gemData.Name = tostring(enums.getName(enums.PrimaryElements, primaryElement))
		gemData:SetAttribute(Attributes.ASSET_ID, itemData.mixins.sell.previewAssetId)
		gemData:SetAttribute(Attributes.COLOR, utils.get2DColorForPrimaryElement(primaryElement))
		gemData.Parent = gemsDataFolder
	end

	if self:hasDevToolAccess() then
		-- add some object and item data for dev tools

		local devToolsDataFolder = Instance.new("Folder")
		devToolsDataFolder.Name = "DevTools"
		devToolsDataFolder.Parent = splendidDataFolder

		local dragonDataFolder = Instance.new("Folder")
		dragonDataFolder.Name = "Dragons"
		dragonDataFolder.Parent = devToolsDataFolder

		local dragonNames = gameController:getAllDragonNames()
		table.sort(dragonNames, devToolItemCompare)
		for _, name in dragonNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			inst:SetAttribute(Attributes.CASTER_PATH, itemData.casterPath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = dragonDataFolder
		end

		local dragonEggDataFolder = Instance.new("Folder")
		dragonEggDataFolder.Name = "DragonEggs"
		dragonEggDataFolder.Parent = devToolsDataFolder

		local dragonEggNames = gameController:getAllDragonEggNames()
		table.sort(dragonEggNames, devToolItemCompare)
		for _, name in dragonEggNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = dragonEggDataFolder
		end

		local cropDataFolder = Instance.new("Folder")
		cropDataFolder.Name = "Crops"
		cropDataFolder.Parent = devToolsDataFolder

		local cropNames = gameController:getAllCropNames()
		table.sort(cropNames, devToolItemCompare)
		for _, name in cropNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = cropDataFolder
		end

		local crystalDataFolder = Instance.new("Folder")
		crystalDataFolder.Name = "Crystals"
		crystalDataFolder.Parent = devToolsDataFolder

		local crystalNames = gameController:getAllCrystalNames()
		table.sort(crystalNames, devToolItemCompare)
		for _, name in crystalNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = crystalDataFolder
		end

		local packDataFolder = Instance.new("Folder")
		packDataFolder.Name = "Packs"
		packDataFolder.Parent = devToolsDataFolder

		local packNames = gameController:getAllPackNames()
		table.sort(packNames, devToolItemCompare)
		for _, name in packNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = packDataFolder
		end

		local keyDataFolder = Instance.new("Folder")
		keyDataFolder.Name = "Keys"
		keyDataFolder.Parent = devToolsDataFolder

		local keyNames = gameController:getAllKeyNames()
		table.sort(keyNames, devToolItemCompare)
		for _, name in keyNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = keyDataFolder
		end

		local blueprintDataFolder = Instance.new("Folder")
		blueprintDataFolder.Name = "Blueprints"
		blueprintDataFolder.Parent = devToolsDataFolder

		local blueprintNames = gameController:getAllBlueprintNames()
		table.sort(blueprintNames, devToolItemCompare)
		for _, name in blueprintNames do
			local itemData = objectDataStore:getObjectDataByName(name)
			local inst = Instance.new("Part")
			inst.Name = itemData.name
			inst:SetAttribute(Attributes.TEMPLATE_PATH, itemData.templatePath)
			local cameraPositionData = itemData.indexCameraPosition or (itemData.buy and itemData.buy.cameraPosition)
			if cameraPositionData then
				inst:SetAttribute(
					Attributes.SCREENSHOT_CAMERA_POSITION,
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end
			inst.Parent = blueprintDataFolder
		end

		local islandDataFolder = Instance.new("Folder")
		islandDataFolder.Name = "Islands"
		islandDataFolder.Parent = devToolsDataFolder

		local islandNames = gameController:getAllIslandNames()
		table.sort(islandNames, devToolIslandCompare)
		for _, name in islandNames do
			local inst = Instance.new("Part")
			inst.Name = name
			inst.Parent = islandDataFolder
		end
	end

	local weatherDataFolder = Instance.new("Folder")
	weatherDataFolder.Name = "Weather"
	weatherDataFolder.Parent = splendidDataFolder

	local weatherNames = weatherDataStore:getAllWeatherNames()
	for _, weatherName in weatherNames do
		local weatherData = weatherDataStore:getWeatherDataByName(weatherName) :: any
		local item = Instance.new("Part")
		item.Name = weatherName
		item:SetAttribute(Attributes.ASSET_ID, weatherData.iconAssetId)
		item.Parent = weatherDataFolder
	end

	local instantOpenCrystalDataFolder = Instance.new("Folder")
	instantOpenCrystalDataFolder.Name = "InstantOpenCrystal"
	instantOpenCrystalDataFolder.Parent = splendidDataFolder

	for _, instantOpenCrystalData in crystalTimeData.instantOpenCrystal do
		local item = Instance.new("Part")
		item.Name = tostring(instantOpenCrystalData.durationSec)
		item:SetAttribute(Attributes.PRODUCT_ID, instantOpenCrystalData.robuxProductId)
		item:SetAttribute(Attributes.DURATION, instantOpenCrystalData.durationSec)
		item.Parent = instantOpenCrystalDataFolder
	end

	local playersDataFolder = Instance.new("Folder")
	playersDataFolder.Name = "Players"
	playersDataFolder.Parent = splendidDataFolder
	for _, player in playersService:GetPlayers() do
		self:createOrUpdateOtherPlayerInGuiData(splendidDataFolder, player)
	end

	local gameConfigDataFolder = Instance.new("Folder")
	gameConfigDataFolder.Name = "GameConfig"
	gameConfigDataFolder.Parent = splendidDataFolder

	self:createOrUpdateGameConfigInGuiData(splendidDataFolder)

	local vanityDataFolder = Instance.new("Folder")
	vanityDataFolder.Name = "Vanity"
	vanityDataFolder.Parent = splendidDataFolder

	local vanityInnerPlotDataFolder = Instance.new("Folder")
	vanityInnerPlotDataFolder.Name = Constants.VANITY_INNER_PLOT_NAME
	vanityInnerPlotDataFolder.Parent = vanityDataFolder
	local mainPlotInnerLandNames = plotsManager:getAllMainPlotInnerNames()
	table.sort(mainPlotInnerLandNames, vanityComponentNameCompare)
	for i, name in mainPlotInnerLandNames do
		local vanityComponentData = plotsManager:getVanityComponentDataByName(name)
		if not vanityComponentData.blueprintName then
			continue
		end
		local inst = Instance.new("Part")
		inst.Name = name
		inst:SetAttribute(Attributes.INDEX, i)
		inst:SetAttribute(Attributes.DISPLAY_NAME, vanityComponentData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT, vanityComponentData.blueprintName)
		local blueprintItemData = objectDataStore:getObjectDataByName(vanityComponentData.blueprintName)
		inst:SetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME, blueprintItemData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH, blueprintItemData.templatePath)
		inst:SetAttribute(Attributes.RARITY, vanityComponentData.rarity)
		inst:SetAttribute(Attributes.PRODUCT_ID, vanityComponentData.robuxProductId)
		local innerPlacement: number = enums.VanityPlacements.MAIN_PLOT_INNER
		local innerTemplatePath: string = vanityComponentData.templatePath
		inst:SetAttribute(Attributes.TEMPLATE_PATHS, string.format("%i %s", innerPlacement, innerTemplatePath))

		-- dynamic data added in updateVanityDataInGuiData()

		inst.Parent = vanityInnerPlotDataFolder
	end

	local vanityOuterPlotDataFolder = Instance.new("Folder")
	vanityOuterPlotDataFolder.Name = Constants.VANITY_OUTER_PLOT_NAME
	vanityOuterPlotDataFolder.Parent = vanityDataFolder
	local mainPlotOuterLandNames = plotsManager:getAllMainPlotOuterNames()
	table.sort(mainPlotOuterLandNames, vanityComponentNameCompare)
	for i, name in mainPlotOuterLandNames do
		local vanityComponentData = plotsManager:getVanityComponentDataByName(name)
		if not vanityComponentData.blueprintName then
			continue
		end
		local inst = Instance.new("Part")
		inst.Name = name
		inst:SetAttribute(Attributes.INDEX, i)
		inst:SetAttribute(Attributes.DISPLAY_NAME, vanityComponentData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT, vanityComponentData.blueprintName)
		local blueprintItemData = objectDataStore:getObjectDataByName(vanityComponentData.blueprintName)
		inst:SetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME, blueprintItemData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH, blueprintItemData.templatePath)
		inst:SetAttribute(Attributes.RARITY, vanityComponentData.rarity)
		inst:SetAttribute(Attributes.PRODUCT_ID, vanityComponentData.robuxProductId)
		local outerPlacement: number = enums.VanityPlacements.MAIN_PLOT_OUTER
		local outerTemplatePath: string = vanityComponentData.templatePath
		inst:SetAttribute(Attributes.TEMPLATE_PATHS, string.format("%i %s", outerPlacement, outerTemplatePath))

		-- dynamic data added in updateVanityDataInGuiData()

		inst.Parent = vanityOuterPlotDataFolder
	end

	local vanityFenceDataFolder = Instance.new("Folder")
	vanityFenceDataFolder.Name = Constants.VANITY_FENCE_NAME
	vanityFenceDataFolder.Parent = vanityDataFolder
	local fenceNames = plotsManager:getAllFenceNames()
	table.sort(fenceNames, vanityComponentNameCompare)
	for i, name in fenceNames do
		local vanityComponentData = plotsManager:getVanityComponentDataByName(name)
		if not vanityComponentData.blueprintName then
			continue
		end
		local inst = Instance.new("Part")
		inst.Name = name
		inst:SetAttribute(Attributes.INDEX, i)
		inst:SetAttribute(Attributes.DISPLAY_NAME, vanityComponentData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT, vanityComponentData.blueprintName)
		local blueprintItemData = objectDataStore:getObjectDataByName(vanityComponentData.blueprintName)
		inst:SetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME, blueprintItemData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH, blueprintItemData.templatePath)
		inst:SetAttribute(Attributes.RARITY, vanityComponentData.rarity)
		inst:SetAttribute(Attributes.PRODUCT_ID, vanityComponentData.robuxProductId)

		local vanityPlacements: { number } = {
			enums.VanityPlacements.MAIN_PLOT_FENCE_1,
			enums.VanityPlacements.MAIN_PLOT_FENCE_2,
			enums.VanityPlacements.MAIN_PLOT_FENCE_3,
			enums.VanityPlacements.MAIN_PLOT_FENCE_4,
			enums.VanityPlacements.MAIN_PLOT_FENCE_5,
			enums.VanityPlacements.MAIN_PLOT_FENCE_6,
			enums.VanityPlacements.MAIN_PLOT_FENCE_7,
			enums.VanityPlacements.MAIN_PLOT_FENCE_8,
			enums.VanityPlacements.MAIN_PLOT_FENCE_9,
		}
		local s = ""
		for _, vanityPlacement in vanityPlacements do
			if s ~= "" then
				s = s .. " "
			end
			local templatePath: string = vanityComponentData.templatePaths[vanityPlacement]
			s = s .. string.format("%i %s", vanityPlacement, templatePath)
		end
		inst:SetAttribute(Attributes.TEMPLATE_PATHS, s)

		-- dynamic data added in updateVanityDataInGuiData()

		inst.Parent = vanityFenceDataFolder
	end

	local vanityExpansionInnerDataFolder = Instance.new("Folder")
	vanityExpansionInnerDataFolder.Name = Constants.VANITY_EXPANSION_INNER_NAME
	vanityExpansionInnerDataFolder.Parent = vanityDataFolder
	local expansionInnerNames = plotsManager:getAllExpansionInnerNames()
	table.sort(expansionInnerNames, vanityComponentNameCompare)
	for i, name in expansionInnerNames do
		local vanityComponentData = plotsManager:getVanityComponentDataByName(name)
		if not vanityComponentData.blueprintName then
			continue
		end
		local inst = Instance.new("Part")
		inst:SetAttribute(Attributes.INDEX, i)
		inst.Name = name
		inst:SetAttribute(Attributes.DISPLAY_NAME, vanityComponentData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT, vanityComponentData.blueprintName)
		local blueprintItemData = objectDataStore:getObjectDataByName(vanityComponentData.blueprintName)
		inst:SetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME, blueprintItemData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH, blueprintItemData.templatePath)
		inst:SetAttribute(Attributes.RARITY, vanityComponentData.rarity)
		inst:SetAttribute(Attributes.PRODUCT_ID, vanityComponentData.robuxProductId)

		local vanityPlacements: { number } = {
			enums.VanityPlacements.EXPANSION_1_INNER,
			enums.VanityPlacements.EXPANSION_2_INNER,
			enums.VanityPlacements.EXPANSION_3_INNER,
			enums.VanityPlacements.EXPANSION_4_INNER,
		}
		local s = ""
		for _, vanityPlacement in vanityPlacements do
			if s ~= "" then
				s = s .. " "
			end
			local templatePath: string = vanityComponentData.templatePaths[vanityPlacement]
			s = s .. string.format("%i %s", vanityPlacement, templatePath)
		end
		inst:SetAttribute(Attributes.TEMPLATE_PATHS, s)

		-- dynamic data added in updateVanityDataInGuiData()

		inst.Parent = vanityExpansionInnerDataFolder
	end

	local vanityExpansionOuterDataFolder = Instance.new("Folder")
	vanityExpansionOuterDataFolder.Name = Constants.VANITY_EXPANSION_OUTER_NAME
	vanityExpansionOuterDataFolder.Parent = vanityDataFolder
	local expansionOuterNames = plotsManager:getAllExpansionOuterNames()
	table.sort(expansionOuterNames, vanityComponentNameCompare)
	for i, name in expansionOuterNames do
		local vanityComponentData = plotsManager:getVanityComponentDataByName(name)
		if not vanityComponentData.blueprintName then
			continue
		end
		local inst = Instance.new("Part")
		inst.Name = name
		inst:SetAttribute(Attributes.INDEX, i)
		inst:SetAttribute(Attributes.DISPLAY_NAME, vanityComponentData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT, vanityComponentData.blueprintName)
		local blueprintItemData = objectDataStore:getObjectDataByName(vanityComponentData.blueprintName)
		inst:SetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME, blueprintItemData.displayName)
		inst:SetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH, blueprintItemData.templatePath)
		inst:SetAttribute(Attributes.RARITY, vanityComponentData.rarity)
		inst:SetAttribute(Attributes.PRODUCT_ID, vanityComponentData.robuxProductId)

		local vanityPlacements: { number } = {
			enums.VanityPlacements.EXPANSION_1_OUTER,
			enums.VanityPlacements.EXPANSION_2_OUTER,
			enums.VanityPlacements.EXPANSION_3_OUTER,
			enums.VanityPlacements.EXPANSION_4_OUTER,
		}
		local s = ""
		for _, vanityPlacement in vanityPlacements do
			if s ~= "" then
				s = s .. " "
			end
			local templatePath: string = vanityComponentData.templatePaths[vanityPlacement]
			s = s .. string.format("%i %s", vanityPlacement, templatePath)
		end
		inst:SetAttribute(Attributes.TEMPLATE_PATHS, s)

		-- dynamic data added in updateVanityDataInGuiData()

		inst.Parent = vanityExpansionOuterDataFolder
	end

	self:updateVanityDataInGuiData(splendidDataFolder)

	local vanityPlacementsDataFolder = Instance.new("Folder")
	vanityPlacementsDataFolder.Name = Constants.VANITY_PLACEMENTS_NAME
	vanityPlacementsDataFolder.Parent = vanityDataFolder

	self:updateVanityPlacementDataInGuiData(splendidDataFolder)

	local vanityAreasDataFolder = Instance.new("Folder")
	vanityAreasDataFolder.Name = Constants.VANITY_AREAS_NAME
	vanityAreasDataFolder.Parent = vanityDataFolder

	self:updateVanityAreaDataInGuiData(splendidDataFolder)

	local mutationStoreDataFolder = Instance.new("Folder")
	mutationStoreDataFolder.Name = "MutationStore"
	mutationStoreDataFolder.Parent = splendidDataFolder
	mutationStoreManager:addClientDataToFolder(mutationStoreDataFolder)

	local vanityStoreDataFolder = Instance.new("Folder")
	vanityStoreDataFolder.Name = "VanityStore"
	vanityStoreDataFolder.Parent = splendidDataFolder
	vanityStoreManager:addClientDataToFolder(vanityStoreDataFolder)

	local luckDataFolder = Instance.new("Folder")
	luckDataFolder.Name = "Luck"
	luckDataFolder.Parent = splendidDataFolder

	local item = Instance.new("Part")
	item.Name = "State"
	item.Parent = luckDataFolder

	self:updateLuckInGuiData(splendidDataFolder)

	-- this runs before the player's state is loaded, as a reminder
	local playerFeaturesDataFolder = Instance.new("Folder")
	playerFeaturesDataFolder.Name = "PlayerFeatures"
	playerFeaturesDataFolder.Parent = splendidDataFolder

	self:updatePlayerFeaturesInGuiData(splendidDataFolder)

	-- and now send this data to this client
	splendidDataFolder.Parent = self.player.PlayerGui
end

function PlayerData.createOrUpdateOtherPlayerInGuiData(self: PlayerData, splendidDataFolder: any, otherPlayer: any)
	local playersDataFolder = splendidDataFolder:FindFirstChild("Players")
	local item = playersDataFolder:FindFirstChild(otherPlayer.Name)

	local playerData = gameController:getPlayerData(otherPlayer)
	if not playerData then
		return
	end
	if not playerData:hasProfile() then
		return
	end

	if not item then
		item = Instance.new("Part")
		item.Name = otherPlayer.Name
	end

	for _, primaryElement in Elements.getPrimaryElementsSorted() do
		local name = enums.getPublicName(enums.PrimaryElements, primaryElement)
		item:SetAttribute(
			name,
			playerAttributesManager:get(otherPlayer, Elements.getLevelKeyForPrimaryElement(primaryElement))
		)
	end
	item:SetAttribute(
		Constants.RECEIVE_TRADE_REQUESTS_ENABLED_NAME,
		playerData:getOption(PlayerOptionKeys.RECEIVE_TRADE_REQUESTS_ENABLED)
	)

	if item.Parent ~= playersDataFolder then
		item.Parent = playersDataFolder
	end
end

function PlayerData.createOrUpdateGameConfigInGuiData(self: PlayerData, splendidDataFolder: any)
	local gameConfigDataFolder = splendidDataFolder:FindFirstChild("GameConfig")
	gameConfigDataFolder:SetAttribute(
		GameConfigKeys.tradingEnabled,
		gameController:getConfigValue(GameConfigKeys.tradingEnabled)
	)
	gameConfigDataFolder:SetAttribute(
		GameConfigKeys.indexEnabled,
		gameController:isIndexEnabled()
	)
end

function PlayerData.updateVanityDataInGuiData(self: PlayerData, splendidDataFolder: any)
	if not splendidDataFolder then
		local playerGui = self.player:WaitForChild("PlayerGui")
		splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
		if not splendidDataFolder then
			return
		end
	end

	local vanityDataFolder = splendidDataFolder:FindFirstChild("Vanity")

	local vanityInnerPlotDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_INNER_PLOT_NAME)
	for _, inst in vanityInnerPlotDataFolder:GetChildren() do
		local vanityComponentName = inst.Name

		inst:SetAttribute(Attributes.STATE, self.vanityComponentStates[vanityComponentName])

		-- whether we currently can unlock it, if it's in that state (do we have a blueprint)
		local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
		local itemName = vanityComponentData.blueprintName
		local isUnlockable = self:doesPlayerHaveItemCount(itemName, 1)
		inst:SetAttribute(Attributes.UNLOCKABLE, isUnlockable)
	end

	local vanityOuterPlotDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_OUTER_PLOT_NAME)
	for _, inst in vanityOuterPlotDataFolder:GetChildren() do
		local vanityComponentName = inst.Name

		inst:SetAttribute(Attributes.STATE, self.vanityComponentStates[vanityComponentName])

		-- whether we currently can unlock it, if it's in that state (do we have a blueprint)
		local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
		local itemName = vanityComponentData.blueprintName
		local isUnlockable = self:doesPlayerHaveItemCount(itemName, 1)
		inst:SetAttribute(Attributes.UNLOCKABLE, isUnlockable)
	end

	local vanityFenceDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_FENCE_NAME)
	for _, inst in vanityFenceDataFolder:GetChildren() do
		local vanityComponentName = inst.Name

		inst:SetAttribute(Attributes.STATE, self.vanityComponentStates[vanityComponentName])

		-- whether we currently can unlock it, if it's in that state (do we have a blueprint)
		local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
		local itemName = vanityComponentData.blueprintName
		local isUnlockable = self:doesPlayerHaveItemCount(itemName, 1)
		inst:SetAttribute(Attributes.UNLOCKABLE, isUnlockable)
	end

	local vanityExpansionInnerDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_EXPANSION_INNER_NAME)
	for _, inst in vanityExpansionInnerDataFolder:GetChildren() do
		local vanityComponentName = inst.Name

		inst:SetAttribute(Attributes.STATE, self.vanityComponentStates[vanityComponentName])

		-- whether we currently can unlock it, if it's in that state (do we have a blueprint)
		local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
		local itemName = vanityComponentData.blueprintName
		local isUnlockable = self:doesPlayerHaveItemCount(itemName, 1)
		inst:SetAttribute(Attributes.UNLOCKABLE, isUnlockable)
	end

	local vanityExpansionOuterDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_EXPANSION_OUTER_NAME)
	for _, inst in vanityExpansionOuterDataFolder:GetChildren() do
		local vanityComponentName = inst.Name

		inst:SetAttribute(Attributes.STATE, self.vanityComponentStates[vanityComponentName])

		-- whether we currently can unlock it, if it's in that state (do we have a blueprint)
		local vanityComponentData = plotsManager:getVanityComponentDataByName(vanityComponentName)
		local itemName = vanityComponentData.blueprintName
		local isUnlockable = self:doesPlayerHaveItemCount(itemName, 1)
		inst:SetAttribute(Attributes.UNLOCKABLE, isUnlockable)
	end
end

function PlayerData.updateVanityPlacementDataInGuiData(self: PlayerData, splendidDataFolder: any)
	if not splendidDataFolder then
		local playerGui = self.player:WaitForChild("PlayerGui")
		splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
		if not splendidDataFolder then
			return
		end
	end

	local vanityDataFolder = splendidDataFolder:FindFirstChild("Vanity")

	local vanityPlacementsDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_PLACEMENTS_NAME)

	-- remove anything there that no longer should be

	for _, inst in vanityPlacementsDataFolder:GetChildren() do
		local vanityPlacementName = inst.Name
		local vanityPlacement = enums.getValueByName(enums.VanityPlacements, vanityPlacementName)
		if not self.vanityPlacements[vanityPlacement] then
			inst:Destroy()
		end
	end

	-- add anything new

	for vanityPlacement, vanityComponentName in self.vanityPlacements do
		local vanityPlacementName = enums.getName(enums.VanityPlacements, vanityPlacement)
		if not vanityPlacementName then
			warn("no name found for vanity placement", vanityPlacement)
			continue
		end
		local inst = vanityPlacementsDataFolder:FindFirstChild(vanityPlacementName)
		if not inst then
			inst = Instance.new("Part")
			inst.Name = vanityPlacementName
			inst.Parent = vanityPlacementsDataFolder
		end
		inst:SetAttribute(Attributes.VANITY_COMPONENT_NAME, vanityComponentName)
	end
end

function PlayerData.updateVanityAreaDataInGuiData(self: PlayerData, splendidDataFolder: any)
	if not splendidDataFolder then
		local playerGui = self.player:WaitForChild("PlayerGui")
		splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
		if not splendidDataFolder then
			return
		end
	end

	local vanityDataFolder = splendidDataFolder:FindFirstChild("Vanity")

	local vanityAreasDataFolder = vanityDataFolder:FindFirstChild(Constants.VANITY_AREAS_NAME)

	for vanityArea, vanityAreaState in self.vanityAreaStates do
		local vanityAreaName = enums.getName(enums.VanityAreas, vanityArea)
		if not vanityAreaName then
			warn("no name found for vanity area", vanityArea)
			continue
		end
		local inst = vanityAreasDataFolder:FindFirstChild(vanityAreaName)
		if not inst then
			inst = Instance.new("Part")
			inst.Name = vanityAreaName
			inst.Parent = vanityAreasDataFolder

			if vanityAreasData.unlockPurchase[vanityArea] then
				inst:SetAttribute(Attributes.COINS, vanityAreasData.unlockPurchase[vanityArea].coins)
				inst:SetAttribute(Attributes.PRODUCT_ID, vanityAreasData.unlockPurchase[vanityArea].robuxProductId)
				local vanityPlacementDecorate = PlotHelpers.getInnerVanityPlacementByVanityArea(vanityArea)
				local vanityPlacementDecorateName = enums.getName(enums.VanityPlacements, vanityPlacementDecorate)
				inst:SetAttribute(Attributes.VANITY_DECORATE_NAME, vanityPlacementDecorateName)

				local capacityStr
				if capacityData.vanityAreaCapacity[vanityArea] then
					local additionalCapacity = capacityData.vanityAreaCapacity[vanityArea]
					local maxCapacity = capacityData.itemCapacitySoftMax
					local increasePercent = math.floor(100 * additionalCapacity / maxCapacity)
					capacityStr = string.format("+%i%% CAPACITY", increasePercent)
					inst:SetAttribute(Attributes.CAPACITY_STR, capacityStr)
				end
			end
		end
		inst:SetAttribute(Attributes.VANITY_AREA_STATE, vanityAreaState)
	end
end

function PlayerData.updateLuckInGuiData(self: PlayerData, splendidDataFolder: any)
	if not splendidDataFolder then
		local playerGui = self.player:WaitForChild("PlayerGui")
		splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
		if not splendidDataFolder then
			return
		end
	end

	local luckDataFolder = splendidDataFolder:FindFirstChild("Luck")
	local item = luckDataFolder:FindFirstChild("State")

	item:SetAttribute(Attributes.PERCENT, self:getLuckPercent())
	item:SetAttribute(Attributes.TIME_LUCK_PERCENT, self:getTimeLuckPercent())
	item:SetAttribute(Attributes.FRIEND_LUCK_PERCENT, self:getFriendLuckPercent())
	item:SetAttribute(Attributes.GROUP_LUCK_PERCENT, self:getGroupLuckPercent())
	item:SetAttribute(Attributes.INDEX_LUCK_PERCENT, self:getIndexMutationChancePercent())
	local beginTime, endTime = self:getLuckTimeRange()
	item:SetAttribute(Attributes.BASE_TIME, self.sessionStartTime)
	item:SetAttribute(Attributes.BEGIN_TIME, beginTime)
	item:SetAttribute(Attributes.END_TIME, endTime)
end

function PlayerData.updatePlayerFeaturesInGuiData(self: PlayerData, splendidDataFolder: any)
	if not splendidDataFolder then
		local playerGui = self.player:WaitForChild("PlayerGui")
		splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
		if not splendidDataFolder then
			return
		end
	end

	local playerFeaturesDataFolder = splendidDataFolder:FindFirstChild("PlayerFeatures")

	playerFeaturesDataFolder:SetAttribute(Attributes.IS_MERGE_ALL_UNLOCKED, self:canMergeAll())
end

function PlayerData.getIsFriend(self: PlayerData, userId: number)
	local isSuccess, result = pcall(function()
		return self.player:IsFriendsWithAsync(userId)
	end)

	local isFriend
	if isSuccess then
		isFriend = result
	else
		warn("error testing friends")
		isFriend = false
	end

	return isFriend
end

function PlayerData.initFriendUserIds(self: PlayerData)
	--print("init existing user friend userids here")
	local userIds = gameController:getAllPlayerUserIds()

	for _, userId in userIds do
		if userId == self.player.UserId then
			-- we'll get a "notifyOtherPlayerAdded" for ourselves anyway
			continue
		end

		if self:getIsFriend(userId) then
			self.friendUserIds[userId] = true
		end
	end

	self:updateLuckInGuiData()
end

function PlayerData.notifyOtherPlayerAdded(self: PlayerData, otherPlayer: any)
	local playerGui = self.player:WaitForChild("PlayerGui")
	local splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	self:createOrUpdateOtherPlayerInGuiData(splendidDataFolder, otherPlayer)

	--print("other player added", self.player, otherPlayer)

	local isFriend = self:getIsFriend(otherPlayer.userId)

	if isFriend then
		self.friendUserIds[otherPlayer.UserId] = true

		self:updateLuckInGuiData()
	end
end

function PlayerData.notifyOtherPlayerLevelChanged(self: PlayerData, otherPlayer: any)
	local playerGui = self.player:WaitForChild("PlayerGui")
	local splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	self:createOrUpdateOtherPlayerInGuiData(splendidDataFolder, otherPlayer)
end

function PlayerData.notifyOtherPlayerReceiveTradeRequestsOptionChanged(self: PlayerData, otherPlayer: any)
	local playerGui = self.player:WaitForChild("PlayerGui")
	local splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	self:createOrUpdateOtherPlayerInGuiData(splendidDataFolder, otherPlayer)
end

function PlayerData.notifyOtherPlayerRemoved(self: PlayerData, otherPlayer: any)
	if self.friendUserIds[otherPlayer.UserId] then
		self.friendUserIds[otherPlayer.UserId] = nil

		self:updateLuckInGuiData()
	end

	local playerGui = self.player.PlayerGui
	local splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		-- we're logging out ourselves, I guess? Saw this in prod on 2026-april-27
		return
	end

	local playersDataFolder: any = splendidDataFolder:FindFirstChild("Players")
	local otherPlayerData = playersDataFolder:FindFirstChild(otherPlayer.Name)
	if not otherPlayerData then
		return
	end
	otherPlayerData:Destroy()
end

-- we're not removed yet, but about to go--any last second things go here
function PlayerData.notifyRemovingPlayer(self: PlayerData)
	if self.pendingWelcomeBackCoinCount > 0 then
		self:tryClaimWelcomeBackGift()
	end
end

function PlayerData.notifyUpdateGameConfigSnapshot(self: PlayerData)
	local playerGui = self.player:WaitForChild("PlayerGui")
	local splendidDataFolder = playerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	self:createOrUpdateGameConfigInGuiData(splendidDataFolder)
end

function PlayerData.initCharacter(self: PlayerData)
	-- a missing character or plot crashed in here before typing too
	local character = self.player.Character :: any
	utils.addTreeToCollisionGroup(character, Constants.NO_COLLIDE_GEMS_COLLISION_GROUP)

	local cframe = plotsManager:getPlotCFrameForUserId(self.player.UserId) :: CFrame
	character.HumanoidRootPart:PivotTo(
		cframe.Rotation
			+ utils.getGroundPositionForLocation(cframe.Position)
			+ Vector3.new(
				0,
				character.Humanoid.HipHeight + character.HumanoidRootPart.Size.Y / 2,
				0
			)
	)

	local humanoid: any = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		-- we try to prevent this but this is a backup safety plan
		warn("player character humanoid died, should not happen", self.player)

		-- need to take out everything from backpack and equipped tool and put them on the board, because roblox will wipe them otherwise
		local checkTools = self.player.Backpack:GetChildren()
		for _, tool in (self.player.Character :: Model):GetChildren() do
			if not tool:IsA("Tool") then
				continue
			end

			table.insert(checkTools, tool)
		end

		for _, tool in checkTools do
			local itemObj = tool:FindFirstChild("Handle")
			if not itemObj then
				-- we put the model of an item here, so it's OK
				continue
			end

			local itemId = itemObj:GetAttribute(Attributes.ITEM_ID) :: number?
			--print("looking at backpack item id", itemId)
			local item = itemManager:getItemById(itemId)
			if not item then
				warn("cannot find item from tool", itemId)
				continue
			end

			if item:getObj():IsA("Model") then
				item:setupChildPartsToObj()
			end

			item:getObj().Parent = workspace
			item:teleportToRecoveryPosition()
		end
	end)
	humanoid.HealthChanged:Connect(function(health)
		--warn("player character humanoid has new health value, should not happen", self.player, health)
	end)

	-- keep main plot loaded, ideally

	local Level = workspace:WaitForChild("Level")
	local plotIndex = plotsManager:getPlotIndexByUserId(self.player.UserId)
	local capacitySign =
		utils.findFirstDescendantWithNameAndAttribute(Level, CAPACITY_SIGN_NAME, Attributes.INDEX, plotIndex)
	-- capacitySign is a model, so we need to get a part to give to replication focus
	self.player:AddReplicationFocus((capacitySign :: any).PrimaryPart)
end

function PlayerData.getProfile(self: PlayerData)
	return self.profile
end

function PlayerData.hasProfile(self: PlayerData)
	return self.profile ~= nil
end

-- this is called BEFORE loading save data
function PlayerData.init(self: PlayerData, profile: any)
	self.profile = profile

	self:initGroupData()

	playerAttributesManager:notifyAddPlayer(self.player)

	self:initPlayerGuiData()

	self:initLeaderboardData()

	self:initLuck()
end

function PlayerData.destroy(self: PlayerData)
	print("player stats:", self.player.Name, self.stats)
	playerAttributesManager:notifyRemovePlayer(self.player)

	if self.luckTimer then
		self.luckTimer:cancel()
		self.luckTimer = nil
	end
end

function PlayerData.getDefaultSaveData(): any
	return {
		standardSave = {},
	}
end

-- the module-scope singleton below is constructed with no player; real instances always get one
function PlayerData.new(player: Player?): PlayerData
	local self: PlayerData = setmetatable({} :: PlayerDataFields, PlayerData)

	self.player = player :: Player
	self.saveOnExit = false
	self.canUseDevTools = false
	self.isInCommunityGroup = false
	self.hasClaimedGroupLuck = false

	self.isInPlot = false

	self.options = {}

	self.ridingItemId = nil
	self.latestRidingItemId = nil

	self.mergeData = nil

	self.stats = {}
	self.abilityStatuses = {}

	self.stableSlots = {}
	self.totalDragonPower = 0

	self.purchasedSlotUnlocks = {}

	self.playerVariables = {}

	self.sessionStartTime = workspace:GetServerTimeNow()

	self.starterOfferProgress = {}
	self.buyStorePurchases = { era = 0, counts = {} }
	self.ftueProgress = {}
	self.firstSessionOfferState = {}
	self.codesRedeemed = {}
	self.contextualFtueState = self:getDefaultContextualFtueState()
	self.indexDiscoveredItems = {}
	self.indexClaimedRewards = {}
	self.indexDiscoveredMutations = {}
	self.indexStatBuffs = {}
	self.indexMutationChancePercent = 0
	self.hasBackfilledBlueprintIndex = false
	self.lastIndexRefreshTime = 0
	self.vanityState = enums.PlayerVanityState.LOCKED
	self.vanityComponentStates = {}
	self.vanityPlacements = {}
	self.vanityAreaStates = {}
	self.latestPromptGroupTime = 0

	-- these can be set by dev tool controls
	self.devToolSettings = {}

	-- queue of crystals that the player may be purchasing instant-open for
	self.instantOpenCrystalItemIds = {}

	self.tradeRequestCount = 0

	self.friendUserIds = {}

	self.pendingWelcomeBackCoinCount = 0

	return self
end

function PlayerData.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = PlayerData.new()

return singleton
