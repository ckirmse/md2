--!strict

local MergeMixin = {}
MergeMixin.__index = MergeMixin

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local itemManager = require("./ItemManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
local MergeAudioParent = Effects:WaitForChild("MergeAudioParent")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
local MergePost = ParticleEffects:WaitForChild("MergePost")
local MutationCreatedParent = ParticleEffects:WaitForChild("MutationCreatedParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local contextualFtueManager = require("./ContextualFtueManager")
local ftueManager = require("./FtueManager")
local lootTableManager = require("./LootTableManager")
local MItem = require("./MItem")

local MUTATION_CLOUD_DURATION_SEC = 2

type MergeMixinFields = {
	random: Random,
}

export type MergeMixin = typeof(setmetatable({} :: MergeMixinFields, MergeMixin))

function MergeMixin.notifyItemCreated(self: MergeMixin, item: any)
	-- client depends on these attributes and tags for combining
	local itemData = item:getItemData()
	local obj = item:getObj()
	local part = item:getPart()

	--print("merge mixin adding attribute", obj, itemData.name)

	local mergeName = itemData.mixins.merge.mergeName
	if not mergeName then
		warn("item should be mergeable but missing mergeName", item)
		return
	end
	local mergeAllName = itemData.name

	part:SetAttribute(Attributes.MERGE_NAME, mergeName)
	part:SetAttribute(Attributes.MERGE_ALL_NAME, mergeAllName)
	part:SetAttribute(Attributes.USER_ID, item:getUserId())
	part:SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	-- interesting how we track the whole obj being in workspace or not, but mark the part. This is because
	-- for held models, only the primarypart is held
	obj:GetPropertyChangedSignal("Parent"):Connect(
		function ()
			if obj.Parent == workspace then
				collectionService:AddTag(part, Tags.MERGEABLE)
			else
				collectionService:RemoveTag(part, Tags.MERGEABLE)
			end
		end
	)

	item:getVenueChangedEvent():Connect(
		function(venue)
			--print("merge item", item:getItemId(), item:getItemName(), "now in venue", venue)

			if venue == enums.Venues.WORKSPACE_AVAILABLE then
				collectionService:AddTag(part, Tags.MERGEABLE)
			elseif venue == enums.Venues.PLAYER then
				collectionService:RemoveTag(part, Tags.MERGEABLE)
			elseif venue == enums.Venues.WORKSPACE_SETTLING then
				collectionService:RemoveTag(part, Tags.MERGEABLE)
			elseif venue == enums.Venues.WORKSPACE_BUSY then
				collectionService:RemoveTag(part, Tags.MERGEABLE)
			else
				warn("unknown venue", venue, "for item", item:getItemId(), item:getItemName(), "now in venue", venue)
			end

		end
	)

end

function MergeMixin.notifyItemCloned(self: MergeMixin, item: any)
	--print("told that item is a new clone", item, item:getObj(), item:getPart())
	self:notifyItemCreated(item)
end

function MergeMixin.getCircleContainingMergeItems(self: MergeMixin, triggerItemId: number, itemIds: { number }): utils.Circle
	local positions: { Vector3 } = {}
	-- callers validated the ids, so the items exist
	local triggerItem = itemManager:getItemById(triggerItemId) :: Types.Item
	table.insert(positions, triggerItem:getPart().Position)
	for _, itemId in itemIds do
		local item = itemManager:getItemById(itemId) :: Types.Item
		table.insert(positions, item:getPart().Position)
	end

	local circle = utils.getSmallestEnclosingCircleXZ(positions)

	return circle
end

function MergeMixin.canMergeItems(self: MergeMixin, player: Player, triggerItemId: number, itemIds: { number }, isMergeAll: boolean?): boolean
	-- ids were validated by the remote handler; mergeable items stack, so they are NumberItems
	local triggerItem = itemManager:getItemById(triggerItemId) :: Types.NumberItem
	local allMergingItems = {triggerItem}
	for _, itemId in itemIds do
		local item = itemManager:getItemById(itemId) :: Types.NumberItem
		table.insert(allMergingItems, item)
	end

	local mergingItemTotalCount
	if isMergeAll then
		mergingItemTotalCount = 0
		for _, item in allMergingItems do
			mergingItemTotalCount += item:getCount()
		end
	else
		mergingItemTotalCount = #allMergingItems
	end

	if mergingItemTotalCount < 3 then
		print("not enough items to merge", player, #itemIds)
		return false
	end

	if isMergeAll then
		-- merge can't mix rarities
		local mergeName = triggerItem:getItemName()
		for _, itemId in itemIds do
			local item = itemManager:getItemById(itemId) :: Types.Item
			if item:getItemName() ~= mergeName then
				print("items are of different names, cannot merge", mergeName, item)
				return false
			end
		end
	else
		-- check to make sure thy're close enough together
		local circle = self:getCircleContainingMergeItems(triggerItemId, itemIds)

		-- make sure the items are close enough to merge--but not TOO strict a check in case there's some difference in client/server understanding
		-- of position of an item, because it's moving (as the player will often be moving)
		if circle.radius > gameController:getPlayerData(player):getPlayerVariable(Attributes.MERGE_CIRCLE_RADIUS) * 1.1 then
			--print("circle containing the potentially merged stuff is", circle)
			print("items aren't close enough together to merge", circle)
			return false
		end
		--print("items close enough to merge:", positions, circle)

		-- regular merges can mix rarities; just need to share a mergeName
		local mergeName = triggerItem:getItemData().mixins.merge.mergeName
		for _, itemId in itemIds do
			local item = itemManager:getItemById(itemId) :: Types.Item
			if item:getItemData().mixins.merge.mergeName ~= mergeName then
				print("items are of different merge names, cannot merge", mergeName, item)
				return false
			end
		end

	end



	return true
end

function MergeMixin.getMutationLootTableForPlayer(self: MergeMixin, player: Player): { any }
	local playerData = gameController:getPlayerData(player)

	local lootTable = lootTableManager:getLootTable("Mutations")
	local luckPercent = playerData:getLuckPercent()
	--print("luck", player, luckPercent)

	--print("base loot table", lootTable)

	-- copy the loot table and modify based on luck
	local normalIndex: number?
	local luckLootTable: { any } = {}
	local totalDiff = 0
	for i, lootEntry in lootTable do
		local luckLootEntry: any = {}
		luckLootEntry.result = lootEntry.result
		if lootEntry.result == enums.Mutations.NORMAL then
			normalIndex = i
		else
			luckLootEntry.weight = lootEntry.weight * (1 + luckPercent / 100)
			totalDiff += luckLootEntry.weight - lootEntry.weight
		end
		table.insert(luckLootTable, luckLootEntry)
	end

	if normalIndex then
		luckLootTable[normalIndex].weight = lootTable[normalIndex].weight - totalDiff
	else
		warn("mutation loot table missing normal entry; luck will not have any effect")
	end

	--print("luck loot table", luckLootTable)

	return luckLootTable
end

-- returns an array of mutations in best-to-worst order, of size totalCount
function MergeMixin.calculateNewItemMutations(self: MergeMixin, player: Player, count: number, mergingItems: { any }): { number }
	if count < 1 then
		warn("cannot calculate new item mutations for no items", count)
		return {}
	end

	local existingMutations: { number } = {}
	for _, item in mergingItems do
		-- this is only called for mutation-capable merges, so the items are MItems
		local mitem = item :: Types.MItem
		for i = 1, mitem:getCount() do
			table.insert(existingMutations, mitem:getMutation())
		end
	end
	table.sort(existingMutations, MItem.compareMutations)

	if count > #existingMutations then
		warn("cannot calculate new item mutations larger than merging item list", count, mergingItems)
		return {}
	end

	local preserveMutations: { number } = {}
	for i = 1, count do
		table.insert(preserveMutations, existingMutations[i])
	end

	-- since we have "luck", this is pretty custom. Without luck, this:
	--local lootTable = lootTableManager:getLootTable("Mutations")
	-- with luck, we get a table and modify it
	--local lootTable = lootTableManager:getLootTable("Mutations")
	local lootTable = self:getMutationLootTableForPlayer(player)

	local mutations: { number } = {}
	for i = 1, count do
		-- calculate a mutation roll
		local mutationResult = lootTableManager:calculateLootResultsByTable(lootTable)
		local mutation = mutationResult[1].result
		--print("result of mutation roll is", mutation, enums.getName(enums.Mutations, mutation))

		if mutation ~= enums.Mutations.NORMAL then
			local item = mergingItems[1]
			analyticsManager:logEvent(player, analyticsManager.Events.GainMutation,
				{
					objectName = item:getItemName(),
					primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
					rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
					itemType = item:getType(),
					mutation = mutation
				}
			)
		end

		table.insert(mutations, mutation)
	end

	for i, mutation in preserveMutations do
		mutations[i] = MItem.getBestMutation(mutation, mutations[i])
	end

	return mutations
end

-- returns an array of modifications in best-to-worst order, of size totalCount
function MergeMixin.calculateNewItemModifications(self: MergeMixin, player: Player, count: number, mergingItems: { any }): { { number } }
	if count < 1 then
		warn("cannot calculate new item modifications for no items", count)
		return {}
	end

	local existingModificationsCountMap: { [number]: number } = {}
	for _, item in mergingItems do
		for i = 1, item:getCount() do
			local modifications = item:getModifications()
			for j = 1, #modifications do
				if not existingModificationsCountMap[modifications[j]] then
					existingModificationsCountMap[modifications[j]] = 0
				end

				existingModificationsCountMap[modifications[j]] += 1
			end
		end
	end

	local modifications: { { number } } = {}
	for i = 1, count do
		table.insert(modifications, {} :: { number })
	end

	-- now go through existing modifications and distribute them
	for modification, count in existingModificationsCountMap do
		for j = 1, math.min(count, #modifications) do
			table.insert(modifications[j], modification)
		end
	end

	return modifications
end

-- this is to support a dev tool
function MergeMixin.createItemsToMergeWithItem(self: MergeMixin, player: Player, triggerItem: any, isEnhanced: boolean?)
	local count = isEnhanced and 4 or 2

	for i = 1, count do
		local item = itemManager:createItem(triggerItem:getItemName(), triggerItem:getUserId())
		if not item then
			continue
		end

		local direction = triggerItem:getPart().CFrame.LookVector
		local rotation = CFrame.fromEulerAnglesXYZ(0, math.rad(-45 + (i - 1) * (90 / (count - 1))), 0)
		local positionDiff = (rotation * direction) * (gameController:getPlayerData(player):getPlayerVariable(Attributes.MERGE_CIRCLE_RADIUS) / 2)
		local cframe = CFrame.lookAt(triggerItem:getPart().Position + positionDiff, triggerItem:getPart().Position)

		item:getObj():PivotTo(cframe)
		item:getObj().Parent = workspace
	end
end

-- place it properly equipped or in the workspace depending on the item's capabilities
function MergeMixin.placePrimaryMergedItem(self: MergeMixin, item: Types.Item, cframe: CFrame)
	local itemData = item:getItemData()
	item:getObj():PivotTo(cframe)
	if itemData.mixins.pickup and itemData.mixins.pickup.equip ~= false then
		item:equip()
	else
		item:getObj().Parent = workspace

		if itemData.type == "shadowDragon" then
			local dragon = item :: Types.ShadowDragon
			dragon:notifyShouldMoveToIdleAtCurrentLocation()
		end
	end
end

function MergeMixin.getRandomUpgradeNameFromMergingItems(self: MergeMixin, items: { Types.NumberItem }): string
	local index = self.random:NextInteger(1, #items)
	return items[index]:getItemData().mixins.merge.upgradeItemName
end

function MergeMixin.getRandomLevel0ItemNameFromMergingItems(self: MergeMixin, items: { Types.NumberItem }): string?
	local index = self.random:NextInteger(1, #items)
	return gameController:getLevel0ItemNameForItem(items[index])
end

function MergeMixin.getMergeItemCountForItemIds(self: MergeMixin, itemIds: { number }): number
	local mergingItemTotalCount = 0
	for _, itemId in itemIds do
		local item = itemManager:getItemById(itemId) :: Types.NumberItem
		mergingItemTotalCount += item:getCount()
	end

	return mergingItemTotalCount
end

function MergeMixin.performMerge(self: MergeMixin, player: Player, triggerItemId: number, itemIds: { number }, destCFrame: CFrame, isMergeAll: boolean?)

	-- the documented prerequisite: canMergeItems returned true, so all ids resolve to stackable items
	local triggerItem = itemManager:getItemById(triggerItemId) :: Types.NumberItem
	local isMItem = itemManager:isMutationCapableType(triggerItem:getType())
	local itemData = triggerItem:getItemData()
	local mergeData = itemData.mixins.merge

	local allMergingItems = {triggerItem}
	for _, itemId in itemIds do
		local item = itemManager:getItemById(itemId) :: Types.NumberItem
		table.insert(allMergingItems, item)
	end

	-- find best mutation among items being merged for calculating xp/gems
	local bestInputMutation = enums.Mutations.NORMAL

	for _, itemId in itemIds do
		local item = itemManager:getItemById(itemId) :: Types.NumberItem

		item:notifyMergingWithTriggerItem(triggerItem)

		if isMItem then
			local mitem = item :: Types.MItem
			bestInputMutation = MItem.getBestMutation(bestInputMutation, mitem:getMutation())
		end
	end

	local mergingItemTotalCount = 0
	if isMergeAll then
		for _, item in allMergingItems do
			mergingItemTotalCount += item:getCount()
		end
		mergingItemTotalCount = math.min(Constants.MERGE_ALL_MAX_COUNT, mergingItemTotalCount)
	else
		mergingItemTotalCount = #allMergingItems
	end

	--print("merging item total count", mergingItemTotalCount, "in the past would have", #allMergingItems)

	local totalUpgradeCount = (mergingItemTotalCount // 5) * 2
	local remainingInputCount = mergingItemTotalCount % 5
	local recreateCount
	if remainingInputCount >= 3 then
		totalUpgradeCount += 1
		recreateCount = remainingInputCount - 3
	else
		recreateCount = remainingInputCount
	end
	local extraUpgradeCount = totalUpgradeCount - 1
	local totalNewCount = 1 + extraUpgradeCount + recreateCount

	--print("merge", mergingItemTotalCount, "creating one upgrade standard. Also", extraUpgradeCount, "extras, and recreating", recreateCount)

	-- figure out consecutive merge count to use as a gem multiplier and also tell the client
	local playerData = gameController:getPlayerData(player)
	local prevMergeData = playerData:getMergeData()
	local consecutiveMergeCount = 1
	local mergeTime = workspace:GetServerTimeNow()
	if prevMergeData and itemData.primaryElement then
		if mergeTime - prevMergeData.latestMergeTime < Constants.MERGE_COMBO_GAP_SEC then
			consecutiveMergeCount = prevMergeData.consecutiveMergeCount + 1
		end
	end
	playerData:setMergeData(
		{
			latestMergeTime = mergeTime,
			consecutiveMergeCount = consecutiveMergeCount,
		}
	)

	-- figure out mutations of new items
	local mutations: { number }
	local modifications: { { number } }
	if isMItem then
		mutations = self:calculateNewItemMutations(player, totalNewCount, allMergingItems)
		modifications = self:calculateNewItemModifications(player, totalNewCount, allMergingItems)
	else
		mutations = {}
		for i = 1, totalNewCount do
			table.insert(mutations, enums.Mutations.NORMAL)
		end
		modifications = {}
		for i = 1, totalNewCount do
			table.insert(modifications, {} :: { number })
		end
	end

	local haveAnyMutations = false
	for i = 1, #mutations do
		if mutations[i] == enums.Mutations.NORMAL then
			continue
		end

		haveAnyMutations = true
		break
	end

	-- in most things, GameController event handler sends status messages, but for merging we needed to calculate some extra
	-- data to send to the client so we send it here
	local bestMutation: number
	if haveAnyMutations then
		bestMutation = mutations[1]
	else
		bestMutation = enums.Mutations.NORMAL
	end
	RemoteEvents.NotifyMergeBeginStatus:FireClient(player, true, consecutiveMergeCount, bestMutation)

	local mergeAudioParent: any = MergeAudioParent:Clone()
	mergeAudioParent.Position = destCFrame.Position
	mergeAudioParent.Parent = workspace
	game:GetService("Debris"):AddItem(mergeAudioParent, 5) -- destroy after 5s

	if haveAnyMutations then
		local mutationCreatedParent: any = MutationCreatedParent:Clone()
		mutationCreatedParent.CFrame = destCFrame
		mutationCreatedParent.Anchored = true
		mutationCreatedParent.Parent = workspace
		utils.safelyDisposeOfParticleParent(mutationCreatedParent, MUTATION_CLOUD_DURATION_SEC)

		local audioMergeMutation = mergeAudioParent:FindFirstChild("AudioMergeMutation")
		audioMergeMutation:Play();

		-- a missing character crashed here before typing too
		(player.Character :: any).HumanoidRootPart.Anchored = true
		task.wait(MUTATION_CLOUD_DURATION_SEC);
		(player.Character :: any).HumanoidRootPart.Anchored = false

		playerData:notifyReceivedMutation()
	end

	-- create/play some animations, audio
	local mergePost: any = MergePost:Clone()
	mergePost:PivotTo(destCFrame)
	mergePost.Parent = workspace
	-- emit won't actually show anything unless we put this delay in here... ugh what a hack
	-- see https://devforum.roblox.com/t/particleemitteremit-doesnt-work/758953/12
	task.delay(0.05,
		function()
			mergePost:FindFirstChild("Burst"):Emit(totalNewCount)
			utils.safelyDisposeOfParticleParent(mergePost, 0.05)
		end
	)

	local audioMergeEvent = mergeAudioParent:FindFirstChild("AudioMergeEvent")
	audioMergeEvent:Play()

	local audioMergeEnd = mergeAudioParent:FindFirstChild("AudioMergeEnd")
	audioMergeEnd:Play()

	for _, item in allMergingItems do
		analyticsManager:logEvent(player, analyticsManager.Events.LoseItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				lossSource = "merge",
			}
		)
	end

	-- keep this around for the end in case the player has an ability that grants one of these
	local level0ItemName = self:getRandomLevel0ItemNameFromMergingItems(allMergingItems)

	-- destroy all the merged items
	local remainingRemoveCount = mergingItemTotalCount
	for _, item in allMergingItems do
		local removingCount = math.min(remainingRemoveCount, item:getCount())
		--print("item", item, "count", item:getCount(), "remaining to remove", remainingRemoveCount, "actually removing", removingCount)
		item:reduceCount(removingCount)
		remainingRemoveCount -= removingCount
		if remainingRemoveCount == 0 then
			break
		end
	end

	-- create primary/first item
	--print("primary merged item is", upgradeName)
	local upgradeItem = itemManager:createItem(self:getRandomUpgradeNameFromMergingItems(allMergingItems), player.UserId)
	if not upgradeItem then
		warn("merge failed to create its upgrade item")
		return
	end

	-- contextual FTUE: explain flying the first time the player receives a level 4+ dragon
	local upgradeItemData = upgradeItem:getItemData()
	if upgradeItem:getType() == "shadowDragon" and upgradeItemData.level and upgradeItemData.level >= 4 then
		contextualFtueManager:tryTrigger(player, "flyingUnlocked")
	end

	if isMItem then
		local upgradeMItem = upgradeItem :: Types.MItem
		upgradeMItem:setMutation(mutations[1])
		table.remove(mutations, 1)
		upgradeMItem:setModifications(modifications[1])
		table.remove(modifications, 1)

		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = upgradeItem:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, upgradeItem:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, upgradeItem:getItemData().rarity),
				itemType = upgradeItem:getType(),
				acquisitionSource = "mergeUpgrade",
			}
		)
	end

	local newItems = {}
	-- create extra upgraded items
	for i = 1, extraUpgradeCount do
		local newItem = itemManager:createItem(self:getRandomUpgradeNameFromMergingItems(allMergingItems), player.UserId)
		if not newItem then
			continue
		end
		if isMItem then
			local newMItem = newItem :: Types.MItem
			newMItem:setMutation(mutations[1])
			table.remove(mutations, 1)
			newMItem:setModifications(modifications[1])
			table.remove(modifications, 1)

			analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
				{
					objectName = newItem:getItemName(),
					primaryElement = enums.getPublicName(enums.PrimaryElements, newItem:getItemData().primaryElement),
					rarity = enums.getPublicName(enums.Rarity, newItem:getItemData().rarity),
					itemType = newItem:getType(),
					acquisitionSource = "mergeExtra",
				}
			)
		end

		table.insert(newItems, newItem)
	end

	-- if you have a spare, just create what item the player already had
	for i = 1, recreateCount do
		local newItem = itemManager:createItem(triggerItem:getItemName(), player.UserId)
		if not newItem then
			continue
		end
		if isMItem then
			local newMItem = newItem :: Types.MItem
			newMItem:setMutation(mutations[1])
			table.remove(mutations, 1)
			newMItem:setModifications(modifications[1])
			table.remove(modifications, 1)
		end
		table.insert(newItems, newItem)

		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = newItem:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, newItem:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, newItem:getItemData().rarity),
				itemType = newItem:getType(),
				acquisitionSource = "mergeSpare",
			}
		)
	end

	-- put primary item in the player's hand (or in world if not pick-up-able)
	self:placePrimaryMergedItem(upgradeItem, destCFrame)

	-- could have been merged into an item we already had in inventory, so figure out what we're holding now and highlight it (upgradeItem could be completely gone)
	local nowUpgradeItem: Types.Item = upgradeItem
	local tool = utils.getHoldingToolWithHandle(player)
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle then
			local heldItem = itemManager:getItemById(handle:GetAttribute(Attributes.ITEM_ID) :: number?)
			if heldItem then
				nowUpgradeItem = heldItem
			end
		end
	end
	nowUpgradeItem:createAndDecayHighlight()

	-- place new items in the world
	if isMergeAll then
		gameController:spawnItemsInBackpack(newItems)
	else
		gameController:spawnItemsAtPosition(newItems, destCFrame.Position)
	end

	local amountMultiplier = 1 + extraUpgradeCount
	local mutationMultiplier = 1 + MItem.getMutationBonus(bestInputMutation)
	local comboMultiplier = math.min(10, consecutiveMergeCount)

	local xp = 0
	if mergeData.xp then
		local baseXp = mergeData.xp
		xp = math.ceil(baseXp * amountMultiplier * mutationMultiplier * comboMultiplier)
		--print("merge xp calculation: base", baseXp, "amount multiplier", amountMultiplier, "mutation multiplier", mutationMultiplier, "combo multiplier", comboMultiplier, "=", xp)

		gameController:addPrimaryElementXpToPlayer(player, itemData.primaryElement, xp, upgradeItem:getPart())
	end

	local comboGemCount = 0
	if consecutiveMergeCount > 1 then
		comboGemCount = math.ceil(1 * mutationMultiplier * comboMultiplier)
		--print("merge gem calculation: base", 1, "mutation multiplier", mutationMultiplier, "combo multiplier", comboMultiplier, "=", comboGemCount)

		--print("spawning combo gems", comboGems)
		-- legacy (2026-august-20): used to spawn physical gems; now grants coins directly
		-- gameController:spawnGemsForPlayerFromItem(player, itemData.primaryElement, comboGemCount, upgradeItem)
		gameController:grantCoinsForGemValue(player, itemData.primaryElement, comboGemCount)
	end

	analyticsManager:logEvent(player, analyticsManager.Events.Merge,
		{
			objectName = triggerItem:getItemName(),
			objectCount = mergingItemTotalCount,
			gemCount = comboGemCount,
			xp = xp,
			combo = consecutiveMergeCount,
			primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
			itemType = itemData.type,
			isMergeAll = isMergeAll,
		}
	)

	if triggerItem:getType() == "crop" then
		playerData:incrementStat("cropMerges")
	elseif triggerItem:getType() == "shadowDragon" or triggerItem:getType() == "dragonEgg" then
		playerData:incrementStat("dragonMerges")
	elseif triggerItem:getType() == "crystal" then
		playerData:incrementStat("crystalMerges")
	end

	RemoteEvents.NotifyMergeEnd:FireClient(player)

	-- here we support "merge crop get seed" ability

	if triggerItem:getType() == "crop" then
		local getSeedFrac = playerData:getPlayerVariable(Attributes.MERGE_CROP_GET_SEED_FRAC)
		--print("seed frac is", getSeedFrac)
		if self.random:NextNumber(0, 1) < getSeedFrac then
			--print("trying to give an ability-triggered seed here", level0ItemName)
			-- safety check; it should always succeed
			local seedItem = if level0ItemName then itemManager:createItem(level0ItemName, player.UserId) else nil
			if seedItem then
				gameController:spawnItemsAtPosition({seedItem}, destCFrame.Position)

				analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
					{
						objectName = seedItem:getItemName(),
						primaryElement = enums.getPublicName(enums.PrimaryElements, seedItem:getItemData().primaryElement),
						rarity = enums.getPublicName(enums.Rarity, seedItem:getItemData().rarity),
						itemType = seedItem:getType(),
						acquisitionSource = "abilityMergeCropGetSeed",
					}
				)
			end
		end
	end

	-- here we support "merge dragon get egg" ability

	if triggerItem:getType() == "shadowDragon" or triggerItem:getType() == "dragonEgg" then
		local getEggFrac = playerData:getPlayerVariable(Attributes.MERGE_DRAGON_GET_EGG_FRAC)
		--print("egg frac is", getEggFrac)
		if self.random:NextNumber(0, 1) < getEggFrac then
			--print("trying to give an ability-triggered egg here", level0ItemName)
			-- safety check; it should always succeed
			local eggItem = if level0ItemName then itemManager:createItem(level0ItemName, player.UserId) else nil
			if eggItem then
				gameController:spawnItemsAtPosition({eggItem}, destCFrame.Position)

				analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
					{
						objectName = eggItem:getItemName(),
						primaryElement = enums.getPublicName(enums.PrimaryElements, eggItem:getItemData().primaryElement),
						rarity = enums.getPublicName(enums.Rarity, eggItem:getItemData().rarity),
						itemType = eggItem:getType(),
						acquisitionSource = "abilityMergeDragonGetEgg",
					}
				)
			end
		end
	end

end

--[[
	Only call this if canMergeItems returns true
]]
function MergeMixin.notifyMergeItemsWithHeldItem(self: MergeMixin, player: Player, triggerItemId: number, itemIds: { number }, isMergeAll: boolean?)
	--print("merging", triggerItemId, itemIds)

	-- these are guaranteed to succeed due to earlier checks
	local tool = utils.getHoldingToolWithHandle(player) :: Tool
	local handle = tool:FindFirstChild("Handle") :: BasePart

	-- take item out of player's hand
	local destCFrame = handle.CFrame

	-- the documented prerequisite: canMergeItems returned true, so the item exists and stacks
	local triggerItem = itemManager:getItemById(triggerItemId) :: Types.NumberItem
	local mergeItem: Types.NumberItem?
	if isMergeAll then
		local mergingItemCount = self:getMergeItemCountForItemIds(itemIds)
		--print("merging item count is", mergingItemCount, itemIds)
		local countRemaining = math.min(triggerItem:getCount(), Constants.MERGE_ALL_MAX_COUNT - mergingItemCount)
		--local countRemaining = math.min(triggerItem:getCount(), math.max(1, Constants.MERGE_ALL_MAX_COUNT - mergingItemCount))
		--print("count remaining is", countRemaining, "trigger item", triggerItem, triggerItem:getCount())
		if triggerItem:getCount() > countRemaining then
			--print("splitting")
			-- player is holding a stack, so we just take from the stack and merge it
			mergeItem = triggerItem:splitOffCount(countRemaining);
			-- and unequip remainder so that the newly merged item may go into the hand (if the upgrade item is a pickup-able item)
			(player.Character :: any).Humanoid:UnequipTools()
		else
			--print("using full trigger")
			mergeItem = triggerItem
		end
	else
		if triggerItem:getCount() > 1 then
			-- player is holding a stack, so we just take 1 from the stack and merge it
			mergeItem = triggerItem:splitOffOne();
			-- and unequip remainder so that the newly merged item may go into the hand (if the upgrade item is a pickup-able item)
			(player.Character :: any).Humanoid:UnequipTools()
		else
			mergeItem = triggerItem
		end
	end

	if not mergeItem then
		warn("merge could not split off a merge item from the held stack")
		return
	end

	mergeItem:notifyMergingWithTriggerItem(mergeItem)

	if mergeItem:getPart() == mergeItem:getObj() then
		mergeItem:getPart().Name = mergeItem:getItemDataType():getTemplate().Name
		--print("trigger item is just a part", mergeItem:getPart())
	else
		-- this means the obj is a model and the part is the primary part, which was temporarily parented to the tool
		mergeItem:setupChildPartsToObj()
	end

	ftueManager:notifyMergeForPlayer(player, mergeItem)

	mergeItem:getPart().Anchored = true
	mergeItem:getPart().CanCollide = false

	mergeItem:getObj().Parent = workspace

	mergeItem:getObj():PivotTo(destCFrame)

	-- yield to next step, to ensure callbacks for parent changing get called (as of 2026-february-27 that's important for plot capacity to stay correct)
	task.wait()

	if triggerItem == mergeItem then
		tool:Destroy()
	end

	self:performMerge(player, mergeItem:getItemId(), itemIds, destCFrame, isMergeAll)
end

function MergeMixin.notifyMergeItemsWithRidingItem(self: MergeMixin, player: Player, triggerItemId: number, itemIds: { number }, isMergeAll: boolean?)
	--print("merging", triggerItemId, itemIds)

	-- maybe should specifically detach player from the seat and give some impulse or something

	-- the documented prerequisite: canMergeItems returned true, so the item exists
	local triggerItem = itemManager:getItemById(triggerItemId) :: Types.Item

	local destCFrame = triggerItem:getPart().CFrame

	self:performMerge(player, triggerItemId, itemIds, destCFrame, isMergeAll)
end

function MergeMixin.new(): MergeMixin
	local self: MergeMixin = setmetatable({
		random = Random.new(),
	} :: MergeMixinFields, MergeMixin)

	return self
end

function MergeMixin.initClass(deps: any)
	gameController = deps.gameController

end

local singleton = MergeMixin.new()

return singleton
