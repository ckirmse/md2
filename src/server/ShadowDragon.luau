--!strict


local MItem = require("./MItem")
local super = MItem

local ShadowDragon = {}
ShadowDragon.__index = setmetatable(ShadowDragon, super)

local collectionService = game:GetService("CollectionService")

local DirectFlyItemMover = require("./DirectFlyItemMover")
local DubinsItemMover = require("./DubinsItemMover")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local islandManager = require("./IslandManager")
local playerAttributesManager = require("./PlayerAttributesManager")
local plotsManager = require("./PlotsManager")
local rideMixin = require("./RideMixin")
local stableManager = require("./StableManager")
local UpAndOverItemMover = require("./UpAndOverItemMover")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local DragonPower = require("@game/ReplicatedStorage/Shared/DragonPower")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToIndependentTween = require("@game/ReplicatedStorage/Shared/PivotToIndependentTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local dragonPowerValues = require("@game/ServerScriptService/GameData/Control/DragonPowerValues")

local analyticsManager = require("./AnalyticsManager")


local DRAGON_IDEAL_MINING_DISTANCE = 20

export type ShadowDragonFields = Types.ShadowDragonFields
export type ShadowDragon = Types.ShadowDragon

function ShadowDragon.getDataDumpString(self: ShadowDragon): string
	local itemData = self:getItemData()

	local text = super.getDataDumpString(self)
	text = text .. "\nState: " .. tostring(enums.getName(enums.DragonState, self.state))
	if itemData.mixins.ride then
		text = text .. string.format("\nStamina %f", self.stamina)
	end

	return text
end

function ShadowDragon.notifyParentWorkspace(self: ShadowDragon)
	self:getPart().Anchored = true

	if self.state == enums.DragonState.IDLE then
		if self:getIsParentingOnLoad() or self.doPreventSettling then
			self.doPreventSettling = false
			--print("dragon now in workspace from idle, skipping settle", self:getItemId())
			local currentPosition = self:getObj():GetPivot().Position
			self.lastKnownGoodIdleLocation = Vector3.new(currentPosition.X, 0, currentPosition.Z)

			self:setupIdleInWorkspace()
		else
			--print("dragon now in workspace from idle, NOT parenting on load, going to settling", self:getItemId())
			self:setState(enums.DragonState.SETTLING)
		end
	else
		-- does get here with state OPENING on load
		-- also gets here in MOVING_TO_IDLE when created from dev tool, which isn't right
		-- and MOVING_TO_EAT in production as of 2026-april-14
		--print("dragon now in workspace, state", enums.getName(enums.DragonState, self.state), self:getItemId())
	end
end

function ShadowDragon.notifyParentPlayer(self: ShadowDragon)
	super.notifyParentPlayer(self)

	-- should we have a "held" state? probably yes... ah well, not right now

	self:setState(enums.DragonState.IDLE)
end

function ShadowDragon.notifyItemMoverDone(self: ShadowDragon)
	--print("shadow dragon item mover done")

	if self.state == enums.DragonState.MOVING_TO_IDLE then
		if self.movingToIdle.isStableSlotReturn then
			local destCFrame = self.movingToIdle.destCFrame

			if self.movingToIdle.needsExactApproach then
				-- ease the last gap into the exact pose
				self.movingToIdle.needsExactApproach = false
				if self.movingToIdle.itemMover then
					self.movingToIdle.itemMover:destroy()
					self.movingToIdle.itemMover = nil
				end

				local tween = self:createSettleTween(0.8, destCFrame)
				self.movingToIdle.approachTween = tween
				tween.Completed:Once(function()
					self:notifyItemMoverDone()
				end)
				tween:Play()
				return
			end

			self:setPreventSettling()
			self:endState()
			self:getObj():PivotTo(destCFrame)
			self:beginState(enums.DragonState.IDLE)
			local periodDivisor, amplitudeMultiplier = self:getFlapDataForCurrentState()
			self:setFlapData(periodDivisor, amplitudeMultiplier)
			return
		end

		self:setState(enums.DragonState.IDLE)
	elseif self.state == enums.DragonState.MOVING_TO_EAT then
		local crop = itemManager:getItemById(self.movingToEat.cropItemId)
		self.movingToEat.isComplete = true

		if crop == nil then
			-- crop was merged away or something
			self:setState(enums.DragonState.IDLE)
			return
		end

		-- this will set our next state, whatever it should be
		gameController:tryBeginDragonEatingCrop(self, crop)

		return
	elseif self.state == enums.DragonState.MOVING_TO_OPEN then
		local crystal = itemManager:getItemById(self.movingToOpen.crystalItemId)
		self.movingToOpen.isComplete = true

		-- this will set our next state, whatever it should be
		gameController:tryBeginDragonOpeningCrystal(self, crystal)
		return
	elseif self.state == enums.DragonState.MOVING_TO_MINE then
		local node = islandManager:getNodeByObjectId(self.movingToMine.nodeObjectId)
		local player = self:getPlayer()
		if not node or not player or not node:canBeMinedByPlayer(player) then
			-- it went away or got mined while we were moving
			self:notifyShouldMoveToIdle()
			return
		end

		self.movingToMine.isComplete = true

		self:notifyShouldChargeUp()
		task.delay(Constants.FIREBALL_CHARGE_SEC,
			function()
				if self.state ~= enums.DragonState.MOVING_TO_MINE then
					-- we were already destroyed or otherwise changed
					return
				end

				self:notifyShouldMineNode(node)
			end
		)
		return
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		self:setState(enums.DragonState.OUTSIDE)
	else
		warn("item mover while in unexpected state", self, self.state)
	end

end

function ShadowDragon.setupIdleInWorkspace(self: ShadowDragon)
	local itemData = self:getItemData()

	if self.stableSlotIndex ~= nil then
		-- parked: server-controlled and static, no hover
		self:setServerControlMotion()
		self:getObj():SetAttribute(Attributes.DRAGON_PULSE_DATA, nil)
		self:setVenueWorkspaceAvailable()
		return
	end

	self:setClientControlMotion()

	--print("dragon setupIdleInWorkspace", self:getItemId(), "at", self:getPart().Position)

	-- add a little randomness to period so they won't all be in sync
	self:getObj():SetAttribute(Attributes.DRAGON_PULSE_DATA, string.format("%.3f %.1f %.1f", itemData.idle.pulsePeriodSec + self.random:NextNumber(0, 0.3), itemData.idle.pulseAmplitudePlayerFar, itemData.idle.pulseAmplitudePlayerNear or 0))

	self:setVenueWorkspaceAvailable()
end

function ShadowDragon.beginIdle(self: ShadowDragon, data: any)
	if self:getObj().Parent ~= workspace then
		self:setServerControlMotion()
		return
	end

	self:setupIdleInWorkspace()
end

function ShadowDragon.cleanupIdle(self: ShadowDragon)
	self:getObj():SetAttribute(Attributes.DRAGON_PULSE_DATA, nil)
end

function ShadowDragon.calculateGoodIdleLocation(self: ShadowDragon): Vector3
	local dragons = itemManager:getDragonsOnGroundForUserId(self:getUserId())
	local crops = itemManager:getCropsOnGroundForUserId(self:getUserId())

	local awayLocations = {}
	for _, item in dragons do
		if item == self then
			continue
		end

		-- for dragons moving to idle, we get their destination spot instead
		local dragonLocation = item:getPart().Position
		if item.state == enums.DragonState.MOVING_TO_IDLE then
			dragonLocation = item.movingToIdle.destCFrame.Position
		end

		table.insert(awayLocations, dragonLocation)
	end
	for _, item in crops do
		table.insert(awayLocations, item:getPart().Position)
	end

	-- dragons always belong to a user with a plot, so the cast keeps the previous crash-on-nil behavior
	local location = plotsManager:getRandomLocationInMainPlotByUserId(self:getUserId()) :: Vector3
	location = Vector3.new(location.X, 0, location.Z)

	if #awayLocations == 0 then
		return location
	end

	for i = 1, 100 do
		--print("dragon find idle location step", i, "location", location)
		local minDistance = math.huge
		local closestLocation = nil
		for _, awayLocation in awayLocations do
			local distance = utils.getMagnitudeXZ(awayLocation - location)
			if distance < minDistance then
				minDistance = distance
				closestLocation = awayLocation
			end
		end
		if not closestLocation then
			break
		end

		local direction = closestLocation - location
		direction = Vector3.new(direction.X, 0, direction.Y)

		local diffLocation
		if utils.getMagnitudeXZ(direction) > 5 then
			if utils.getMagnitudeXZ(direction) < 30 then
				--print("dragon find idle calculation success, direction", direction, "magnitude", direction.Magnitude, "steps", i)
				break
			end

			-- very far from any dragon, move a little bit towards nearest one
			diffLocation = 0.1 * direction
		else
			-- very close to a dragon, move a little bit away from it
			diffLocation = -0.1 * direction
		end

		location += diffLocation
	end

	return location
end

function ShadowDragon.calculateIdleHeightAtLocation(self: ShadowDragon, location: Vector3): number
	local groundY = (utils.getGroundHeight(location.X, location.Z) or 0)

	local itemData = self:getItemData()

	local destY = groundY + self.random:NextNumber(itemData.idle.minHeight, itemData.idle.maxHeight)

	return destY
end

function ShadowDragon.beginMovingToIdleWithPosition(self: ShadowDragon, position: Vector3)
	if utils.getMagnitudeXZ(position - self:getPart().Position) < 0.1 then
		-- maintain current orientation if staying in place, just changing Y
		local destCFrame = CFrame.new(position) * self:getPart().CFrame.Rotation
		self.movingToIdle.destCFrame = destCFrame

		--print("just changing Y, using DirectFlyItemMover to", self.movingToIdle.destCFrame.Position)
		self.movingToIdle.itemMover = DirectFlyItemMover.new(self:getItemId(), self.movingToIdle.destCFrame)
	else
		-- pick random orientation if moving elsewhere
		local destCFrame = CFrame.new(position) * CFrame.fromEulerAnglesXYZ(0, self.random:NextNumber(0, math.pi * 2), 0)
		self.movingToIdle.destCFrame = destCFrame

		local minRadius = self:getItemData().movement.minRadius
		--print("dubins move to idle to", self.movingToIdle.destCFrame.Position, minRadius)
		self.movingToIdle.itemMover = DubinsItemMover.new(self:getItemId(), self.movingToIdle.destCFrame, minRadius)
	end

	if not self.movingToIdle.itemMover:tryBegin() then
		self:setState(enums.DragonState.IDLE)
        return
    end
end

-- fly to an exact CFrame: dubins to a point in front of it (facing it, so no orbit), then
-- a short tween lands the exact pose (see notifyItemMoverDone)
function ShadowDragon.beginMovingToIdleWithCFrame(self: ShadowDragon, destCFrame: CFrame)
	self:setServerControlMotion()

	self.movingToIdle.destCFrame = destCFrame
	self.movingToIdle.isStableSlotReturn = true

	local toDest = destCFrame.Position - self:getPart().Position
	local flatToDest = Vector3.new(toDest.X, 0, toDest.Z)

	if flatToDest.Magnitude < 8 then
		self.movingToIdle.needsExactApproach = true
		self:notifyItemMoverDone()
		return
	end

	local approachDir = flatToDest.Unit
	local approachPos = destCFrame.Position - approachDir * 6
	local dubinsTarget = CFrame.lookAt(approachPos, approachPos + approachDir)

	local minRadius = self:getItemData().movement.minRadius
	self.movingToIdle.itemMover = DubinsItemMover.new(self:getItemId(), dubinsTarget, minRadius)
	self.movingToIdle.needsExactApproach = true

	if not self.movingToIdle.itemMover:tryBegin() then
		self:setState(enums.DragonState.IDLE)
		return
	end
end

-- location is a Vector3 where the X and Z are definitive, and we should calculate a Y
function ShadowDragon.beginMovingToIdleWithLocation(self: ShadowDragon, location: Vector3)
	--print("moving to idle with location", self:getPart().Position, location)

	local destY = self:calculateIdleHeightAtLocation(location)
	local destPosition = Vector3.new(location.X, destY, location.Z)

	self:beginMovingToIdleWithPosition(destPosition)
end

function ShadowDragon.beginMovingToIdle(self: ShadowDragon)
	--print("moving", self:getItemName(), "to idle spot")

	self:setServerControlMotion()

	local idleLocation
	if self.lastKnownGoodIdleLocation then
		idleLocation = self.lastKnownGoodIdleLocation
		--print("dragon moving to last known good idle", idleLocation)
	else
		-- pick a "random"-ish location
		idleLocation = self:calculateGoodIdleLocation()
		--print("dragon moving to new random location", idleLocation)
	end

	self:beginMovingToIdleWithLocation(idleLocation)
end

function ShadowDragon.cleanupMovingToIdle(self: ShadowDragon)
	if self.movingToIdle.itemMover then
		self.movingToIdle.itemMover:destroy()
		self.movingToIdle.itemMover = nil
	end

	if self.movingToIdle.approachTween then
		self.movingToIdle.approachTween:Cancel()
		self.movingToIdle.approachTween = nil
	end

	self.movingToIdle = {}
end

function ShadowDragon.beginEating(self: ShadowDragon, crop: any)
	self.eating.eatingItemId = crop:getItemId()

	self:setServerControlMotion()

	self:getObj():SetAttribute(Attributes.ANIMATION_EAT, string.format("%i", self:getItemData().eat.audioPitchShift))
end

function ShadowDragon.cleanupEating(self: ShadowDragon)
	if not self.eating.eatingItemId then
		warn("dragon cleanupEating without an itemId", self, "should not be possible")
		return
	end

	self:getObj():SetAttribute(Attributes.ANIMATION_EAT, nil)

	local crop = itemManager:getItemById(self.eating.eatingItemId)

	self.eating = {}

	-- crop may not exist if a player is being removed
	if crop then
		gameController:notifyDragonStoppedEatingCrop(self, crop)
	end
end

function ShadowDragon.beginMovingToEat(self: ShadowDragon, crop: any)
	self.movingToEat.cropItemId = crop:getItemId()
	self.movingToEat.isComplete = false

	self:setServerControlMotion()

	self:setVenueWorkspaceBusy()

	local dragonPosition = self:getPart().Position

	local fruitPosition

	-- pick nearest fruit on the crop to the dragon
	-- fruit parts are BaseParts; anything else crashed here before typing too
	local fruitParts = utils.getAllDescendantsWithAttribute(crop:getObj(), Attributes.VARIABLE_FOOD, true) :: { any }
	if #fruitParts == 0 then
		warn("dragon eating from a crop with no fruits, should not be possible", crop)
		fruitPosition = crop:getPart().Position
	else
		local bestFruit = fruitParts[1]
		local bestDistance = (bestFruit.Position - dragonPosition).Magnitude
		for _, fruit in fruitParts do
			local distance = (fruit.Position - dragonPosition).Magnitude
			if distance < bestDistance then
				bestFruit = fruit
				bestDistance = distance
			end
		end
		fruitPosition = bestFruit.Position
	end

	local towardsDragon = Vector3.new(dragonPosition.X - fruitPosition.X, 0, dragonPosition.Z - fruitPosition.Z).Unit
	local destPosition = fruitPosition + towardsDragon * self:getItemData().distanceToTipOfNose

	local diffPosition = destPosition - dragonPosition
	local cframe = CFrame.lookAlong(destPosition, diffPosition)
	cframe = utils.getCFrameParallelToGround(cframe)
	local aimDown = CFrame.fromAxisAngle(cframe.RightVector, -math.rad(20))
	cframe = aimDown.Rotation * cframe.Rotation + cframe.Position

	self.movingToEat.itemMover = UpAndOverItemMover.new(self:getItemId(), cframe)
	self.movingToEat.itemMover:setStepCallback(
		function(cframe)
			if not self.isRiding then
				return
			end
			local player = self:getPlayer()
			if not player then
				return
			end
			local playerData = gameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:notifyRidingItemCFrame(cframe)
		end
	)

	--print("dragon moving to eat", self:getItemName(), self:getPart().Position, crop:getItemName(), crop:getPart().Position)

	if not self.movingToEat.itemMover:tryBegin() then
 		self:setState(enums.DragonState.MOVING_TO_IDLE)
        return
    end
end

function ShadowDragon.cleanupMovingToEat(self: ShadowDragon)
	if self.movingToEat.itemMover then
		self.movingToEat.itemMover:destroy()
		self.movingToEat.itemMover = nil
	end

	if not self.movingToEat.isComplete then
		-- dragon didn't successfully move to eat, so the crop should be edible again
		local crop = itemManager:getItemById(self.movingToEat.cropItemId) :: Types.Crop?
		if crop then
			crop:notifyDragonNoLongerComingToEat(self)
		end
	end

	self.movingToEat = {}
end

function ShadowDragon.beginMovingToOpen(self: ShadowDragon, crystal: any)
	self.movingToOpen.crystalItemId = crystal:getItemId()
	self.movingToOpen.isComplete = false

	self:setServerControlMotion()

	self:setVenueWorkspaceBusy()

	local dragonPosition = self:getPart().Position
	local crystalPosition = crystal:getPart().Position

	local inclinationAngle = math.rad(30)

	local flatTowardsDragon = Vector3.new(dragonPosition.X - crystalPosition.X, 0, dragonPosition.Z - crystalPosition.Z)
	local inclinedY = flatTowardsDragon.Magnitude * math.tan(inclinationAngle)
	local towardsDragon = Vector3.new(flatTowardsDragon.X, inclinedY, flatTowardsDragon.Z).Unit
	--print("inclined Y an extra", inclinedY)

	local openDistance = self:getItemData().open.distance
	local destPosition = crystalPosition + towardsDragon * openDistance

	local diffPosition = crystalPosition - destPosition
	local cframe = CFrame.lookAlong(destPosition, diffPosition)
	cframe = utils.getCFrameParallelToGround(cframe)
	local aimDown = CFrame.fromAxisAngle(cframe.RightVector, -inclinationAngle)
	cframe = aimDown.Rotation * cframe.Rotation + cframe.Position

	self.movingToOpen.itemMover = UpAndOverItemMover.new(self:getItemId(), cframe)
	self.movingToOpen.itemMover:setStepCallback(
		function(cframe)
			if not self.isRiding then
				return
			end
			local player = self:getPlayer()
			if not player then
				return
			end
			local playerData = gameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:notifyRidingItemCFrame(cframe)
		end
	)
	--print("dragon moving to open", self:getItemName(), self:getPart().Position, crystal:getItemName(), crystal:getPart().Position)

	if not self.movingToOpen.itemMover:tryBegin() then
 		self:setState(enums.DragonState.MOVING_TO_IDLE)
        return
    end
end

function ShadowDragon.cleanupMovingToOpen(self: ShadowDragon)
	if self.movingToOpen.itemMover then
		self.movingToOpen.itemMover:destroy()
		self.movingToOpen.itemMover = nil
	end

	if not self.movingToOpen.isComplete then
		-- dragon didn't successfully move to open, so the crystal should be openable again
		local crystal = itemManager:getItemById(self.movingToOpen.crystalItemId) :: Types.Crystal?
		if crystal then
			crystal:notifyDragonNoLongerComingToOpen(self)
		end
	end

	self.movingToOpen = {}
end

function ShadowDragon.beginOpening(self: ShadowDragon, crystal: any)
	--print("shadow dragon now opening a crystal", crystal)

	self.opening.crystalItemId = crystal:getItemId()

	self:setServerControlMotion()

	self:getObj():SetAttribute(Attributes.ANIMATION_OPENING, crystal:getItemId())
end

function ShadowDragon.cleanupOpening(self: ShadowDragon)
	--print("shadow dragon now cleanup opening a crystal")

	self:getObj():SetAttribute(Attributes.ANIMATION_OPENING, nil)

	local crystal = itemManager:getItemById(self.opening.crystalItemId)
	self.opening = {}
	-- crystal may not exist if a player is being removed
	if crystal then
		gameController:notifyDragonStoppedOpeningCrystal(self, crystal)
	end
end

function ShadowDragon.beginMovingToMine(self: ShadowDragon, node: any)
	self.movingToMine.nodeObjectId = node:getObjectId()
	self.movingToMine.isComplete = false

	self:setServerControlMotion()

	self:setVenueWorkspaceBusy()

	local dragonPosition = self:getPart().Position
	local nodeTargetPosition = node:getMineTargetPosition()

	local inclinationAngle = math.rad(45)

	local flatTowardsDragon = Vector3.new(dragonPosition.X - nodeTargetPosition.X, 0, dragonPosition.Z - nodeTargetPosition.Z)
	local inclinedY = flatTowardsDragon.Magnitude * math.tan(inclinationAngle)
	local towardsDragon = Vector3.new(flatTowardsDragon.X, inclinedY, flatTowardsDragon.Z).Unit
	--print("inclined Y an extra", inclinedY)

	local mineDistance = DRAGON_IDEAL_MINING_DISTANCE
	local destPosition = nodeTargetPosition + towardsDragon * mineDistance

	local diffPosition = nodeTargetPosition - destPosition
	local cframe = CFrame.lookAlong(destPosition, diffPosition)
	cframe = utils.getCFrameParallelToGround(cframe)
	local aimDown = CFrame.fromAxisAngle(cframe.RightVector, -inclinationAngle)
	cframe = aimDown.Rotation * cframe.Rotation + cframe.Position

	self.movingToMine.itemMover = UpAndOverItemMover.new(self:getItemId(), cframe)
	self.movingToMine.itemMover:setStepCallback(
		function(cframe)
			if not self.isRiding then
				return
			end
			local player = self:getPlayer()
			if not player then
				return
			end
			local playerData = gameController:getPlayerData(player)
			if not playerData then
				return
			end
			playerData:notifyRidingItemCFrame(cframe)
		end
	)

	--print("dragon moving to mine", self:getItemName(), self:getPart().Position, node, nodeTargetPosition)

	if not self.movingToMine.itemMover:tryBegin() then
 		self:setState(enums.DragonState.MOVING_TO_IDLE)
        return
	end
end

function ShadowDragon.cleanupMovingToMine(self: ShadowDragon)
	if self.movingToMine.itemMover then
		self.movingToMine.itemMover:destroy()
		self.movingToMine.itemMover = nil
	end

	self.movingToMine = {}
end

function ShadowDragon.beginOutside(self: ShadowDragon, data: any)
	self:setClientControlMotion()

	local itemData = self:getItemData()

	self:getObj():SetAttribute(Attributes.DRAGON_PULSE_DATA, string.format("%.1f %.1f %.1f", itemData.idle.pulsePeriodSec, itemData.idle.pulseAmplitudePlayerFar / 2, itemData.idle.pulseAmplitudePlayerNear / 2 or 0))
end

function ShadowDragon.cleanupOutside(self: ShadowDragon)
	self:getObj():SetAttribute(Attributes.DRAGON_PULSE_DATA, nil)
end

function ShadowDragon.beginMovingToOutside(self: ShadowDragon, data: any)
	--print("moving to outside spot", self.lastKnownGoodOutsidePosition)

	self:setServerControlMotion()

	-- the outside position is always recorded before this state begins
	local destPosition = self.lastKnownGoodOutsidePosition :: Vector3

	if utils.getMagnitudeXZ(destPosition - self:getPart().Position) < 0.1 then
		-- maintain current orientation if staying in place, just changing Y
		local destCFrame = CFrame.new(destPosition) * self:getPart().CFrame.Rotation
		self.movingToOutside.destCFrame = destCFrame

		--print("just changing Y, using DirectFlyItemMover to", self.movingToOutside.destCFrame.Position)
		self.movingToOutside.itemMover = DirectFlyItemMover.new(self:getItemId(), self.movingToOutside.destCFrame)
	else
		-- pick random orientation if moving elsewhere
		local destCFrame = CFrame.new(destPosition) * CFrame.fromEulerAnglesXYZ(0, self.random:NextNumber(0, math.pi * 2), 0)
		self.movingToOutside.destCFrame = destCFrame

		--print("dubins move to outside to", self.movingToOutside.destCFrame.Position)
		local minRadius = self:getItemData().movement.minRadius
		self.movingToOutside.itemMover = DubinsItemMover.new(self:getItemId(), self.movingToOutside.destCFrame, minRadius)
	end

	if not self.movingToOutside.itemMover:tryBegin() then
		self:setState(enums.DragonState.OUTSIDE)
        return
    end

end

function ShadowDragon.cleanupMovingToOutside(self: ShadowDragon)
	if self.movingToOutside.itemMover then
		self.movingToOutside.itemMover:destroy()
		self.movingToOutside.itemMover = nil
	end

	self.movingToOutside = {}
end

function ShadowDragon.getSettlePositionForLocation(self: ShadowDragon, location: Vector3): Vector3
	local destY = self:calculateIdleHeightAtLocation(location)
	local position = Vector3.new(location.X, destY, location.Z)

	--local groundPosition = utils.getGroundPositionForLocation(location)
	--print("ground Y is", groundPosition.Y, "we picked", destY)

	return position
end

function ShadowDragon.getSettleCFrameForPosition(self: ShadowDragon, position: Vector3): CFrame
	if self:getItemData().mixins.pickup.equip == false then
		-- high level dragons get here
		-- point them away from player so it looks good as they zoom there

		local lookVector = position - (self:getPlayer() :: any).Character.HumanoidRootPart.Position
		local directionCFrame = CFrame.lookAlong(position, lookVector)
		local finalCFrame = utils.getCFrameParallelToGround(directionCFrame)
		return finalCFrame
	end

	return super.getSettleCFrameForPosition(self, position)
end

function ShadowDragon.getSettleDurationForPosition(self: ShadowDragon, position: Vector3): number
	if self:getItemData().mixins.pickup.equip == false then
		-- high level dragons get here

		local distance = (position - self.obj:GetPivot().Position).Magnitude
		return distance / 30
	end

	return super.getSettleDurationForPosition(self, position)
end

function ShadowDragon.createSettleTween(self: ShadowDragon, duration: number, cframe: CFrame): Tween
	-- the default is to bounce. But we're a dragon and can fly! So no bounce.
	return PivotToIndependentTween(self:getObj(), duration, "linear", "linear", "outQuad", "linear", cframe)
end

function ShadowDragon.beginSettling(self: ShadowDragon)
	self:setServerControlMotion()

	local extraRepulsors = nil
	if self:getItemData().mixins.pickup.equip == false then
		extraRepulsors = (
			{
				{
					position = (self:getPlayer() :: any).Character.HumanoidRootPart.Position,
					boardSpacing = 25,
				}
			}
		)
	end

	self:settleOnGroundInWorkspace(
		function()
			if not self:getObj() then
				return
			end

			local currentPosition = self:getObj():GetPivot().Position
			self.lastKnownGoodIdleLocation = Vector3.new(currentPosition.X, 0, currentPosition.Z)

			self:setVenueWorkspaceAvailable()

			self:setState(enums.DragonState.IDLE)
		end,
		extraRepulsors
	)
end

function ShadowDragon.cleanupSettling(self: ShadowDragon)
end


function ShadowDragon.notifyShouldMineNode(self: ShadowDragon, node: any)
	--print("dragon should now mine a node")

	local nodeTargetPosition = node:getMineTargetPosition()

	local attributeStr = string.format("%s %.2f %.2f %.2f", self:getItemData().fireballPath, nodeTargetPosition.X, nodeTargetPosition.Y, nodeTargetPosition.Z)
	--print("full attribute is", attributeStr)
	self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, attributeStr)

	local nodeObjectId = node:getObjectId()

	local animationSec = Constants.FIREBALL_TRAVEL_SEC

	task.delay(animationSec,
		function()
			if not self.state then
				-- we were already destroyed
				return
			end
			self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, nil)

			local node = islandManager:getNodeByObjectId(nodeObjectId)
			if node then
				local player = self:getPlayer()
				if not player then
					return
				end

				-- yay, actually mine it!
				node:notifyMinedByDragon(self)
			end

			if self.isRiding then
				self:setState(enums.DragonState.IDLE)
			elseif self.lastKnownGoodOutsidePosition then
				self:setState(enums.DragonState.MOVING_TO_OUTSIDE)
			else
				self:setState(enums.DragonState.MOVING_TO_IDLE)
			end

		end
	)
end

function ShadowDragon.notifyShouldShootFireballAtCrop(self: ShadowDragon, crop: any)
	--print("dragon should now shoot fireball at crop")

	local targetPosition = crop:getObj():GetPivot().Position

	local attributeStr = string.format("%s %.2f %.2f %.2f", self:getItemData().fireballPath, targetPosition.X, targetPosition.Y, targetPosition.Z)
	--print("full attribute is", attributeStr)
	self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, attributeStr)

	local cropItemId = crop:getItemId()

	local animationSec = Constants.FIREBALL_TRAVEL_SEC

	task.delay(animationSec,
		function()
			if not self.obj then
				-- we were already destroyed
				return
			end

			self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, nil)

			local crop = itemManager:getItemById(cropItemId) :: Types.Crop?
			if crop then
				if crop:getObj().Parent ~= workspace then
					return
				end

				local dragonPlayer = self:getPlayer()
				if not dragonPlayer then
					return
				end

				local cropPlayer = crop:getPlayer()
				if not cropPlayer then
					return
				end

				local primaryElement = self:getItemData().primaryElement
				local modification = Elements.getFireballModificationForPrimaryElement(primaryElement)

				--print("telling crop fireball hit")
				utils.pulseAttribute(crop:getObj(), Attributes.ANIMATION_FIREBALL_HIT, string.format("%i", primaryElement))

				if crop:doesHaveModification(modification) then
					return
				end

				-- yay, actually add modification

				crop:addModification(modification)

				local color = utils.get2DColorForPrimaryElement(primaryElement)
				local colorStr: string = color:ToHex()
				local modificationName: string = tostring(enums.getPublicName(enums.Modifications, modification))

				local cropPlayerName: string = cropPlayer.Name
				local cropDisplayName: string = crop:getDisplayName()

				gameController:sendSystemMessageToPlayer(dragonPlayer, string.format("You added a <font color=\"#%s\">%s</font> modifier to %s's %s", colorStr, modificationName, cropPlayerName, cropDisplayName))

				gameController:sendSystemMessageToPlayer(cropPlayer, string.format("%s added a <font color=\"#%s\">%s</font> modifier to your %s", dragonPlayer.Name, colorStr, modificationName, cropDisplayName))

				playerAttributesManager:addWholeNumber(dragonPlayer, Elements.getApplyFlameKeyForPrimaryElement(primaryElement), 1)

				analyticsManager:logEvent(dragonPlayer, analyticsManager.Events.ApplyFlame,
					{
						objectName = self:getItemName(),
						cropObjectName = crop:getItemName(),
					}
				)

			end

			if self.isRiding then
				self:setState(enums.DragonState.IDLE)
			elseif self.lastKnownGoodOutsidePosition then
				self:setState(enums.DragonState.MOVING_TO_OUTSIDE)
			else
				self:setState(enums.DragonState.MOVING_TO_IDLE)
			end

		end
	)
end

function ShadowDragon.notifyShouldShootFireballAtCritter(self: ShadowDragon, critter: any)
	--print("dragon should now shoot fireball at critter")

	local animationSec = Constants.FIREBALL_TRAVEL_SEC

	local targetPosition = critter:getFuturePosition(animationSec)

	local attributeStr = string.format("%s %.2f %.2f %.2f", self:getItemData().fireballPath, targetPosition.X, targetPosition.Y, targetPosition.Z)
	--print("full attribute is", attributeStr)
	self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, attributeStr)

	local critterObjectId = critter:getObjectId()

	task.delay(animationSec,
		function()
			if not self.state then
				-- we were already destroyed
				return
			end
			self:getObj():SetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL, nil)

			local critter = islandManager:getCritterByObjectId(critterObjectId)
			if critter then
				local player = self:getPlayer()
				if not player then
					return
				end

				-- yay, actually did it it!
				critter:notifyShotByDragon(self)
			end

			if self.isRiding then
				self:setState(enums.DragonState.IDLE)
			elseif self.lastKnownGoodOutsidePosition then
				self:setState(enums.DragonState.MOVING_TO_OUTSIDE)
			else
				self:setState(enums.DragonState.MOVING_TO_IDLE)
			end

		end
	)
end

function ShadowDragon.notifyPlayerReturnedToPlot(self: ShadowDragon)
	if self.state ~= enums.DragonState.OUTSIDE and self.state ~= enums.DragonState.MOVING_TO_OUTSIDE then
		return
	end

	--print("dragon was outside, now returning to plot")
	self:setState(enums.DragonState.MOVING_TO_IDLE)
end

function ShadowDragon.setServerControlMotion(self: ShadowDragon)
	--print("shadow dragon", self:getItemName(), "now under server control")
	self:getObj():SetAttribute(Attributes.CLIENT_CONTROL, nil)
end

function ShadowDragon.setClientControlMotion(self: ShadowDragon)
	--print("shadow dragon", self:getItemName(), "now under client control")

	-- ok, so... these attribute changes come down from the server in a separate "channel" compared to physics/position updates,
	-- so there might be more position updates that the server already applied that we haven't received yet

	local obj = self:getObj()

	-- so we send our current position when client control takes over, so the client can move to this spot
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = obj:GetPivot():GetComponents()
	obj:SetAttribute(Attributes.CLIENT_CONTROL, string.format("%.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f", x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22))
end

function ShadowDragon.getMovingToEatItemId(self: ShadowDragon): any
	if self.state ~= enums.DragonState.MOVING_TO_EAT then
		return nil
	end

	return self.movingToEat.cropItemId
end

function ShadowDragon.getEatingItemId(self: ShadowDragon): any
	if self.state ~= enums.DragonState.EATING then
		return nil
	end

	return self.eating.eatingItemId
end

function ShadowDragon.getMovingToOpenItemId(self: ShadowDragon): any
	if self.state ~= enums.DragonState.MOVING_TO_OPEN then
		return nil
	end

	return self.movingToOpen.crystalItemId
end

function ShadowDragon.notifyShouldMoveToIdle(self: ShadowDragon)
	self:setState(enums.DragonState.MOVING_TO_IDLE)
end

function ShadowDragon.notifyShouldMoveToIdleAtCurrentLocation(self: ShadowDragon)
	self:setState(enums.DragonState.MOVING_TO_IDLE, self:getPart().Position)
end

-- larger first number means flap faster; larger second number means bigger flap
function ShadowDragon.setFlapData(self: ShadowDragon, periodDivisor: number, amplitudeMultiplier: number)
	local itemData = self:getItemData()

	local period = itemData.movement.baseFlapPeriod / periodDivisor
	local amplitude = itemData.movement.baseFlapAmplitude * amplitudeMultiplier

	self:getObj():SetAttribute(Attributes.DRAGON_FLAP_DATA, string.format("%.1f %.1f", period, amplitude))
end

function ShadowDragon.canBePickedUp(self: ShadowDragon): boolean
	if self.state == enums.DragonState.MERGING then
		return false
	end

	-- other cases handled by mixin
	return true
end

function ShadowDragon.isInFreeFlyZone(self: ShadowDragon): boolean
	local player = self:getPlayer()
	if not player or not player.Character or not (player.Character :: any).HumanoidRootPart then
		return false
	end
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return false
	end

	local position

	local obj = self:getObj()
	if not obj then
		return false
	end

	if obj.Parent == workspace or not player then
		position = self:getPart().Position
	else
		position = (player.Character :: any).HumanoidRootPart:GetPivot().Position
	end

	return gameController:isLocationInFreeFlyZone(position) or playerData:isLocationInPlotOrUnlockedExpansions(position)

end

function ShadowDragon.getMaxStamina(self: ShadowDragon): number
	if self.overrideMaxStamina then
		return self.overrideMaxStamina
	end

	local itemData = self:getItemData()
	if itemData.mixins.ride then
		return itemData.mixins.ride.maxFlightDuration
	end
	return 0
end

function ShadowDragon.notifyRideBegin(self: ShadowDragon)
	--print("ride begin", self, self:getPlayer())

	self:setFlapData(3, 1)

	self.wasRidingMaxDuration = false
	self.ridingBeginTime = workspace:GetServerTimeNow()
	self.lastRidingUpdateTime = self.ridingBeginTime

	if self.state == enums.DragonState.MOVING_TO_IDLE then
		self:setState(enums.DragonState.IDLE)
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		self:setState(enums.DragonState.IDLE)
	end

	if self.stableSlotIndex ~= nil then
		self:setClientControlMotion()
	end

	self:getObj():SetAttribute(Attributes.DRAGON_RIDER, true)

	self.isRiding = true
end

function ShadowDragon.notifyRideEnd(self: ShadowDragon)
	--print("ride end", self, self:getPlayer())

	self:getObj():SetAttribute(Attributes.DRAGON_RIDER, false)

	if not self.isRiding then
		warn("notifyRideEnd when not riding")
		return
	end

	local periodDivisor, amplitudeMultiplier = self:getFlapDataForCurrentState()
	self:setFlapData(periodDivisor, amplitudeMultiplier)

	self.isRiding = false

	local playerData = self:getPlayerData()

	if not self.wasRidingMaxDuration then
		--print("ride was less than max duration")
		if playerData:isLocationInPlotOrUnlockedExpansions(self.part.Position) then
			--print("player stopped riding their dragon over their own plot--leave dragon here")
			local currentPosition = self:getObj():GetPivot().Position
			self.lastKnownGoodIdleLocation = Vector3.new(currentPosition.X, 0, currentPosition.Z)
		else
			--print("player stopped riding their dragon somewhere else around the world--move dragon to an idle spot")
			self.lastKnownGoodIdleLocation = nil
		end
	end

	local ridingBeginTime = self.ridingBeginTime
	-- ridingBeginTime is always set while riding; report a zero duration if it somehow is not
	local rideDuration = if ridingBeginTime then workspace:GetServerTimeNow() - ridingBeginTime else 0
	if self:getPlayer() then
		analyticsManager:logEvent(self:getPlayer(), analyticsManager.Events.RideDragon,
			{
				objectName = self:getItemName(),
				duration = rideDuration,
				primaryElement = enums.getPublicName(enums.PrimaryElements, self:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, self:getItemData().rarity),
			}
		)
	end

	self.ridingBeginTime = nil
	self.lastRidingUpdateTime = nil

	if self.stableSlotIndex ~= nil then
		-- fly back to the exact stable slot pose; notifyItemMoverDone finishes it on arrival
		local slotCFrame = stableManager:getStableSlotAnchorCFrame(self:getUserId(), self.stableSlotIndex)
		if slotCFrame then
			self:setState(enums.DragonState.MOVING_TO_IDLE, slotCFrame)
		else
			self:setState(enums.DragonState.IDLE)
		end
		return
	end

	if self:isInFreeFlyZone() or gameController:getPlayerData(self:getPlayer()):getIsInPlot() or self.stamina <= 0 then
		--print("end riding, moving dragon to idle", self:isInFreeFlyZone(), gameController:getPlayerData(self:getPlayer()):getIsInPlot(), self.stamina)
		if self.state == enums.DragonState.IDLE or self.state == enums.DragonState.OUTSIDE then
			self:setState(enums.DragonState.MOVING_TO_IDLE)
		else
			-- keep doing what we were doing
		end
	else
		--print("end riding, dragon staying outside", self)
		self.lastKnownGoodOutsidePosition = self:getObj():GetPivot().Position

		-- perhaps should go moving-to-outside and let it include a leveling step xxx
		self:setState(enums.DragonState.OUTSIDE)
	end

end

function ShadowDragon.notifyEndEating(self: ShadowDragon)
	if self:getObj().Parent == workspace and not self.isRiding then
 		if self.state ~= enums.DragonState.MOVING_TO_EAT then

			self:setState(enums.DragonState.MOVING_TO_IDLE)
		end
	else
		self:setState(enums.DragonState.IDLE)
	end
end

function ShadowDragon.notifyEndMovingToOpen(self: ShadowDragon)
	if self:getObj().Parent == workspace then
		self:setState(enums.DragonState.MOVING_TO_IDLE)
	else
		self:setState(enums.DragonState.IDLE)
	end
end
function ShadowDragon.notifyEndMovingToEat(self: ShadowDragon)
	if self:getObj().Parent == workspace then
		self:setState(enums.DragonState.MOVING_TO_IDLE)
	else
		self:setState(enums.DragonState.IDLE)
	end
end

function ShadowDragon.notifyEndOpening(self: ShadowDragon)
	if self.state ~= enums.DragonState.OPENING or not self.opening.crystalItemId then
		-- this can happen when we triggered
		return
	end

	if self.isRiding then
		self:setState(enums.DragonState.IDLE)
	elseif self:getObj().Parent == workspace then
		self:setState(enums.DragonState.MOVING_TO_IDLE)
	else
		self:setState(enums.DragonState.IDLE)
	end
end

function ShadowDragon.notifyShouldMoveToEat(self: ShadowDragon, crop: any)
	self:setState(enums.DragonState.MOVING_TO_EAT, crop)
end

function ShadowDragon.notifyShouldMoveToOpen(self: ShadowDragon, crystal: any)
	self:setState(enums.DragonState.MOVING_TO_OPEN, crystal)
end

function ShadowDragon.notifyShouldMoveToMine(self: ShadowDragon, node: any)
	self:setState(enums.DragonState.MOVING_TO_MINE, node)
end

function ShadowDragon.notifyShouldEatCrop(self: ShadowDragon, crop: any)
	self:setState(enums.DragonState.EATING, crop)
end

function ShadowDragon.notifyShouldOpenCrystal(self: ShadowDragon, crystal: any)
	self:setState(enums.DragonState.OPENING, crystal)
end

function ShadowDragon.notifyShouldChargeUp(self: ShadowDragon)
	self:getObj():SetAttribute(Attributes.ANIMATION_CHARGE_UP, "")
	task.wait(Constants.FIREBALL_CHARGE_SEC)
	self:getObj():SetAttribute(Attributes.ANIMATION_CHARGE_UP, nil)
end

function ShadowDragon.isClientControlling(self: ShadowDragon): boolean
	if self:getObj():GetAttribute(Attributes.CLIENT_CONTROL) then
		return true
	end

	return false
end

function ShadowDragon.canChargeUp(self: ShadowDragon): boolean
	return self:isClientControlling()
end

function ShadowDragon.trySetRidingItemCFrame(self: ShadowDragon, time: number, cframe: CFrame)
	if not self:getObj():GetAttribute(Attributes.CLIENT_CONTROL) then
		--print("shadow dragon ignoring riding item cframe, not under client control", self, time)
		return
	end

	local player = self:getPlayer()

	if not self.isRiding then
		--print("shadow dragon ignoring riding item cframe, not currently riding", player, self)
		return
	end

	if not self.lastRidingUpdateTime then
		warn("player is riding but have no last riding update time; not sure how this is possible", self)
		self.lastRidingUpdateTime = time
		return
	end


	if time < self.lastRidingUpdateTime then
		--print("throwing away older riding item cframe time", player, time, self.lastRidingUpdateTime)
		return
	end

	-- validate the position could legally be achieved without cheating

	local playerData = gameController:getPlayerData(player)
	local flyFastDuration = playerData:getPlayerVariable(Attributes.FLY_FAST_DURATION)

	--print("player can fly fast for", flyFastDuration)

	local durationSec = time - self.lastRidingUpdateTime

	self.lastRidingUpdateTime = time

	-- always allow first move onto the dragon; it's often a few studs
	-- both times are always set while riding
	if (self.lastRidingUpdateTime :: number) > (self.ridingBeginTime :: number) then

		-- perform security/teleportation checks

		-- letting fly fast duration potentially last an extra half second to make sure we don't calculate poorly across the transition;
		-- falsely accusing client of cheating would be very bad
		local isFlyingFast = (time - (self.ridingBeginTime :: number)) < (flyFastDuration + 0.5)
		--print("is flying fast?", isFlyingFast)

		local speedMultiplier
		if isFlyingFast then
			speedMultiplier = Constants.FLY_FAST_MULTIPLIER
		else
			speedMultiplier = 1
		end
		local maxLegalDistance = durationSec * Constants.BASE_RIDE_SPEED * speedMultiplier

		local prevPosition = self:getObj().Position
		local diff = cframe.Position - prevPosition
		local distanceXZ = utils.getMagnitudeXZ(diff)
		local distance = diff.Magnitude
		--print("time", durationSec, "distance", distance, "position", cframe.Position)

		if distance > maxLegalDistance * 5 then
			-- this still happens as of 2026-april-15
			print("player moved way too far on dragon", player, distance, maxLegalDistance, "in time", durationSec)

			-- tell client we rejected this
			RemoteEvents.NotifyTrySetRidingCFrameRejected:FireClient(player, self:getObj():GetPivot())

			return
		end

		-- give a few seconds grace before looking for minor speed cheating--as the player gets on dragon, things are messy and non-cheaters would trigger this
		if time - (self.ridingBeginTime :: number) > 3 then
			if distanceXZ > maxLegalDistance * 1.2 then
				-- maybe should count these, if player gets to some big number (100+?) in a ride, banish them?
				--warn("player moved a bit too far on dragon", player, distanceXZ, maxLegalDistance, speedMultiplier, "in time", durationSec)
			elseif distanceXZ > maxLegalDistance then
				--warn("player moved a smidge too far on dragon", player, distanceXZ, maxLegalDistance, "in time", durationSec)
			end
		end
	end

	self:getObj():PivotTo(cframe)
end

function ShadowDragon.isAvailableToEat(self: ShadowDragon): boolean
	-- small dragons can be held; in that state, they can't go eat
	if self:getObj().Parent ~= workspace then
		return false
	end

	return self.state == enums.DragonState.IDLE or self.state == enums.DragonState.MOVING_TO_IDLE or self.state == enums.DragonState.OUTSIDE or self.state == enums.DragonState.MOVING_TO_OUTSIDE
end

function ShadowDragon.isAvailableToOpen(self: ShadowDragon): boolean
	-- small dragons can be held; in that state, they can't go open
	if self:getObj().Parent ~= workspace then
		return false
	end

	return self.state == enums.DragonState.IDLE or self.state == enums.DragonState.MOVING_TO_IDLE or self.state == enums.DragonState.OUTSIDE or self.state == enums.DragonState.MOVING_TO_OUTSIDE
end

function ShadowDragon.isAvailableToMine(self: ShadowDragon): boolean
	-- small dragons can be held; in that state, they can't go mine
	if self:getObj().Parent ~= workspace then
		return false
	end

	if not self:getItemData().mixins.ride then
		return false
	end

	return self.state == enums.DragonState.IDLE or self.state == enums.DragonState.MOVING_TO_IDLE or self.state == enums.DragonState.OUTSIDE or self.state == enums.DragonState.MOVING_TO_OUTSIDE
end

function ShadowDragon.notifyUnequippableEquipped(self: ShadowDragon)
	--(self:getPlayer() :: any).Character.Humanoid:UnequipTools()

	--return gameController:isLocationInFreeFlyZone(self:getPart().Position)
	if not self:isInFreeFlyZone() then
		gameController:sendSystemMessageToPlayer(self:getPlayer(), "You cannot release a ridable dragon out here")
		return
	end

	if self:getCount() > 1 then
		--print("splitting off a dragon, tool and backpack should stay the same")
		local splitDragon = self:splitOffOne() :: ShadowDragon?
		if not splitDragon then
			warn("failed to split a dragon off the stack", self:getItemName())
			return
		end

		splitDragon:moveDragonFromBackpackToWorkspace();

		(self:getPlayer() :: any).Character.Humanoid:UnequipTools()
	else
		--print("putting self dragon out in the world and killing the tool")
		local tool = self:getObj().Parent

		-- ideally this would go in Item somewhere
		utils.destroyDescendantsByName(tool, Constants.ITEM_TOOL_WELD_NAME)

		self:moveDragonFromBackpackToWorkspace()

		tool:Destroy()
	end
end

function ShadowDragon.moveDragonFromBackpackToWorkspace(self: ShadowDragon)
	--print("releasing unequippable dragon")

	local playerCFrame = (self:getPlayer() :: any).Character.HumanoidRootPart:GetPivot()
	local dragonCFrame = playerCFrame + Vector3.new(0, 6, 0)
	--print("player at", playerCFrame.Position, "dragon going to", dragonCFrame.Position)

	-- to mimic the behavior of an item getting placed into workspace in the normal activation flow (from a tool),
	-- we set parent to nil, and _then_ workspace
	-- this is important because tags will all trigger events about being added to the instance
	self:getObj().Parent = nil
	self:getObj():PivotTo(dragonCFrame)
	-- let the notification of parenting change to nil happen
	task.wait()
	self:moveFromPlayerToWorkspace()

	local playerData = self:getPlayerData()
	if playerData:isLocationInPlotOrUnlockedExpansions(self.part.Position) then
		-- when dragon was moved to workspace in IDLE state, it was already set to settling
	else
		self:notifyShouldMoveToIdle()
	end
end

function ShadowDragon.setPreventSettling(self: ShadowDragon)
	self.doPreventSettling = true
end

function ShadowDragon.getToolName(self: ShadowDragon): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

function ShadowDragon.calculateGoodSaveCFrame(self: ShadowDragon): CFrame
	local location
	if self.lastKnownGoodIdleLocation then
		location = self.lastKnownGoodIdleLocation
	else
		location = self:calculateGoodIdleLocation()
	end
	local destY = self:calculateIdleHeightAtLocation(location)
	local destPosition = Vector3.new(location.X, destY, location.Z)

	local cframe = CFrame.new(destPosition) * CFrame.fromEulerAnglesXYZ(0, self.random:NextNumber(0, math.pi * 2), 0)

	return cframe
end

function ShadowDragon.getFlapDataForCurrentState(self: ShadowDragon): (number, number)
	if self.state == enums.DragonState.IDLE then
		-- default
	elseif self.state == enums.DragonState.MOVING_TO_EAT then
		return 1.5, 1.5
	elseif self.state == enums.DragonState.EATING then
		return 0.5, 0.5
	elseif self.state == enums.DragonState.MOVING_TO_IDLE then
		return 1.2, 1.2
	elseif self.state == enums.DragonState.MERGING then
		-- default
	elseif self.state == enums.DragonState.MOVING_TO_OPEN then
		return 1.5, 1.5
		-- default
	elseif self.state == enums.DragonState.OPENING then
		return 0.5, 0.5
	elseif self.state == enums.DragonState.MOVING_TO_MINE then
		return 1.5, 1.5
	elseif self.state == enums.DragonState.OUTSIDE then
		-- default
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		return 1.2, 1.2
	elseif self.state == enums.DragonState.SETTLING then
		return 1.5, 1.5
	else
		warn("end unknown dragon state", self, self.state)
	end

	return 1, 1
end

function ShadowDragon.getWorldSaveCFrame(self: ShadowDragon): CFrame
	if self.state == enums.DragonState.IDLE then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.MOVING_TO_EAT then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.EATING then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.MOVING_TO_IDLE then
		return self.movingToIdle.destCFrame
	elseif self.state == enums.DragonState.MERGING then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.MOVING_TO_OPEN then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.OPENING then
		-- at some point if we have the dragon moving, we may want to change this
		return super.getWorldSaveCFrame(self)
	elseif self.state == enums.DragonState.MOVING_TO_MINE then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.OUTSIDE then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		return self:calculateGoodSaveCFrame()
	elseif self.state == enums.DragonState.SETTLING then
		return self:calculateGoodSaveCFrame()
	else
		warn("end unknown dragon state", self, self.state)
	end

	return super.getWorldSaveCFrame(self)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function ShadowDragon.getSaveData(self: ShadowDragon, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.state = self.state
	retval.stableSlotIndex = self.stableSlotIndex
	if self.state == enums.DragonState.OPENING then
		--print("saving data remapping an item id for dragon target", self.opening.crystalItemId, itemIdMap[self.opening.crystalItemId])
		retval.opening = {}
		retval.opening.crystalItemId = itemIdMap[self.opening.crystalItemId]
		if retval.opening.crystalItemId == nil then
			warn("saving dragon in state opening a crystal did not have an item id mapping for crystal")
			retval.state = enums.DragonState.IDLE
		end
	end

	return retval
end

--shouldn't be called if everything is working, but it's a good safety mechanism
function ShadowDragon.getSafeCFrameOnLoad(self: ShadowDragon, cframe: CFrame): CFrame
	local location = self:calculateGoodIdleLocation()
	local destY = self:calculateIdleHeightAtLocation(location)
	local position = Vector3.new(location.X, destY, location.Z)

	return cframe.Rotation + position
end

function ShadowDragon.loadSaveData(self: ShadowDragon, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	self.stableSlotIndex = itemSaveData.stableSlotIndex

	-- saved in this state: itemSaveData.state but we put every dragon in idle to start with; they were saved with idle locations

	-- processLoadComplete will handle OPENING state dragons which need to resume their OPENING on load
	-- notifyLoadComplete re-parks a dragon that was saved in a stable slot
end

function ShadowDragon.notifyLoadComplete(self: ShadowDragon, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	if itemSaveData.state == enums.DragonState.OPENING then
		-- we do this here as we have a reference to another item that needs to exist and be in the workspace when we initialize OPENING state

		--print("handled data remapping an item id for dragon target, should be", itemSaveData.opening.crystalItemId, itemIdMap[itemSaveData.opening.crystalItemId])
		local crystalItemId = itemIdMap[itemSaveData.opening.crystalItemId]
		local crystal
		if crystalItemId then
			crystal = itemManager:getItemById(crystalItemId)
		end
		if crystal then
			self:setState(enums.DragonState.OPENING, crystal)
		else
			print("dragon loading, handled data remapping an item id for dragon target, should be", itemSaveData.opening.crystalItemId, itemIdMap[itemSaveData.opening.crystalItemId])
			print("but crystal is nil")
		end

	else
		--print("loading dragon is already idle, leaving it alone", enums.getName(enums.DragonState, self.state))
	end

	if self.stableSlotIndex ~= nil then
		stableManager:equipDragonOnLoad(self)
	end
end

function ShadowDragon.setOverrideMaxStamina(self: ShadowDragon, stamina: number?)
	self.overrideMaxStamina = stamina
	self.stamina = stamina

	self:getObj():SetAttribute(Attributes.DRAGON_STAMINA, self.stamina)
end

function ShadowDragon.tryStepUpdateStaminaAndFreeFlyZone(self: ShadowDragon)
	local itemData = self:getItemData()
	if not itemData.mixins.ride then
		return
	end

	local isInFreeFlyZone = self:isInFreeFlyZone()

	self:getObj():SetAttribute(Attributes.DRAGON_IS_IN_FREE_FLY_ZONE, isInFreeFlyZone)

	local maxStamina = self:getMaxStamina()

	local nextStamina = self.stamina
	if isInFreeFlyZone then
		nextStamina = math.min(maxStamina, self.stamina + 1)
	else
		if self.isRiding then
			-- lose stamina if outside free fly zone
			nextStamina = math.max(0, self.stamina - 1)
		end
	end

	if nextStamina == self.stamina then
		return
	end

	-- update client and state based on changed stamina
	self.stamina = nextStamina

	self:getObj():SetAttribute(Attributes.DRAGON_STAMINA, self.stamina)

	if self.isRiding and self.stamina == 0 then
		local player = self:getPlayer()
		if not player then
			return
		end

		gameController:sendSystemMessageToPlayer(player, "Your dragon is too tired to continue carrying you")

		self.wasRidingMaxDuration = true

		rideMixin:stopPlayerRiding(player)
	end

	self:updateDataDump()

end

function ShadowDragon.endState(self: ShadowDragon)
	--print("shadow dragon ending state", enums.getName(enums.DragonState, self.state))

	if self.state == enums.DragonState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.DragonState.MOVING_TO_EAT then
		self:cleanupMovingToEat()
	elseif self.state == enums.DragonState.EATING then
		self:cleanupEating()
	elseif self.state == enums.DragonState.MOVING_TO_IDLE then
		self:cleanupMovingToIdle()
	elseif self.state == enums.DragonState.MERGING then
		-- pass
	elseif self.state == enums.DragonState.MOVING_TO_OPEN then
		self:cleanupMovingToOpen()
	elseif self.state == enums.DragonState.OPENING then
		self:cleanupOpening()
	elseif self.state == enums.DragonState.MOVING_TO_MINE then
		self:cleanupMovingToMine()
	elseif self.state == enums.DragonState.OUTSIDE then
		self:cleanupOutside()
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		self:cleanupMovingToOutside()
	elseif self.state == enums.DragonState.SETTLING then
		self:cleanupSettling()
	else
		warn("end unknown dragon state", self, self.state)
	end

	self.state = nil
end

function ShadowDragon.beginState(self: ShadowDragon, state: number?, data: any)
	--print("shadow dragon beginning state", self:getItemName(), enums.getName(enums.DragonState, state))

	self.state = state

	if self.state == enums.DragonState.IDLE then
		self:beginIdle(data)
	elseif self.state == enums.DragonState.MOVING_TO_EAT then
		self:beginMovingToEat(data)
	elseif self.state == enums.DragonState.EATING then
		self:beginEating(data)
	elseif self.state == enums.DragonState.MOVING_TO_IDLE then
		if typeof(data) == "CFrame" then
			self:beginMovingToIdleWithCFrame(data)
		elseif data then
			--print("moving to idle with location", data)
			self:beginMovingToIdleWithLocation(data)
		else
			self:beginMovingToIdle()
		end
	elseif self.state == enums.DragonState.MERGING then
		-- pass
	elseif self.state == enums.DragonState.MOVING_TO_OPEN then
		self:beginMovingToOpen(data)
	elseif self.state == enums.DragonState.OPENING then
		self:beginOpening(data)
	elseif self.state == enums.DragonState.MOVING_TO_MINE then
		self:beginMovingToMine(data)
	elseif self.state == enums.DragonState.OUTSIDE then
		self:beginOutside(data)
	elseif self.state == enums.DragonState.MOVING_TO_OUTSIDE then
		self:beginMovingToOutside(data)
	elseif self.state == enums.DragonState.SETTLING then
		self:beginSettling()
	else
		warn("begin unknown dragon state", self, state)
	end

	self:updateDataDump()
end

function ShadowDragon.setState(self: ShadowDragon, state: number?, data: any)
	self:endState()

	self:beginState(state, data)

	local periodDivisor, amplitudeMultiplier = self:getFlapDataForCurrentState()
	self:setFlapData(periodDivisor, amplitudeMultiplier)
end

function ShadowDragon.destroy(self: ShadowDragon)
	self:endState()

	self.state = nil

	if self.isRiding then
		local player = self:getPlayer()
		if player then
			local playerData = gameController:getPlayerData(player)
			if playerData then
				gameController:getPlayerData(player):setRiding(nil, nil)
			end
		end

	end

	super.destroy(self)
end

function ShadowDragon.recomputePower(self: ShadowDragon)
	local itemData = self:getItemData()

	local tierIndex = itemData.rarity - enums.Rarity.COMMON
	local rarityBase = DragonPower.rarityBase(dragonPowerValues.rarityStep, tierIndex)
	local base = DragonPower.basePower(rarityBase, dragonPowerValues.levelMult, itemData.level)

	local mutationBonus = MItem.getMutationBonus(self.mutation)

	-- weather traits and mastery aren't in the game yet
	local traitBonus = 0
	local masteryMult = DragonPower.masteryMult(dragonPowerValues.masteryPerLevel, 0)

	self.power = DragonPower.compute(base, mutationBonus, traitBonus, masteryMult)

	self:getObj():SetAttribute(Attributes.DRAGON_POWER, self.power)
end

function ShadowDragon.getPower(self: ShadowDragon): number
	if self.power == nil then
		self:recomputePower()
	end

	return self.power :: number
end

function ShadowDragon.processMutationChanged(self: ShadowDragon)
	super.processMutationChanged(self)

	self:recomputePower()
end

function ShadowDragon.getStableSlotIndex(self: ShadowDragon): number?
	return self.stableSlotIndex
end

function ShadowDragon.setStableSlotIndex(self: ShadowDragon, stableSlotIndex: number?)
	self.stableSlotIndex = stableSlotIndex
end

-- park the dragon at its stable slot anchor: prevent settling, keep it IDLE but server-held and
-- static, never move it until unequipped
function ShadowDragon.parkInStableSlot(self: ShadowDragon, slotCFrame: CFrame)
	self:setPreventSettling()

	if self:getObj().Parent ~= workspace then
		-- from a backpack tool (or a fresh split clone with no parent): drop the hold weld,
		-- do the parent nil -> workspace dance, kill the empty tool
		local tool = self:getObj().Parent
		if tool then
			utils.destroyDescendantsByName(tool, Constants.ITEM_TOOL_WELD_NAME)
		end

		self:getObj().Parent = nil
		self:getObj():PivotTo(slotCFrame)
		task.wait()
		self:moveFromPlayerToWorkspace()

		if tool and tool:IsA("Tool") then
			tool:Destroy()
		end

		-- re-assert once the client ghost-follow handler is live
		task.wait()
		self:getObj():PivotTo(slotCFrame)
	else
		-- in the world: end current state, hand motion to the server so the ghost tracks the shadow, then move
		self:endState()
		self:setServerControlMotion()
		task.wait()
		self:getObj():PivotTo(slotCFrame)
		self:beginState(enums.DragonState.IDLE)
		local periodDivisor, amplitudeMultiplier = self:getFlapDataForCurrentState()
		self:setFlapData(periodDivisor, amplitudeMultiplier)
	end
end

function ShadowDragon.returnToBackpackFromStableSlot(self: ShadowDragon)
	-- Item.equip puts the model back into a backpack tool; the parent change fires
	-- notifyParentPlayer which resets the dragon to a normal held IDLE state
	self:equip()
end

function ShadowDragon.init(self: ShadowDragon)
	local itemData = self:getItemData()

	self.random = Random.new()

	self.stamina = self:getMaxStamina()
	self.overrideMaxStamina = nil

	self.state = enums.DragonState.IDLE

	self.movingToEat = {}
	self.eating = {}
	self.movingToIdle = {}
	self.movingToOpen = {}
	self.opening = {}
	self.movingToMine = {}
	self.movingToOutside = {}
	self.settling = {}

	self.isRiding = false
	self.ridingBeginTime = nil
	self.lastRidingUpdateTime = nil
	self.wasRidingMaxDuration = false

	self.lastKnownGoodIdleLocation = nil
	self.lastKnownGoodOutsidePosition = nil

	self.stableSlotIndex = nil

	local periodDivisor, amplitudeMultiplier = self:getFlapDataForCurrentState()
	self:setFlapData(periodDivisor, amplitudeMultiplier)

	self:getObj():SetAttribute(Attributes.DRAGON_STAMINA, self.stamina)

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, itemData.primaryElement)

	self:getObj():SetAttribute(Attributes.USER_ID, self:getUserId())
	self:getObj():SetAttribute(Attributes.CASTER_PATH, itemData.casterPath)

	collectionService:AddTag(self:getObj(), Tags.SHADOW)
	collectionService:AddTag(self:getObj(), Tags.SHADOW_DRAGON)

	self:recomputePower()
end

function ShadowDragon.notifyNewClone(self: ShadowDragon)
	--print("shadow dragon notify new clone")

	super.notifyNewClone(self)

	self:init()
end

function ShadowDragon.new(itemId: number, itemName: string, userId: number): ShadowDragon
	local self = (setmetatable(super.new(itemId, itemName, userId), ShadowDragon) :: any) :: ShadowDragon

	self:init()

	return self
end

function ShadowDragon.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return ShadowDragon
