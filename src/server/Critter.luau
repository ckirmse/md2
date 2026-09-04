--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local Critter = {}
Critter.__index = setmetatable(Critter, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local CritterHelpers = require("@game/ReplicatedStorage/Shared/CritterHelpers")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local lootTableManager = require("./LootTableManager")


export type CritterFields = Types.CritterFields
export type Critter = Types.Critter

function Critter.beginIdle(self: Critter)

end

function Critter.cleanupIdle(self: Critter)

end

function Critter.beginOpened(self: Critter)
	--print("critter is opened", self:getObj())
	self:getObj():SetAttribute(Attributes.OPENED, true)
end

function Critter.cleanupOpened(self: Critter)

end

function Critter.canKeyOpen(self: Critter, key: any)
	local critterLevel = self:getObjectData().level
	local keyLevel = key:getItemData().level

	return keyLevel >= critterLevel
end

function Critter.isPlayerCloseEnoughToOpen(self: Critter, player: Player)
	local distance = ((player.Character :: any).HumanoidRootPart.Position - self.obj:GetPivot().Position).Magnitude
	local maxDistance = Constants.OPEN_CRITTER_DISTANCE

	if distance > maxDistance * 1.1 then
		print("player tried to open critter but too far away", player, distance, maxDistance)
		return false
	end

	return true
end

function Critter.endState(self: Critter)
	if self.state == enums.CritterState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.CritterState.OPENED then
		self:cleanupOpened()
	else
		warn("end unknown critter state", self, self.state)
	end

	self.state = nil
end

function Critter.beginState(self: Critter, state: number?, ...)
	self.state = state
	--print("critter beginning state", self:getObjectName(), state)

	if self.state == enums.CritterState.IDLE then
		self:beginIdle(...)
	elseif self.state == enums.CritterState.OPENED then
		self:beginOpened(...)
	else
		warn("begin unknown critter state", self, state)
	end
end

function Critter.isPlayerCloseEnoughToShootFireballAtCritter(self: Critter, player: Player)
	local playerData = gameController:getPlayerData(player)
	local maxDistance = playerData:getPlayerVariable(Attributes.FIREBALL_RANGE)

	local distance = ((player.Character :: any).HumanoidRootPart.Position - self:getCurrentPosition()).Magnitude

	if distance > maxDistance * 1.2 then
		print("player tried to shoot fireball at critter but too far away", player, distance, maxDistance)
		return false
	end

	return true
end

function Critter.getFuturePosition(self: Critter, timeFromNowSec: number): Vector3
	local radius = self.radius
	local period = self.period

	local elapsedTime = workspace:GetServerTimeNow() + timeFromNowSec - self.baseTime
	local angle = (elapsedTime / period) * (math.pi * 2)

	local cframe = CritterHelpers.calculateCFrame(self:getObj():GetPivot().Position, radius, angle)
	local position = cframe.Position

	return position
end

function Critter.getCurrentPosition(self: Critter): Vector3
	return self:getFuturePosition(0)
end

function Critter.notifyShotByDragon(self: Critter, dragon: any)
	local player = dragon:getPlayer()
	local playerData = gameController:getPlayerData(player)

	utils.pulseAttribute(self.obj, Attributes.ANIMATION_EXPLODE_CRITTER, "")

	task.wait(0.15)

	if not self:getObj() then
		-- we have been destroyed (player probably logged off)
		return
	end

	local objectData = self:getObjectData()
	local lootName = objectData.lootName
	local lootEntries = lootTableManager:calculateLootResults(lootName)

	-- get the items from the results
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
				acquisitionSource = "shootCrystalCritter",
			}
		)
	end

	gameController:spawnItemsAtPositionAndGoToPlayerBackpack(items, self:getCurrentPosition(), player)

	--[[
	analyticsManager:logEvent(player, analyticsManager.Events.MineNode,
		{
			objectName = self.objectName,
			dragonObjectName = dragon:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
		}
	)
	]]

	playerData:incrementStat("crittersShot")

	self:destroy()
end

function Critter.setState(self: Critter, state: number?, data: any)
	self:endState()

	self:beginState(state, data)
end

function Critter.loadSaveData(self: Critter, objectSaveData: any)
	local state = objectSaveData.state

	self:setState(state)
end

function Critter.getSaveData(self: Critter): any
	return {
		state = self.state,
	}
end


function Critter.destroy(self: Critter)
	if not self.obj then
		return
	end

	self:endState()

	self.obj:Destroy()
	self.obj = nil
end

function Critter.new(objectData: any, cframe: CFrame, objectId: number): Critter
	local self = (setmetatable(super.new(objectData, cframe, objectId), Critter) :: any) :: Critter

	utils.setPropertyTreeBaseParts(self:getObj(), "Transparency", 1)

	self.baseTime = workspace:GetServerTimeNow()

	local random = Random.new()

	self.radius = random:NextNumber(objectData.minRadius, objectData.maxRadius)
	self.period = random:NextNumber(objectData.minPeriod, objectData.maxPeriod)

	--print("creating critter", objectId, cframe)
	self:beginState(enums.ChestState.IDLE)

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, objectData.primaryElement)

	self:getObj():SetAttribute(Attributes.CASTER_PATH, objectData.casterPath) -- not truly a shadow / caster, but very similar
	self:getObj():SetAttribute(Attributes.CRATE_TEMPLATE_PATH, objectData.crateTemplatePath)
	self:getObj():SetAttribute(Attributes.BASE_TIME, self.baseTime)
	self:getObj():SetAttribute(Attributes.RADIUS, self.radius)
	self:getObj():SetAttribute(Attributes.PERIOD, self.period)

	collectionService:AddTag(self:getObj(), Tags.CRITTER)

	return self
end

function Critter.initClass(deps: any)
	gameController = deps.gameController
end

return Critter
