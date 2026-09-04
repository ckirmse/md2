--!strict


local MItem = require("./MItem")
local super = MItem

local DragonEgg = {}
DragonEgg.__index = setmetatable(DragonEgg, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local pickupMixin = require("./PickupMixin")


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")


export type DragonEggFields = Types.DragonEggFields
export type DragonEgg = Types.DragonEgg

function DragonEgg.getDataDumpString(self: DragonEgg): string
	local text = super.getDataDumpString(self)

	return text
end

-- doing this automatically (based on parent change) is not great, because there are different situations--
-- initial spawn, player placing later, etc., and they have different properties.
-- there are times we want to spawn an egg and have it NOT settle, because the spawning code has specific
-- other ways it wants the egg to move (this applies to other item types too)
function DragonEgg.notifyParentWorkspace(self: DragonEgg)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	-- parts have been made children of the model again before it gets here, so we do the normal thing (looking for descendants of obj)

	--print("egg put in workspace")

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		--print("letting egg get placed directly on ground, skipping settle")
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			--print("egg settled")
		end
	)
end

function DragonEgg.notifyParentPlayer(self: DragonEgg)
	super.notifyParentPlayer(self)
end

function DragonEgg.notifyMergingWithTriggerItem(self: DragonEgg, triggerItem: any)
	if self:getItemData().mixins.pickup then
		pickupMixin:notifyItemCannotBePickedUp(self)
	end

end

function DragonEgg.canBePickedUp(self: DragonEgg): boolean
	-- other cases handled by mixin
	return true
end

function DragonEgg.setPreventSettling(self: DragonEgg)
	self.doPreventSettling = true
end

function DragonEgg.getToolName(self: DragonEgg): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function DragonEgg.getSaveData(self: DragonEgg, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.type = "dragonEgg"

	return retval
end

function DragonEgg.loadSaveData(self: DragonEgg, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function DragonEgg.notifyNewClone(self: DragonEgg)
	--print("dragon egg notify new clone")

	super.notifyNewClone(self)

	local itemData = self:getItemData()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)
end

function DragonEgg.new(itemId: number, itemName: string, userId: number): DragonEgg
	local self = (setmetatable(super.new(itemId, itemName, userId), DragonEgg) :: any) :: DragonEgg

	local itemData = self:getItemData()

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	collectionService:AddTag(self:getObj(), Tags.DRAGON_EGG)

	return self
end

return DragonEgg
