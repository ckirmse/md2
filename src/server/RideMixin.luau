--!strict

local RideMixin = {}
RideMixin.__index = RideMixin

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local indexManager = require("./IndexManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

type RideMixinFields = {}

export type RideMixin = typeof(setmetatable({} :: RideMixinFields, RideMixin))

-- some part needs to be marked with Attributes.SEAT_LOCATION for this to work

function RideMixin.notifyItemCreated(self: RideMixin, item: any)
	local obj = item:getObj()

	local itemData = item:getItemData()

	obj:SetAttribute(Attributes.DRAGON_RISE_SPEED, itemData.mixins.ride.riseSpeed)
	obj:SetAttribute(Attributes.USER_ID, item:getUserId())

	collectionService:AddTag(obj, Tags.RIDABLE)

end

function RideMixin.notifyItemCloned(self: RideMixin, item: any)
	self:notifyItemCreated(item)
end

function RideMixin.canRideItem(self: RideMixin, player: Player, itemId: number): boolean
	-- only dragons are ridable
	local item = itemManager:getItemById(itemId) :: Types.ShadowDragon?
	if not item then
		print("canRideItem false due to unknown item", player, itemId)
		return false
	end

	--print("can ride have", player, itemId, player.UserId, item:getObj().Parent)

	if item:getUserId() ~= player.UserId then
		print("canRideItem false due to user id not matching", player, item)
		return false
	end

	if item:getObj().Parent ~= workspace then
		print("canRideItem false due to item not in workspace", player, item)
		return false
	end

	if self:isPlayerRiding(player) then
		print("canRideItem false due to player already riding", player)
		return false
	end


	local playerPosition = (player.Character :: any).HumanoidRootPart.Position
	local seatPosition = item:getObj():GetPivot():PointToWorldSpace(item:getItemData().seatOffset)
	--print("positions player", playerPosition, "seat", seatPosition, "dragon", item:getObj():GetPivot().Position)

	local distance = utils.getMagnitudeXZ(playerPosition - seatPosition)
	if distance > Constants.BEGIN_RIDE_DISTANCE * 1.4 then
		print("canRideItem false due to player too far away", player, distance)
		return false
	end

	local itemData = item:getItemData()
	if not itemData.mixins.ride then
		print("canRideItem false due to item not being ridable", player, item)
		return false
	end

	local playerData = gameController:getPlayerData(player)
	indexManager:notifyItemDiscoveredIfNew(player, playerData, item:getItemName())

	if itemManager:isMutationCapableType(item:getType()) then
		local mutation = item:getMutation()
		if mutation and mutation ~= enums.Mutations.NORMAL then
			indexManager:notifyMutationDiscoveredIfNew(player, playerData, mutation)
		end
	end

	return true
end

--[[
	Only call this if canRideItem returns true
]]
function RideMixin.notifyPlayerBeginRideDragon(self: RideMixin, player: Player, itemId: number, playerRelativeToDragonCFrame: CFrame?)
	--print("ride mixin begin ride", player, itemId)

	-- the documented prerequisite: canRideItem returned true, so the dragon exists
	local item = itemManager:getItemById(itemId) :: Types.ShadowDragon;

	-- a missing character crashed here before typing too
	(player.Character :: any).Humanoid:UnequipTools()

	item:notifyRideBegin()

	local playerData = gameController:getPlayerData(player)

	playerData:setRiding(itemId, playerRelativeToDragonCFrame)

	-- move the player to where they start riding
	-- if player is controlling dragon, this is irrelevant, but if dragon is openingc a crystal or something, then this is necessary
	playerData:notifyRidingItemCFrame(item:getObj():GetPivot())
end

function RideMixin.notifyPlayerEndRideDragon(self: RideMixin, player: Player, itemId: number)
	--print("ride mixin end ride", player, itemId)

	local item = itemManager:getItemById(itemId) :: Types.ShadowDragon?

	gameController:getPlayerData(player):setRiding(nil, nil)

	if item then
		item:notifyRideEnd()
	end
end

function RideMixin.tryGetRidingDragonForPlayer(self: RideMixin, player: Player): Types.ShadowDragon?
	local itemId = gameController:getPlayerData(player):getRidingItemId()
	if not itemId then
		return nil
	end

	local dragon = itemManager:getItemById(itemId) :: Types.ShadowDragon?

	return dragon
end

function RideMixin.isPlayerRiding(self: RideMixin, player: Player): boolean
	return gameController:getPlayerData(player):getRidingItemId() ~= nil
end

function RideMixin.stopPlayerRiding(self: RideMixin, player: Player)
	RemoteEvents.NotifyStopRiding:FireClient(player)
	local playerData = gameController:getPlayerData(player)
	local itemId = playerData:getRidingItemId()
	if not itemId then
		print("ride mixin told to stop player riding, but they are not riding")
		return
	end

	playerData:setRiding(nil, nil)

	local item = itemManager:getItemById(itemId) :: Types.ShadowDragon?
	if item then
		item:notifyRideEnd()
	end
end

function RideMixin.new(): RideMixin
	local self = setmetatable({}, RideMixin)

	return self
end

function RideMixin.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

local singleton = RideMixin.new()

return singleton
