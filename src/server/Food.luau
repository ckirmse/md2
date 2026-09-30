--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local Food = {}
Food.__index = setmetatable(Food, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local rideMixin = require("./RideMixin")

local Tags = require("@game/ReplicatedStorage/Shared/Tags")


export type FoodFields = Types.FoodFields
export type Food = Types.Food

function Food.getDataDumpString(self: Food): string
	local text = super.getDataDumpString(self)

	return text
end

function Food.notifyParentWorkspace(self: Food)
	if self:getIsParentingOnLoad() or self.doPreventSettling then
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
		end
	)
end

function Food.notifyParentPlayer(self: Food)
	super.notifyParentPlayer(self)
end

function Food.canBePickedUp(self: Food): boolean
	return true
end

function Food.setPreventSettling(self: Food)
	self.doPreventSettling = true
end

-- overridden without calling super: feeds the ridden dragon instead of dropping the item. The
-- client only shows this tool's activate button while riding; re-validated here regardless.
function Food.notifyToolActivated(self: Food)
	local player = self:getPlayer()
	if not player then
		return
	end

	if not rideMixin:isPlayerRiding(player) then
		warn("food activated while not riding", player)
		return
	end

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		warn("food activated while riding, but no riding dragon found", player)
		return
	end

	local itemData = self:getItemData()

	dragon:addDragonXp(itemData.foodXp)

	self:reduceCount(1)
end

function Food.getSaveData(self: Food, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	return retval
end

function Food.loadSaveData(self: Food, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Food.init(self: Food)
	collectionService:AddTag(self:getObj(), Tags.FOOD)
end

function Food.notifyNewClone(self: Food)
	super.notifyNewClone(self)

	self:init()
end

function Food.new(itemId: number, itemName: string, userId: number): Food
	local self = (setmetatable(super.new(itemId, itemName, userId), Food) :: any) :: Food

	self:init()

	return self
end

return Food
