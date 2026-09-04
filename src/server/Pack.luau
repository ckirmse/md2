--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local Pack = {}
Pack.__index = setmetatable(Pack, super)

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

export type PackFields = Types.PackFields
export type Pack = Types.Pack

function Pack.getDataDumpString(self: Pack): string
	local text = super.getDataDumpString(self)
	text = text .. "\nState: " .. tostring(enums.getName(enums.PackState, self.state))

	return text
end

function Pack.finishPlaceInWorkspace(self: Pack)
	self:getPart().Anchored = true

	collectionService:AddTag(self:getObj(), Tags.OPENABLE_PACK)
end

function Pack.notifyParentWorkspace(self: Pack)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		self.doPreventSettling = false
		--print("letting pack get placed directly on ground because it's loading, skipping settle")
		self:setVenueWorkspaceAvailable()
		self:finishPlaceInWorkspace()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			self:finishPlaceInWorkspace()
		end
	)
end

function Pack.notifyParentPlayer(self: Pack)
	super.notifyParentPlayer(self)

	collectionService:RemoveTag(self:getObj(), Tags.OPENABLE_PACK)
end

function Pack.beginIdle(self: Pack)
	if self:getObj().Parent == workspace then
		self:setVenueWorkspaceAvailable()
	end
end

function Pack.cleanupIdle(self: Pack)
end

function Pack.canBePickedUp(self: Pack): boolean
	return true
end

function Pack.notifyShouldOpen(self: Pack)
	--print("pack opening now", self)

	self:getObj():SetAttribute(Attributes.ANIMATION_OPENING, "")

	task.wait(0.15)

	if not self:getObj() then
		-- we have been destroyed (player probably logged off)
		return
	end

	local itemData = self:getItemData()
	local lootTableName = itemData.lootName
	local lootEntries = lootTableManager:calculateLootResults(lootTableName)
	local itemCreationData = lootTableManager:getItemCreationDataFromItemLootResults(lootEntries)
	local items = gameController:createItemsFromItemCreationDataForPlayer(itemCreationData, self:getPlayer())
	gameController:spawnItemsAtPosition(items, self:getPart().Position + Vector3.new(0, 3, 0))

	analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.LoseItem,
		{
			objectName = self:getItemName(),
			itemType = self:getType(),
			lossSource = "openPack",
		}
	)

	itemManager:destroyItem(self)

	local playerData = gameController:getPlayerData(self:getPlayer())
	for _, item in items do
		playerData:notifyItemReceived(item)
	end

	for _, item in items do
		analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "pack",
			}
		)
	end

end

function Pack.setPreventSettling(self: Pack)
	self.doPreventSettling = true
end

function Pack.getToolName(self: Pack): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

function Pack.endState(self: Pack)
	if self.state == enums.PackState.IDLE then
		self:cleanupIdle()
	else
		warn("end unknown pack state", self, self.state)
	end

	self.state = nil
end

function Pack.beginState(self: Pack, state: number?, ...: any)
	self.state = state
	--print("dragon beginning state", self:getItemName(), state)

	if self.state == enums.PackState.IDLE then
		self:beginIdle(...)
	else
		warn("begin unknown pack state", self, state)
	end

	self:updateDataDump()
end

function Pack.setState(self: Pack, state: number?, ...: any)
	self:endState()

	self:beginState(state, ...)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Pack.getSaveData(self: Pack, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.state = self.state

	return retval
end

function Pack.loadSaveData(self: Pack, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Pack.destroy(self: Pack)
	self:endState()

	super.destroy(self)
end

function Pack.notifyNewClone(self: Pack)
	self.state = enums.PackState.IDLE

	collectionService:AddTag(self:getObj(), Tags.PACK)
end

function Pack.new(itemId: number, itemName: string, userId: number): Pack
	local self = (setmetatable(super.new(itemId, itemName, userId), Pack) :: any) :: Pack

	self.state = enums.PackState.IDLE

	collectionService:AddTag(self:getObj(), Tags.PACK)

	return self
end

function Pack.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Pack
