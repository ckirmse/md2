--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local Crate = {}
Crate.__index = setmetatable(Crate, super)

local collectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local mutationStoreManager: Types.MutationStoreManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local vanityStoreManager: Types.VanityStoreManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local analyticsManager = require("./AnalyticsManager")


export type CrateFields = Types.CrateFields
export type Crate = Types.Crate

function Crate.getDataDumpString(self: Crate): string
	local text = super.getDataDumpString(self)
	text = text .. "\nState: " .. tostring(enums.getName(enums.CrateState, self.state))

	return text
end

function Crate.finishPlaceInWorkspace(self: Crate)
	self:getPart().Anchored = true

	collectionService:AddTag(self:getObj(), Tags.OPENABLE_CRATE)
end

function Crate.notifyParentWorkspace(self: Crate)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		self.doPreventSettling = false
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

function Crate.notifyParentPlayer(self: Crate)
	super.notifyParentPlayer(self)

	collectionService:RemoveTag(self:getObj(), Tags.OPENABLE_CRATE)
end

function Crate.beginIdle(self: Crate)
	if self:getObj().Parent == workspace then
		self:setVenueWorkspaceAvailable()
	end
end

function Crate.cleanupIdle(self: Crate)
end

function Crate.canBePickedUp(self: Crate): boolean
	return true
end

function Crate.setRewardSource(self: Crate, rewardType: string?, lootTableName: string?, displayText: string?)
	self.rewardType = rewardType
	self.lootTableName = lootTableName
	self.displayText = displayText
end

function Crate.canStackWith(self: Crate, item: any): boolean
	return item.rewardType == self.rewardType and item.lootTableName == self.lootTableName
end

function Crate.notifyShouldOpen(self: Crate)
	self:getObj():SetAttribute(Attributes.ANIMATION_OPENING, "")

	task.wait(0.15)

	if not self:getObj() then
		-- we have been destroyed (player probably logged off)
		return
	end

	local lootTableName = self.lootTableName
	if not lootTableName then
		warn("crate has no loot table name, cannot open", self)
		return
	end

	local items = {}
	if self.rewardType == indexHelpers.RewardType.MUTATION_PULL then
		local item, mutation = mutationStoreManager:rollAndCreateItem(self:getPlayer(), lootTableName)
		if item then
			table.insert(items, item)

			local itemData = item:getItemData()
			local templatePath = itemData.casterPath or itemData.templatePath
			local mutationSurfaceAppearanceName = itemData.mutationSurfaceAppearanceName
			local cameraPosition = itemData.buy and itemData.buy.cameraPosition or nil
			local text = string.format("You received a %s!", item:getVisibleName())

			RemoteEvents.NotifyItemRevealFanfare:FireClient(
				self:getPlayer(), text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition
			)
		end
	elseif self.rewardType == indexHelpers.RewardType.VANITY_PULL then
		local item = vanityStoreManager:rollAndCreateItem(self:getPlayer(), lootTableName)
		if item then
			table.insert(items, item)
		end
	else
		warn("crate has unknown reward type, cannot open", self, self.rewardType)
	end

	gameController:spawnItemsAtPosition(items, self:getPart().Position + Vector3.new(0, 3, 0))

	analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.LoseItem,
		{
			objectName = self:getItemName(),
			itemType = self:getType(),
			lossSource = "openCrate",
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
				acquisitionSource = "crate",
			}
		)
	end

end

function Crate.setPreventSettling(self: Crate)
	self.doPreventSettling = true
end

function Crate.getToolName(self: Crate): string
	local label = self.displayText or self.lootTableName
	if label then
		return self:getVisibleName() .. " (" .. label .. ")"
	end

	return self:getVisibleName()
end

function Crate.endState(self: Crate)
	if self.state == enums.CrateState.IDLE then
		self:cleanupIdle()
	else
		warn("end unknown crate state", self, self.state)
	end

	self.state = nil
end

function Crate.beginState(self: Crate, state: number?, ...)
	self.state = state

	if self.state == enums.CrateState.IDLE then
		self:beginIdle(...)
	else
		warn("begin unknown crate state", self, state)
	end

	self:updateDataDump()
end

function Crate.setState(self: Crate, state: number?, ...)
	self:endState()

	self:beginState(state, ...)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Crate.getSaveData(self: Crate, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.state = self.state
	retval.rewardType = self.rewardType
	retval.lootTableName = self.lootTableName
	retval.displayText = self.displayText

	return retval
end

function Crate.loadSaveData(self: Crate, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	self.rewardType = itemSaveData.rewardType
	self.lootTableName = itemSaveData.lootTableName
	self.displayText = itemSaveData.displayText
end

function Crate.destroy(self: Crate)
	self:endState()

	super.destroy(self)
end

function Crate.notifyNewClone(self: Crate)
	self.state = enums.CrateState.IDLE

	collectionService:AddTag(self:getObj(), Tags.CRATE)
end

function Crate.new(itemId: number, itemName: string, userId: number): Crate
	local self = (setmetatable(super.new(itemId, itemName, userId), Crate) :: any) :: Crate

	self.state = enums.CrateState.IDLE

	collectionService:AddTag(self:getObj(), Tags.CRATE)

	return self
end

function Crate.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
	mutationStoreManager = deps.mutationStoreManager
	vanityStoreManager = deps.vanityStoreManager
end

return Crate
