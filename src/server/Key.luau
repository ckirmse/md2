--!strict


local NumberItem = require("./NumberItem")
local super = NumberItem

local Key = {}
Key.__index = setmetatable(Key, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local pickupMixin = require("./PickupMixin")


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")


export type KeyFields = Types.KeyFields
export type Key = Types.Key

function Key.getDataDumpString(self: Key): string
	local text = super.getDataDumpString(self)

	return text
end

-- doing this automatically (based on parent change) is not great, because there are different situations--
-- initial spawn, player placing later, etc., and they have different properties.
-- there are times we want to spawn a key and have it NOT settle, because the spawning code has specific
-- other ways it wants the egg to move (this applies to other item types too)
function Key.notifyParentWorkspace(self: Key)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	-- parts have been made children of the model again before it gets here, so we do the normal thing (looking for descendants of obj)

	--print("key put in workspace")

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		--print("letting egg get placed directly on ground, skipping settle")
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			--print("key settled")
		end
	)
end

function Key.notifyParentPlayer(self: Key)
	super.notifyParentPlayer(self)
end

function Key.notifyMergingWithTriggerItem(self: Key, triggerItem: any)
	if self:getItemData().mixins.pickup then
		pickupMixin:notifyItemCannotBePickedUp(self)
	end
end

function Key.canBePickedUp(self: Key): boolean
	-- other cases handled by mixin
	return true
end

function Key.setPreventSettling(self: Key)
	self.doPreventSettling = true
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Key.getSaveData(self: Key, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	return retval
end

function Key.loadSaveData(self: Key, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Key.init(self: Key)
	self:getObj():SetAttribute(Attributes.LEVEL, self:getItemData().level)
	collectionService:AddTag(self:getObj(), Tags.KEY)
end

function Key.notifyNewClone(self: Key)
	super.notifyNewClone(self)

	self:init()
end

function Key.new(itemId: number, itemName: string, userId: number): Key
	local self = (setmetatable(super.new(itemId, itemName, userId), Key) :: any) :: Key

	self:init()

	return self
end

return Key
