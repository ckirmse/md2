--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local Nest = {}
Nest.__index = setmetatable(Nest, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

export type NestFields = Types.NestFields
export type Nest = Types.Nest

function Nest.getEggSpawnPosition(self: Nest): Vector3
	local eggSpawn = utils.findFirstDescendant(self.obj, "EggSpawn") :: Attachment
	return eggSpawn.WorldPosition
end

function Nest.getBiomeIndex(self: Nest): number
	return (self:getObj():GetAttribute(Attributes.BIOME_INDEX) :: number?) or 1
end

function Nest.getEggItemId(self: Nest): number?
	return self.eggItemId
end

function Nest.isPlayerCloseEnoughToPickupWhileRiding(self: Nest, player: Player): boolean
	local distance = ((player.Character :: any).HumanoidRootPart.Position - self:getEggSpawnPosition()).Magnitude
	return distance <= Constants.PICKUP_EGG_DISTANCE * 1.1
end

function Nest.beginIdle(self: Nest)
	local objectData = self:getObjectData()

	local item = itemManager:createItem(objectData.eggItemName, Constants.UNOWNED_USER_ID)
	if not item then
		warn("nest failed to create egg item", objectData.eggItemName, self:getObjectName())
		return
	end

	item:getObj():PivotTo(CFrame.new(self:getEggSpawnPosition()))
	item:setPreventSettling()
	item:getObj().Parent = workspace
	item:getObj():SetAttribute(Attributes.SOURCE_BIOME_INDEX, self:getBiomeIndex())

	self.eggItemId = item:getItemId()
end

function Nest.cleanupIdle(self: Nest)
	if self.eggItemId then
		local item = itemManager:getItemById(self.eggItemId)
		if item then
			itemManager:destroyItem(item)
		end
		self.eggItemId = nil
	end
end

function Nest.beginDepleted(self: Nest)
	local objectData = self:getObjectData()

	local completeTime = workspace:GetServerTimeNow() + objectData.respawnSec
	self:getObj():SetAttribute(Attributes.NEST_RESPAWN_COMPLETE_TIME, completeTime)

	self.respawnTimer = Timer.new(objectData.respawnSec,
		function()
			self:notifyRefill()
		end
	)
end

function Nest.cleanupDepleted(self: Nest)
	if self.respawnTimer then
		self.respawnTimer:cancel()
		self.respawnTimer = nil
	end

	self:getObj():SetAttribute(Attributes.NEST_RESPAWN_COMPLETE_TIME, nil)
end

function Nest.notifyEggTaken(self: Nest)
	if self.state ~= enums.NestState.IDLE then
		return
	end

	-- the taken egg item itself is not destroyed here -- whatever took it (M4's carry flow) owns it now
	self.eggItemId = nil

	self:setState(enums.NestState.DEPLETED)
end

function Nest.notifyRefill(self: Nest)
	self:setState(enums.NestState.IDLE)
end

function Nest.endState(self: Nest)
	if self.state == enums.NestState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.NestState.DEPLETED then
		self:cleanupDepleted()
	else
		warn("end unknown nest state", self, self.state)
	end

	self.state = nil
end

function Nest.beginState(self: Nest, state: number?)
	self.state = state

	if self.state == enums.NestState.IDLE then
		self:beginIdle()
	elseif self.state == enums.NestState.DEPLETED then
		self:beginDepleted()
	else
		warn("begin unknown nest state", self, state)
	end
end

function Nest.setState(self: Nest, state: number?)
	self:endState()

	self:beginState(state)
end

function Nest.destroy(self: Nest)
	self:endState()

	self.obj:Destroy()
	self.obj = nil
end

function Nest.new(objectData: any, cframe: CFrame, objectId: number): Nest
	local self = (setmetatable(super.new(objectData, cframe, objectId), Nest) :: any) :: Nest

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())
	collectionService:AddTag(self:getObj(), Tags.NEST)

	self:beginState(enums.NestState.IDLE)

	return self
end

function Nest.initClass(deps: any)
	itemManager = deps.itemManager
end

return Nest
