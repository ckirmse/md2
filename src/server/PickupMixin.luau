--!strict

local PickupMixin = {}
PickupMixin.__index = PickupMixin

local collectionService = game:GetService("CollectionService")

local ftueManager = require("./FtueManager")
local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local rideMixin = require("./RideMixin")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

type PickupMixinFields = {}

export type PickupMixin = typeof(setmetatable({} :: PickupMixinFields, PickupMixin))


function PickupMixin.notifyItemCreated(self: PickupMixin, item: any)
	local itemData = item:getItemData()
	local obj = item:getObj()
	local part = item:getPart()

	--print("new pickup item created", obj, item:getUserId())

	-- client depends on this to know when it should be able to pick things up
	obj:SetAttribute(Attributes.USER_ID, item:getUserId())
	obj:SetAttribute(Attributes.PICKUP_NAME, item:getItemName())
	obj:SetAttribute(Attributes.SIZE, itemData.mixins.pickup.underlaySize)
	obj:SetAttribute(Attributes.EQUIP, (itemData.mixins.pickup.equip ~= false))

	-- if it's a model, the part wouldn't normally have this, so we need to add
	part:SetAttribute(Attributes.USER_ID, item:getUserId())

	--print("now listening for changes to item", item:getItemId(), item:getItemName())

	item:getVenueChangedEvent():Connect(
		function(venue)
			--print("item", item:getItemId(), item:getItemName(), "now in venue", venue)

			if itemData.mixins.pickup.equip == false then
				-- non-equippable dragons cannot be picked up from the ground
				return
			end

			if venue == enums.Venues.WORKSPACE_AVAILABLE then
				collectionService:AddTag(obj, Tags.PICKUPABLE)
			elseif venue == enums.Venues.PLAYER then
				collectionService:RemoveTag(obj, Tags.PICKUPABLE)
			elseif venue == enums.Venues.WORKSPACE_SETTLING then
				collectionService:RemoveTag(obj, Tags.PICKUPABLE)
			elseif venue == enums.Venues.WORKSPACE_BUSY then
				collectionService:RemoveTag(obj, Tags.PICKUPABLE)
			else
				warn("unknown venue", venue, "for item", item:getItemId(), item:getItemName(), "now in venue", venue)
			end

		end
	)
end

function PickupMixin.notifyItemCloned(self: PickupMixin, item: any)
	self:notifyItemCreated(item)
end

function PickupMixin.notifyItemCannotBePickedUp(self: PickupMixin, item: any)
	local obj = item:getObj()

	collectionService:RemoveTag(obj, Tags.PICKUPABLE)
end

function PickupMixin.canPickupItem(self: PickupMixin, player: Player, itemId: number)
	local item = itemManager:getItemById(itemId)
	if not item then
		return false
	end

	--print("can pickup have", player, itemId, player.UserId, item:getObj().Parent)

	if item:getUserId() ~= player.UserId then
		return false
	end

	if item:getObj().Parent ~= workspace then
		return false
	end

	if rideMixin:isPlayerRiding(player) then
		return false
	end


	local pickupDistance = utils.getMagnitudeXZ(item:getPart().Position - (player.Character :: any).HumanoidRootPart.Position)
	--print("pickup distance", pickupDistance)

	-- give a little grace distance for pickup
	if pickupDistance > Constants.PICKUP_DISTANCE * 1.2 then
		return false
	end

	if item:canBePickedUp() == false then
		return false
	end

	return true
end

--[[
	Only call this if canPickupItem returns true
]]
function PickupMixin.notifyPickupItem(self: PickupMixin, player: Player, itemId: number)
	local item = itemManager:getItemById(itemId)
	if not item then
		warn("notifyPickupItem for unknown item", itemId)
		return
	end

	ftueManager:notifyPickupItemForPlayer(player, itemId)

	item:pickup()
end

function PickupMixin.new(): PickupMixin
	local self = setmetatable({}, PickupMixin)

	return self
end

function PickupMixin.initClass(deps: any)
	itemManager = deps.itemManager
end

local singleton = PickupMixin.new()

return singleton
