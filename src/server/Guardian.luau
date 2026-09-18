--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local Guardian = {}
Guardian.__index = setmetatable(Guardian, super)

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local nestManager = require("./NestManager")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BiomeData = require("@game/ReplicatedStorage/Shared/BiomeData")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

export type GuardianFields = Types.GuardianFields
export type Guardian = Types.Guardian

local function getBiomeIndexForPosition(position: Vector3): number
	local gate = BiomeData.getGoverningGate(position)
	if gate then
		return gate.biomeIndex
	end
	return 1
end

function Guardian.getBiomeIndex(self: Guardian): number
	return self.biomeIndex
end

function Guardian.findCarrierInBiome(self: Guardian): Types.ShadowDragon?
	for _, dragon in itemManager:getAllDragons() do
		if not dragon:getObj():GetAttribute(Attributes.IS_CARRYING) then
			continue
		end

		local eggItemId = dragon:getObj():GetAttribute(Attributes.CARRIED_EGG_ITEM_ID) :: number?
		if not eggItemId then
			continue
		end

		local eggItem = itemManager:getItemById(eggItemId)
		if not eggItem then
			continue
		end

		if eggItem:getObj():GetAttribute(Attributes.SOURCE_BIOME_INDEX) == self.biomeIndex then
			return dragon
		end
	end
	return nil
end

function Guardian.beginSleeping(self: Guardian)
	self:getObj():SetAttribute(Attributes.GUARDIAN_STATE, enums.GuardianState.SLEEPING)

	local wakeCheckIntervalSec = self:getObjectData().wakeCheckIntervalSec

	self.sleepCheckElapsedSec = 0
	self.sleepCheckConnect = runService.Heartbeat:Connect(function(deltaTime: number)
		self.sleepCheckElapsedSec = (self.sleepCheckElapsedSec :: number) + deltaTime
		if (self.sleepCheckElapsedSec :: number) < wakeCheckIntervalSec then
			return
		end
		self.sleepCheckElapsedSec = 0

		local carrier = self:findCarrierInBiome()
		if carrier then
			self.isForcedEncounter = false
			self:setState(enums.GuardianState.TELEGRAPHING, carrier)
		end
	end)
end

function Guardian.cleanupSleeping(self: Guardian)
	if self.sleepCheckConnect then
		self.sleepCheckConnect:Disconnect()
		self.sleepCheckConnect = nil
	end
end

function Guardian.beginTelegraphing(self: Guardian, dragon: Types.ShadowDragon)
	self.targetDragon = dragon

	self:getObj():SetAttribute(Attributes.GUARDIAN_STATE, enums.GuardianState.TELEGRAPHING)

	local objectData = self:getObjectData()
	self.telegraphTimer = Timer.new(objectData.telegraphSec,
		function()
			self:notifyTelegraphComplete()
		end
	)
end

function Guardian.cleanupTelegraphing(self: Guardian)
	if self.telegraphTimer then
		self.telegraphTimer:cancel()
		self.telegraphTimer = nil
	end
end

function Guardian.notifyTelegraphComplete(self: Guardian)
	if self.state ~= enums.GuardianState.TELEGRAPHING then
		return
	end

	local dragon = self.targetDragon
	local dragonObj = dragon and dragon:getObj()

	local isValidTarget = dragon ~= nil and dragonObj ~= nil and (dragonObj :: Instance).Parent == workspace
	if isValidTarget and not self.isForcedEncounter then
		isValidTarget = (dragonObj :: any):GetAttribute(Attributes.IS_CARRYING) == true
			and getBiomeIndexForPosition((dragonObj :: any):GetPivot().Position) == self.biomeIndex
	end

	if isValidTarget then
		self:setState(enums.GuardianState.CHASING, dragon)
	else
		self:setState(enums.GuardianState.SLEEPING)
	end
end

function Guardian.beginChasing(self: Guardian, dragon: Types.ShadowDragon)
	self.targetDragon = dragon
	self.chaseStartTime = workspace:GetServerTimeNow()

	self:getObj():SetAttribute(Attributes.GUARDIAN_STATE, enums.GuardianState.CHASING)

	local objectData = self:getObjectData()
	self.chaseConnect = runService.Heartbeat:Connect(function(deltaTime: number)
		self:stepChasing(dragon, objectData, deltaTime)
	end)
end

function Guardian.stepChasing(self: Guardian, dragon: Types.ShadowDragon, objectData: any, deltaTime: number)
	local dragonObj = dragon:getObj()
	if not dragonObj or dragonObj.Parent ~= workspace then
		self:setState(enums.GuardianState.RETURNING)
		return
	end

	local targetPosition = dragonObj:GetPivot().Position

	if not self.isForcedEncounter then
		if not dragonObj:GetAttribute(Attributes.IS_CARRYING) then
			self:setState(enums.GuardianState.RETURNING)
			return
		end

		if getBiomeIndexForPosition(targetPosition) ~= self.biomeIndex then
			self:setState(enums.GuardianState.RETURNING)
			return
		end
	end

	if workspace:GetServerTimeNow() - (self.chaseStartTime :: number) >= objectData.chaseMaxSec then
		self:setState(enums.GuardianState.RETURNING)
		return
	end

	local guardianPosition = self:getObj():GetPivot().Position
	local distance = (targetPosition - guardianPosition).Magnitude

	if distance <= objectData.catchDistance then
		self:notifyCaughtDragon(dragon)
		self:setState(enums.GuardianState.RETURNING)
		return
	end

	local speedStat = (dragonObj:GetAttribute(Attributes.DRAGON_SPEED_STAT) :: number?) or 100
	local chaseSpeed = speedStat * objectData.chaseSpeedMultiplier

	local direction = (targetPosition - guardianPosition).Unit
	local step = direction * chaseSpeed * deltaTime
	if step.Magnitude > distance then
		step = direction * distance
	end

	local newPosition = guardianPosition + step
	self:getObj():PivotTo(CFrame.lookAt(newPosition, targetPosition))
end

function Guardian.notifyCaughtDragon(self: Guardian, dragon: Types.ShadowDragon)
	local dragonObj = dragon:getObj()
	local eggItemId = dragonObj:GetAttribute(Attributes.CARRIED_EGG_ITEM_ID) :: number?

	dragonObj:SetAttribute(Attributes.IS_CARRYING, false)
	dragonObj:SetAttribute(Attributes.CARRY_SPEED_MULT, nil)
	dragonObj:SetAttribute(Attributes.CARRIED_EGG_ITEM_ID, nil)

	local stunSec = self:getObjectData().stunSec
	dragonObj:SetAttribute(Attributes.STUNNED_UNTIL, workspace:GetServerTimeNow() + stunSec)

	if eggItemId then
		local item = itemManager:getItemById(eggItemId)
		if item then
			itemManager:destroyItem(item)
		end
	end

	for _, nest in nestManager:getAllNests() do
		if nest:getBiomeIndex() == self.biomeIndex and nest.state == enums.NestState.DEPLETED then
			nest:notifyRefill()
			break
		end
	end

	local player = dragon:getPlayer()
	if player then
		gameController:sendSystemMessageToPlayer(player, "The guardian caught you and reclaimed the egg!")
	end
end

function Guardian.cleanupChasing(self: Guardian)
	if self.chaseConnect then
		self.chaseConnect:Disconnect()
		self.chaseConnect = nil
	end
	self.targetDragon = nil
end

function Guardian.beginReturning(self: Guardian)
	self:getObj():SetAttribute(Attributes.GUARDIAN_STATE, enums.GuardianState.RETURNING)

	local homeCFrame = self.homeCFrame :: CFrame
	local currentPosition = self:getObj():GetPivot().Position
	local distance = (homeCFrame.Position - currentPosition).Magnitude

	if distance <= 0 then
		self:setState(enums.GuardianState.SLEEPING)
		return
	end

	local returnSpeed = self:getObjectData().returnSpeed
	local tweenInfo = TweenInfo.new(distance / returnSpeed, Enum.EasingStyle.Linear)
	local returnTween = PivotToTween(self:getObj(), tweenInfo, homeCFrame)
	self.returnTween = returnTween

	returnTween.Completed:Connect(function()
		if self.state == enums.GuardianState.RETURNING then
			self:setState(enums.GuardianState.SLEEPING)
		end
	end)
	returnTween:Play()
end

function Guardian.cleanupReturning(self: Guardian)
	if self.returnTween then
		self.returnTween:Cancel()
		self.returnTween = nil
	end
end

function Guardian.forceWake(self: Guardian, dragon: Types.ShadowDragon)
	if self.state ~= enums.GuardianState.SLEEPING then
		return
	end
	self.isForcedEncounter = true
	self:setState(enums.GuardianState.TELEGRAPHING, dragon)
end

function Guardian.forceReset(self: Guardian)
	self:setState(enums.GuardianState.SLEEPING)
	self:getObj():PivotTo(self.homeCFrame :: CFrame)
end

function Guardian.endState(self: Guardian)
	if self.state == enums.GuardianState.SLEEPING then
		self:cleanupSleeping()
	elseif self.state == enums.GuardianState.TELEGRAPHING then
		self:cleanupTelegraphing()
	elseif self.state == enums.GuardianState.CHASING then
		self:cleanupChasing()
	elseif self.state == enums.GuardianState.RETURNING then
		self:cleanupReturning()
	else
		warn("end unknown guardian state", self, self.state)
	end

	self.state = nil
end

function Guardian.beginState(self: Guardian, state: number?, data: any)
	self.state = state

	if self.state == enums.GuardianState.SLEEPING then
		self:beginSleeping()
	elseif self.state == enums.GuardianState.TELEGRAPHING then
		self:beginTelegraphing(data)
	elseif self.state == enums.GuardianState.CHASING then
		self:beginChasing(data)
	elseif self.state == enums.GuardianState.RETURNING then
		self:beginReturning()
	else
		warn("begin unknown guardian state", self, state)
	end
end

function Guardian.setState(self: Guardian, state: number?, data: any)
	self:endState()
	self:beginState(state, data)
end

function Guardian.destroy(self: Guardian)
	self:endState()

	self.obj:Destroy()
	self.obj = nil
end

function Guardian.new(objectData: any, cframe: CFrame, objectId: number): Guardian
	local self = (setmetatable(super.new(objectData, cframe, objectId), Guardian) :: any) :: Guardian

	self.homeCFrame = cframe
	self.biomeIndex = objectData.biomeIndex

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())
	collectionService:AddTag(self:getObj(), Tags.GUARDIAN)

	self:beginState(enums.GuardianState.SLEEPING)

	return self
end

function Guardian.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Guardian
