--!strict


local NumberItem = require("./NumberItem")
local super = NumberItem

local Blueprint = {}
Blueprint.__index = setmetatable(Blueprint, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local pickupMixin = require("./PickupMixin")
local plotsManager = require("./PlotsManager")


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")


export type BlueprintFields = Types.BlueprintFields
export type Blueprint = Types.Blueprint

function Blueprint.getDataDumpString(self: Blueprint): string
	local text = super.getDataDumpString(self)

	return text
end

-- doing this automatically (based on parent change) is not great, because there are different situations--
-- initial spawn, player placing later, etc., and they have different properties.
-- there are times we want to spawn a blueprint and have it NOT settle, because the spawning code has specific
-- other ways it wants the egg to move (this applies to other item types too)
function Blueprint.notifyParentWorkspace(self: Blueprint)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	-- parts have been made children of the model again before it gets here, so we do the normal thing (looking for descendants of obj)

	--print("blueprint put in workspace")

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		--print("letting egg get placed directly on ground, skipping settle")
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			--print("blueprint settled")
		end
	)

	local playerData = self:getPlayerData()
	if not playerData then
		return
	end

	playerData:updateVanityDataInGuiData()

end

function Blueprint.notifyParentPlayer(self: Blueprint)
	super.notifyParentPlayer(self)

	local playerData = self:getPlayerData()
	if not playerData then
		return
	end

	playerData:updateVanityDataInGuiData()
end

function Blueprint.notifyMergingWithTriggerItem(self: Blueprint, triggerItem: any)
	if self:getItemData().mixins.pickup then
		pickupMixin:notifyItemCannotBePickedUp(self)
	end
end

function Blueprint.canBePickedUp(self: Blueprint): boolean
	-- other cases handled by mixin
	return true
end

function Blueprint.setPreventSettling(self: Blueprint)
	self.doPreventSettling = true
end

function Blueprint.getToolName(self: Blueprint): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Blueprint.getSaveData(self: Blueprint, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	return retval
end

function Blueprint.loadSaveData(self: Blueprint, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Blueprint.init(self: Blueprint)
	local vanityComponentName = plotsManager:getVanityComponentNameForBlueprintName(self:getItemName())

	self:getObj():SetAttribute(Attributes.VANITY_COMPONENT_NAME, vanityComponentName);
	collectionService:AddTag(self:getObj(), Tags.BLUEPRINT)

end

function Blueprint.notifyNewClone(self: Blueprint)
	super.notifyNewClone(self)

	self:init()
end

function Blueprint.destroy(self: Blueprint)
	local playerData = self:getPlayerData()

	super.destroy(self)

	if playerData then
		playerData:updateVanityDataInGuiData()
	end
end

function Blueprint.new(itemId: number, itemName: string, userId: number): Blueprint
	local self = (setmetatable(super.new(itemId, itemName, userId), Blueprint) :: any) :: Blueprint

	self:init()

	return self
end

return Blueprint
