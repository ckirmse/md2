--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local Chest = {}
Chest.__index = setmetatable(Chest, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local lootTableManager = require("./LootTableManager")


export type ChestFields = Types.ChestFields
export type Chest = Types.Chest

function Chest.beginIdle(self: Chest)

end

function Chest.cleanupIdle(self: Chest)

end

function Chest.beginOpening(self: Chest)
end

function Chest.cleanupOpening(self: Chest)

end

function Chest.beginOpened(self: Chest)
	--print("chest is opened", self:getObj())
	self:getObj():SetAttribute(Attributes.OPENED, true)
end

function Chest.cleanupOpened(self: Chest)

end

function Chest.canKeyOpen(self: Chest, key: any)
	local chestLevel = self:getObjectData().level
	local keyLevel = key:getItemData().level

	return keyLevel >= chestLevel
end

function Chest.isClosed(self: Chest)
	return self.state == enums.ChestState.IDLE
end

function Chest.isPlayerCloseEnoughToOpen(self: Chest, player: Player)
	local distance = ((player.Character :: any).HumanoidRootPart.Position - self.obj:GetPivot().Position).Magnitude
	local maxDistance = Constants.OPEN_CHEST_DISTANCE

	if distance > maxDistance * 1.1 then
		print("player tried to open chest but too far away", player, distance, maxDistance)
		return false
	end

	return true
end

function Chest.notifyShouldOpen(self: Chest, key: any)
	--print("chest notify should open", self)
	if self.state ~= enums.ChestState.IDLE then
		return
	end

	--print("chest opening now", self)

	self:setState(enums.ChestState.OPENING)

	utils.pulseAttribute(self:getObj(), Attributes.ANIMATION_OPENING, "")

	local player = key:getPlayer()
	local playerData = gameController:getPlayerData(player);

	-- put away the key (which could be in a stack, of course)
	-- a missing character crashed here before typing too
	(player.Character :: any).Humanoid:UnequipTools()

	task.wait(0.3)

	if not self:getObj() then
		-- we have been destroyed (player probably logged off)
		return
	end

	local objectData = self:getObjectData()
	local lootTableName = objectData.lootName
	local lootEntries = lootTableManager:calculateLootResults(lootTableName)
	local itemCreationData = lootTableManager:getItemCreationDataFromItemLootResults(lootEntries)
	local items = gameController:createItemsFromItemCreationDataForPlayer(itemCreationData, player)

	for _, item in items do
		item:setPreventSettling()
	end

	for _, item in items do
		playerData:notifyItemReceived(item)
	end

	for _, item in items do
		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "openChest",
			}
		)
	end

	gameController:spawnItemsAtPositionAndGoToPlayerBackpack(items, self:getObj():GetPivot().Position + Vector3.new(0, 3, 0), player)

	analyticsManager:logEvent(player, analyticsManager.Events.OpenChest,
		{
			objectName = self.objectName,
			keyObjectName = key:getItemName(),
		}
	)

	-- actually use up the key
	key:reduceCount(1)

	analyticsManager:logEvent(player, analyticsManager.Events.LoseItem,
		{
			objectName = key:getItemName(),
			itemType = key:getType(),
			lossSource = "openChest",
		}
	)

	for _, item in items do
		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "chest",
			}
		)
	end

	self:setState(enums.ChestState.OPENED)
end

function Chest.endState(self: Chest)
	if self.state == enums.ChestState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.ChestState.OPENING then
		self:cleanupOpening()
	elseif self.state == enums.ChestState.OPENED then
		self:cleanupOpened()
	else
		warn("end unknown chest state", self, self.state)
	end

	self.state = nil
end

function Chest.beginState(self: Chest, state: number?, ...)
	self.state = state
	--print("chest beginning state", self:getObjectName(), state)

	if self.state == enums.ChestState.IDLE then
		self:beginIdle(...)
	elseif self.state == enums.ChestState.OPENING then
		self:beginOpening(...)
	elseif self.state == enums.ChestState.OPENED then
		self:beginOpened(...)
	else
		warn("begin unknown chest state", self, state)
	end
end

function Chest.setState(self: Chest, state: number?, data: any)
	self:endState()

	self:beginState(state, data)
end

function Chest.loadSaveData(self: Chest, objectSaveData: any)
	local state = objectSaveData.state

	self:setState(state)
end

function Chest.getSaveData(self: Chest): any
	return {
		state = self.state,
	}
end

function Chest.destroy(self: Chest)
	self:endState()

	self.obj:Destroy()
	self.obj = nil
end

function Chest.new(objectData: any, cframe: CFrame, objectId: number): Chest
	local self = (setmetatable(super.new(objectData, cframe, objectId), Chest) :: any) :: Chest

	self:beginState(enums.ChestState.IDLE)

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())
	self:getObj():SetAttribute(Attributes.LEVEL, self:getObjectData().level)
	collectionService:AddTag(self:getObj(), Tags.CHEST)

	return self
end

function Chest.initClass(deps: any)
	gameController = deps.gameController
end

return Chest
