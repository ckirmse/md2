--!strict


local NumberItem = require("./NumberItem")
local super = NumberItem

local Crystal = {}
Crystal.__index = setmetatable(Crystal, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local lootTableManager = require("./LootTableManager")
local Timer = require("./Timer")

local crystalTimeData = require("@game/ServerScriptService/GameData/Control/CrystalTime")

type OpeningState = Types.OpeningState


export type CrystalFields = Types.CrystalFields
export type Crystal = Types.Crystal

function Crystal.getDataDumpString(self: Crystal): string
	local text = super.getDataDumpString(self)
	text = text .. "\nState: " .. tostring(enums.getName(enums.CrystalState, self.state))
	if self.state == enums.CrystalState.OPENING then
		text = text .. "\nComplete Time: " .. tostring(self.opening.completeTime)
	end

	return text
end

function Crystal.finishPlaceInWorkspace(self: Crystal)
	self:getPart().Anchored = true

	if self.state == enums.CrystalState.OPENING or self.state == enums.CrystalState.OPENED then
		-- we don't allow them to be merged by having them be marked busy
		self:setVenueWorkspaceBusy()
	end

	--print("adding crystal to workspace with state", enums.getName(enums.CrystalState, self.state))

	if self.state == enums.CrystalState.IDLE then

		if not self.doPreventSettling then
			if self:getItemData().open then
				collectionService:AddTag(self:getObj(), Tags.OPENABLE_CRYSTAL)
			end
		end
	end

	if self.state == enums.CrystalState.MERGING then
		-- pass
	end

	if self.state == enums.CrystalState.OPENED then
		collectionService:AddTag(self:getObj(), Tags.CLAIMABLE_CRYSTAL)
	end

end

function Crystal.notifyParentWorkspace(self: Crystal)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	if self:getIsParentingOnLoad() then
		--print("letting crystal get placed directly on ground because it's loading, skipping settle")
		self:setVenueWorkspaceAvailable()
		self:finishPlaceInWorkspace()
		return
	end

	if self.state == enums.CrystalState.MERGING then
		return
	end

	if self.doPreventSettling then
		-- crystals get spawned from nodes and animate to player's backpack, so there's no settling desired (and in fact Anchoring at the end, too late, could happen)
		self:finishPlaceInWorkspace()
		self.doPreventSettling = false
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			self:finishPlaceInWorkspace()
		end
	)
end

function Crystal.notifyParentPlayer(self: Crystal)
	super.notifyParentPlayer(self)

	collectionService:RemoveTag(self:getObj(), Tags.OPENABLE_CRYSTAL)

	-- if something was happening, we gotta stop it

	if self.state == enums.CrystalState.OPENING then
		self:setState(enums.CrystalState.IDLE)
	else
		-- if any dragons were coming to open us, tell 'em we're gone
		gameController:notifyCrystalNoLongerAvailable(self)
	end

	if self.state == enums.CrystalState.OPENED then
		collectionService:RemoveTag(self:getObj(), Tags.CLAIMABLE_CRYSTAL)
	end
end

function Crystal.beginIdle(self: Crystal)
	if self:getObj().Parent == workspace then
		self:setVenueWorkspaceAvailable()
	end

	if self:getItemData().open and self:getObj().Parent == workspace then
		-- this combination happens when it was being opened but was aborted
		collectionService:AddTag(self:getObj(), Tags.OPENABLE_CRYSTAL)
	end

end

function Crystal.cleanupIdle(self: Crystal)
end

function Crystal.finishOpeningSuccessfully(self: Crystal)
	self.opening.isComplete = true

	if self.opening.endTimer then
		self.opening.endTimer:cancel()
		self.opening.endTimer = nil
	end

	local player = self:getPlayer()
	if player then
		gameController:sendSystemMessageToPlayer(player, "You can now break a crystal!")
	end

	--print("finshed opening successfully, have dragonId", self.opening.dragonItemId)
	utils.pulseAttribute(self:getObj(), Attributes.ANIMATION_CRYSTAL_OPENED, "")

	self:setState(enums.CrystalState.OPENED)
end

function Crystal.beginOpening(self: Crystal, dragon: any, remainingSec: number?)
	self:setVenueWorkspaceBusy()

	self.opening.dragonItemId = dragon:getItemId()

	local now = workspace:GetServerTimeNow()

	local duration
	if remainingSec then
		duration = remainingSec
	else
		local player = self:getPlayer()
		local playerData = gameController:getPlayerData(player)
		local speedupFrac = playerData:getPlayerVariable(Attributes.CRYSTALS_OPEN_FASTER_FRAC)

		-- dragons higher than minimum level open it faster
		local baseDuration = self:getItemData().open.durationSec

		local levelDiff = self:getItemData().level - dragon:getItemData().level
		local levelDiffMultiplier = 1
		for _, openCrystalTimeEntry in crystalTimeData.openCrystalTime do
			if openCrystalTimeEntry.levelDiff ~= levelDiff then
				continue
			end

			levelDiffMultiplier = openCrystalTimeEntry.multiplier
			break
		end

		local primaryElementMultiplier
		if self:getItemData().primaryElement == dragon:getItemData().primaryElement then
			primaryElementMultiplier = 1
		else
			primaryElementMultiplier = 2
		end
		--print("opening parameters: base", baseDuration, "level diff multiplier", levelDiffMultiplier, "primary element", primaryElementMultiplier)
		duration = math.max(crystalTimeData.minOpenCrystalTime, baseDuration * levelDiffMultiplier * primaryElementMultiplier) * (1 - speedupFrac)
	end

	self.opening.completeTime = now + duration

	--print("will be done opening at", self.opening.completeTime)
	self:getObj():SetAttribute(Attributes.OPEN_COMPLETE_TIME, self.opening.completeTime)

	self.opening.endTimer = Timer.new(duration,
		function()
			self:finishOpeningSuccessfully()
		end
	)

end

function Crystal.cleanupOpening(self: Crystal)
	if self.opening.endTimer then
		self.opening.endTimer:cancel()
		self.opening.endTimer = nil
	end

	self:getObj():SetAttribute(Attributes.OPEN_COMPLETE_TIME, nil)

	local dragon = itemManager:getItemById(self.opening.dragonItemId) :: Types.ShadowDragon?
	if dragon then
		dragon:notifyEndOpening()
	end

	self.opening = {}
end

function Crystal.beginOpened(self: Crystal)
	if self:getObj().Parent == workspace then
		collectionService:AddTag(self:getObj(), Tags.CLAIMABLE_CRYSTAL)
	end

	self:getObj():SetAttribute(Attributes.ANIMATION_CRYSTAL_CLAIMABLE, "")
end

function Crystal.cleanupOpened(self: Crystal)
	self:getObj():SetAttribute(Attributes.ANIMATION_CRYSTAL_CLAIMABLE, nil)
end

function Crystal.notifyDragonComingToOpen(self: Crystal, dragon: any)
	self:setVenueWorkspaceBusy()

	collectionService:RemoveTag(self:getObj(), Tags.OPENABLE_CRYSTAL)

	local player = dragon:getPlayer()
	if not player then
		return
	end

	local position = (player.Character :: any).HumanoidRootPart.Position
	local animationDragonComingToOpenStr = string.format("%.1f %.1f %.1f", position.X, position.Y, position.Z)

	utils.pulseAttribute(self:getObj(), Attributes.ANIMATION_DRAGON_COMING_TO_OPEN, animationDragonComingToOpenStr)
end

function Crystal.notifyDragonNoLongerComingToOpen(self: Crystal, dragon: any)
	self:setVenueWorkspaceAvailable()

	collectionService:AddTag(self:getObj(), Tags.OPENABLE_CRYSTAL)
end

function Crystal.notifyDragonStartOpening(self: Crystal, dragon: any)
	local itemData = self:getItemData()
	if not itemData.open then
		print("invalid attempt to open non-openable crystal", self:getItemName())
		return
	end

	analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.StartOpenCrystal,
		{
			objectName = self:getItemName(),
			dragonObjectName = dragon:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		}
	)

	self:setState(enums.CrystalState.OPENING, dragon)
end

function Crystal.notifyEndGettingOpened(self: Crystal)
	if self.state ~= enums.CrystalState.OPENING or self.opening.isComplete then
		-- if our state already changed, we handled it already (this happens on fully opening the crystal at least as of 2026-january-1)
		return
	end

	self:setState(enums.CrystalState.IDLE)
end

function Crystal.notifyClaim(self: Crystal)
	local itemData = self:getItemData()

	analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.ClaimCrystal,
		{
			objectName = self:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, itemData.primaryElement),
		}
	)

	self:setVenueWorkspaceBusy()

	self:getObj():SetAttribute(Attributes.ANIMATION_CLAIMING, "")

	task.wait(0.15)

	if not self:getObj() then
		-- we have been destroyed (player probably logged off)
		return
	end

	local lootTableName = itemData.open.lootName
	local lootEntries = lootTableManager:calculateLootResults(lootTableName)
	local itemCreationData = lootTableManager:getItemCreationDataFromItemLootResults(lootEntries)
	local items = gameController:createItemsFromItemCreationDataForPlayer(itemCreationData, self:getPlayer())
	gameController:spawnItemsAtPosition(items, self:getPart().Position)

	local player = self:getPlayer()
	local playerData = gameController:getPlayerData(player)
	local refundFrac = playerData:getPlayerVariable(Attributes.REFUND_CRYSTAL_FRAC)

	local random = Random.new()
	if random:NextNumber(0, 1) < refundFrac then
		local crystalItem = itemManager:createItem(self:getItemName(), self:getUserId())
		if crystalItem then
			gameController:spawnItemsAtPosition({crystalItem}, self:getObj():GetPivot().Position)

			analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
				{
					objectName = crystalItem:getItemName(),
					primaryElement = enums.getPublicName(enums.PrimaryElements, crystalItem:getItemData().primaryElement),
					rarity = enums.getPublicName(enums.Rarity, crystalItem:getItemData().rarity),
					itemType = crystalItem:getType(),
					acquisitionSource = "abilityRefundCrystal",
				}
			)
		end

	end

	itemManager:destroyItem(self)

	for _, item in items do
		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "crystalClaim" .. itemData.level,
			}
		)
	end
end

function Crystal.isOpening(self: Crystal)
	return self.state == enums.CrystalState.OPENING
end

function Crystal.getRemainingOpeningSec(self: Crystal): number?
	if not self:isOpening() then
		return nil
	end

	local now = workspace:GetServerTimeNow()
	-- completeTime is always set while opening
	local remainingOpeningSec = math.max(0, (self.opening.completeTime :: number) - now)

	return remainingOpeningSec
end


function Crystal.isOpened(self: Crystal)
	return self.state == enums.CrystalState.OPENED
end

function Crystal.setPreventSettling(self: Crystal)
	self.doPreventSettling = true
end

function Crystal.canBePickedUp(self: Crystal): boolean
	if self.state == enums.CrystalState.MERGING then
		return false
	end

	if self.state == enums.CrystalState.OPENED then
		return false
	end

	-- other cases handled by mixin
	return true
end

function Crystal.endState(self: Crystal)
	if self.state == enums.CrystalState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.CrystalState.MERGING then
		-- pass
	elseif self.state == enums.CrystalState.OPENING then
		self:cleanupOpening()
	elseif self.state == enums.CrystalState.OPENED then
		self:cleanupOpened()
	else
		warn("end unknown crystal state", self, self.state)
	end

	self.state = nil
end

function Crystal.beginState(self: Crystal, state: number?, ...)
	self.state = state
	--print("dragon beginning state", self:getItemName(), state)

	if self.state == enums.CrystalState.IDLE then
		self:beginIdle(...)
	elseif self.state == enums.CrystalState.MERGING then
		-- pass
	elseif self.state == enums.CrystalState.OPENING then
		self:beginOpening(...)
	elseif self.state == enums.CrystalState.OPENED then
		self:beginOpened(...)
	else
		warn("begin unknown crystal state", self, state)
	end

	self:updateDataDump()
end

function Crystal.setState(self: Crystal, state: number?, ...)
	self:endState()

	self:beginState(state, ...)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Crystal.getSaveData(self: Crystal, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.state = self.state
	if self.state == enums.CrystalState.OPENING then
		--print("saving data remapping an item id for crystal target", self.opening.dragonItemId, itemIdMap[self.opening.dragonItemId])
		retval.opening = {}
		retval.opening.dragonItemId = itemIdMap[self.opening.dragonItemId]
		retval.opening.remainingSec = math.max(0, (self.opening.endTimer :: Timer.Timer):getTimeLeft() or 0)
		--print("remaining sec", retval.opening.remainingSec)
	end

	return retval
end

function Crystal.loadSaveData(self: Crystal, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Crystal.notifyLoadComplete(self: Crystal, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	if itemSaveData.state == enums.CrystalState.OPENING then
		-- we do this here as we have a reference to another item that needs to exist and be in the workspace when we initialize OPENING state

		local dragonItemId = itemIdMap[itemSaveData.opening.dragonItemId]
		local dragon = itemManager:getItemById(dragonItemId)
		--print("crystal loading remaining sec", itemSaveData.opening.remainingSec)
		--print("but real time passed", offlineElapsedSec)
		-- simulate offline time passing
		local remainingSec = math.max(0, itemSaveData.opening.remainingSec - offlineElapsedSec)
		self:setState(enums.CrystalState.OPENING, dragon, remainingSec)
	elseif itemSaveData.state == enums.CrystalState.OPENED then
		self:setState(enums.CrystalState.OPENED)
	else
		self:setState(enums.CrystalState.IDLE)
	end
end

function Crystal.destroy(self: Crystal)
	self:endState()

	super.destroy(self)
end

function Crystal.init(self: Crystal)
	local itemData = self:getItemData()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)
	collectionService:AddTag(self:getObj(), Tags.CRYSTAL)
end

function Crystal.notifyNewClone(self: Crystal)
	super.notifyNewClone(self)

	self.state = enums.CrystalState.IDLE

	self:init()
end

function Crystal.new(itemId: number, itemName: string, userId: number): Crystal
	local self = (setmetatable(super.new(itemId, itemName, userId), Crystal) :: any) :: Crystal

	self.state = enums.CrystalState.IDLE

	self.opening = {}

	self:init()

	return self
end

function Crystal.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Crystal
