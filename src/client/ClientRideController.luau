--!strict

local runService = game:GetService("RunService")

local ClientRideController = {}
ClientRideController.__index = ClientRideController

local collectionService = game:GetService("CollectionService")
local userInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
local RidingDragonAudioParent = Effects:WaitForChild("RidingDragonAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local Types = require("./Types")
local clientDragonManager: Types.ClientDragonManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientPlayerAnimationManager: Types.ClientPlayerAnimationManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientPlayerVariables = require("./ClientPlayerVariables")
local Satchel = require("./Satchel")
local screenGuiManager = require("./ScreenGuiManager")
local TargetBase = require("./TargetBase")
local virtualTouchJoystick = require("./VirtualTouchJoystick")


local FORWARD_KEY = Enum.KeyCode.W
local LEFT_KEY = Enum.KeyCode.A
local RIGHT_KEY = Enum.KeyCode.D
local BACKWARD_KEY = Enum.KeyCode.S

local RIDE_BEGIN_COOLDOWN_SEC = 2

-- rotation in radians per second
local ROTATION_SPEED = 1.5

local INTERPOLATE_MATCH_CAMERA_SEC = 3

local LOW_STAMINA_SEC = 8
local LOW_STAMINA_BLINK_TRANSPARENCY = 0.5

local blinkRate = {
	{
		minRemainingSec = 4,
		blinkDurationSec = 1,
	},
	{
		minRemainingSec = 2,
		blinkDurationSec = 0.25,
	},
	{
		minRemainingSec = 1,
		blinkDurationSec = 0.125,
	},
	{
		minRemainingSec = 0,
		blinkDurationSec = 0.0625,
	},
}

local TARGET_TYPE_NODE = 1
local TARGET_TYPE_CROP = 2
local TARGET_TYPE_CRITTER = 3

local player = game:GetService("Players").LocalPlayer :: Player

type ClientRideControllerFields = {
	alignOrientationConstraint: any,
	attributeChangedConnect: any,
	audioMountDragon: any,
	audioRideDragon: any,
	baseWalkSpeed: any,
	blinkState: any,
	caster: any,
	casterDestroyConnect: any,
	currentBlinkDurationSec: any,
	drivePart: any,
	event: BindableEvent,
	fastDuration: any,
	fireballAngle: any,
	fireballRange: any,
	flightDurationSec: number,
	indicatorMap: { [any]: any },
	inputBeganConnect: any,
	inputChangedConnect: any,
	inputEndedConnect: any,
	isBlinking: boolean,
	isFlyingFast: any,
	isShootingFireball: boolean,
	isStaminaDecreasing: boolean,
	lastSendServer: any,
	latestRideStateChangeTime: any,
	linearVelocityConstraint: any,
	modificationsConnect: any,
	moveVector: any,
	mutationConnect: any,
	nextBlinkDurationSec: any,
	playerSeatLocationWeld: any,
	prevStamina: any,
	progressBlinkDurationSec: any,
	prompt: any,
	ridingItemId: any,
	riseSpeed: any,
	runConnect: any,
	shadow: any,
	staminaHighlight: any,
	sweatInst: any,
	targetBase: any,
	targetConnections: { [any]: any },
	targetHighlight: any,
	targetObjectId: any,
}

export type ClientRideController = typeof(setmetatable({} :: ClientRideControllerFields, ClientRideController))

function ClientRideController.updateStaminaHighlight(self: ClientRideController, deltaTime: any)
	if not self.staminaHighlight then
		return
	end

	if not self.isBlinking then
		self.staminaHighlight.FillTransparency = 1
		screenGuiManager:setStaminaDisplayBlinkState(false)
		return
	end

	-- as of 2026-august-12 this reads currentBlinkDurationSec; it previously read a
	-- misspelled currentblinkDurationSec (always nil), so the permanently-on special case
	-- could never trigger
	if self.currentBlinkDurationSec == 0 then
		-- special case meaning permanently on
		self.blinkState = true
	else
		self.progressBlinkDurationSec += deltaTime
		if self.progressBlinkDurationSec > self.currentBlinkDurationSec then
			--print("toggling, for duration", self.nextBlinkDurationSec)
			self.progressBlinkDurationSec = self.progressBlinkDurationSec % self.currentBlinkDurationSec
			self.currentBlinkDurationSec = self.nextBlinkDurationSec
			self.blinkState = not self.blinkState
		end
	end

	if self.blinkState then
		self.staminaHighlight.FillTransparency = LOW_STAMINA_BLINK_TRANSPARENCY
	else
		self.staminaHighlight.FillTransparency = 1
	end

	screenGuiManager:setStaminaDisplayBlinkState(self.blinkState)
end

function ClientRideController.updateStamina(self: ClientRideController)
	local dragonPart = self.caster.PrimaryPart

	local stamina = self.shadow:GetAttribute(Attributes.DRAGON_STAMINA)

	if stamina < self.prevStamina then
		self.isStaminaDecreasing = true
	end
	if stamina > self.prevStamina then
		self.isStaminaDecreasing = false
	end

	if stamina ~= self.prevStamina then
		screenGuiManager:setStaminaDisplay(stamina)
	end

	local isLowStamina = stamina <= LOW_STAMINA_SEC
	--print("stamina is", stamina, isLowStamina)

	if isLowStamina and self.isStaminaDecreasing then
		if not self.isBlinking then
			--print("starting to blinking")
			self.isBlinking = true
			self.blinkState = true
			self.currentBlinkDurationSec = blinkRate[1].blinkDurationSec
			self.progressBlinkDurationSec = 0
		end
		for i = 1, #blinkRate do
			self.nextBlinkDurationSec = blinkRate[i].blinkDurationSec
			if stamina > blinkRate[i].minRemainingSec then
				break
			end
		end
		--print("next duration is", self.nextBlinkDurationSec)

		-- ensure we have sweat
		if not self.sweatInst then
			local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
			local SweatPart = ParticleEffects:WaitForChild("DragonSweat")
			local Emitter = SweatPart:WaitForChild("Sweat")

			local sweat = Emitter:Clone()
			sweat.Parent = dragonPart

			self.sweatInst = sweat
		end
	else
		self.isBlinking = false
		-- ensure we do not have sweat
		if self.sweatInst then
			self.sweatInst:Destroy()
			self.sweatInst = nil
		end
	end

	self.prevStamina = stamina
end


function ClientRideController.beginListenInputs(self: ClientRideController)
	self.moveVector = Vector2.zero

	-- To detect when it starts being moved
	self.inputBeganConnect = userInputService.InputBegan:Connect(
		function(input, gameProcessed)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				--print("Left Stick Started Moving!")
			end
		end
	)

	self.inputChangedConnect = userInputService.InputChanged:Connect(
		function(input, gameProcessed)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local thumbstickVector = input.Position
				--print("Left Stick Position: X:", thumbstickVector.X, "Y:", thumbstickVector.Y)
				self.moveVector = thumbstickVector
			end
		end
	)

	-- To detect when it stops (returns to center)
	self.inputEndedConnect = userInputService.InputEnded:Connect(
		function(input, gameProcessed)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				--print("Left Stick Released (Returned to center)!")
				self.moveVector = Vector2.zero
			end
		end
	)
end

function ClientRideController.cleanupListenInputs(self: ClientRideController)
	if self.inputChangedConnect then
		self.inputChangedConnect:Disconnect()
		self.inputChangedConnect = nil
	end

	if self.inputBeganConnect then
		self.inputBeganConnect:Disconnect()
		self.inputBeganConnect = nil
	end

	if self.inputEndedConnect then
		self.inputEndedConnect:Disconnect()
		self.inputEndedConnect = nil
	end

end

local THUMBSTICK_DEAD_ZONE = 0.1

function ClientRideController.pollInput(self: ClientRideController)
	local rotationFrac = 0
	local moveFrac = 0

	local virtualJoystickVector = virtualTouchJoystick:getVirtualJoystickVector()
	rotationFrac = virtualJoystickVector.X
	moveFrac = virtualJoystickVector.Y

	if math.abs(self.moveVector.X) > THUMBSTICK_DEAD_ZONE then
		rotationFrac = self.moveVector.X
	end

	if math.abs(self.moveVector.Y) > THUMBSTICK_DEAD_ZONE then
		rotationFrac = self.moveVector.Y
	end

	if userInputService:IsKeyDown(LEFT_KEY) then
		rotationFrac -= 1
	end
	if userInputService:IsKeyDown(RIGHT_KEY) then
		rotationFrac += 1
	end

	if userInputService:IsKeyDown(FORWARD_KEY) then
		moveFrac += 1
	end
	if userInputService:IsKeyDown(BACKWARD_KEY) then
		moveFrac -= 1
	end

	return rotationFrac, moveFrac
end

-- this sends a lot of data to the server (which then goes to other users)
-- optimizing this in the case of small movements or small rotations could save a bunch of bandwidth
function ClientRideController.sendServerRidingItemCFrame(self: ClientRideController)
	--print("client control, telling server dragon is at", self.caster:GetPivot().Position)

	local now = workspace:GetServerTimeNow()
	local lastSendPlayerTime = now
	local dragonCFrame = self.caster:GetPivot()
	local playerRelativeToDragonCFrame = dragonCFrame:Inverse() * (player.Character :: any).HumanoidRootPart:GetPivot()

	if self.lastSendServer then
		if now - self.lastSendServer.time < 0.03 then
			return
		end

		local distance = (dragonCFrame.Position - self.lastSendServer.dragonCFrame.Position).Magnitude
		local angle = math.acos(dragonCFrame.LookVector:Dot(self.lastSendServer.dragonCFrame.LookVector))
		if distance < 0.01 and angle < 0.01 then
			return
		end

		if lastSendPlayerTime - self.lastSendServer.lastSendPlayerTime < 1 then
			-- don't bother sending these updates often; they barely ever change
			-- maybe should do same test as above instead
			playerRelativeToDragonCFrame = nil
			lastSendPlayerTime = self.lastSendServer.lastSendPlayerTime
		end

	end

	RemoteEvents.TrySetRidingItemCFrame:FireServer(self.ridingItemId, workspace:GetServerTimeNow(), dragonCFrame, playerRelativeToDragonCFrame)

	self.lastSendServer = {
		time = now,
		lastSendPlayerTime = lastSendPlayerTime,
		dragonCFrame = dragonCFrame,
		playerRelativeToDragonCFrame = playerRelativeToDragonCFrame,
	}

end

-- progress towards avoiding land, but it's pretty jittery--would need to add some sort of smoothing
--[[
-- up, down, left, right
local checkRotations = {
	CFrame.Angles(math.rad(-45), 0, 0),
	CFrame.Angles(math.rad(45), 0, 0),
	CFrame.Angles(0, math.rad(45), 0),
	CFrame.Angles(0, math.rad(-45), 0),
}
function ClientRideController.adjustCFrameAwayFromLand(self: ClientRideController, baseCFrame: any, moveFrac: any)
	-- look forward and in a few directions

	local direction = baseCFrame.LookVector
	if moveFrac < 0 then
		direction *= -1
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {workspace.Level}
	local raycastResult = workspace:Raycast(baseCFrame.Position, direction * 30, raycastParams)
	if not raycastResult then
		--print("all clear")
		return 1, baseCFrame
	end

	-- look in a few other directions, see which is most clear, and go that way
	-- if nothing clear, slow down
	print("something ahead")
	local bestIndex = nil
	local bestDistance = math.huge
	for i, rotation in checkRotations do
		local cframe = baseCFrame * rotation
		local checkDirection = cframe.LookVector
		if moveFrac < 0 then
			direction *= -1
		end

		local raycastResult = workspace:Raycast(baseCFrame.Position, checkDirection * 30, raycastParams)
		--print("direction", i, "result?", raycastResult ~= nil, raycastResult == nil and "huge" or raycastResult.Distance)
		if not raycastResult then
			-- great direction to go, nothing there
			bestIndex = i
			continue
		end
		if raycastResult.Distance < 3 then
			-- horrible
			continue
		end
		-- something coming up, but not right there
		if not bestIndex then
			bestIndex = i
			bestDistance = raycastResult.Distance
			continue
		end
		if raycastResult.Distance < bestDistance then
			bestIndex = i
			bestDistance = raycastResult.Distance
			continue
		end
	end

	if not bestIndex then
		print("saying don't move at all")
		return 0, baseCFrame
	end

	print("saying move full speed in direction", bestIndex)
	return 1, baseCFrame * checkRotations[bestIndex]
end
]]

function ClientRideController.updateMovement(self: ClientRideController, deltaTime: any)
	self.flightDurationSec += deltaTime

	local isFlyingFast = self.flightDurationSec < self.fastDuration

	if self.isFlyingFast and not isFlyingFast then
		clientDragonManager:disableTrail(self.ridingItemId)
	end

	self.isFlyingFast = isFlyingFast

	if (player.Character :: any).HumanoidRootPart.Anchored then
		-- don't try to control anything if we're being held for some reason, such as a merge happening
		return
	end

	if not self.shadow:GetAttribute(Attributes.CLIENT_CONTROL) then
		return
	end

	local rotationFrac, moveFrac = self:pollInput()

	self.drivePart.AssemblyAngularVelocity = Vector3.new(0, -rotationFrac, 0) * ROTATION_SPEED

	local cameraCFrame = workspace.CurrentCamera.CFrame

	-- if rotating AND moving, this doesn't work because the moving code changes the player's orientation towards the camera
	-- which overrides any possible turning. Need to decide what to actually do here--maybe move camera in that case

	-- should do opposite raycast (up) for looking from underneath xxx
	-- actually have utils functions to do this nicely now as of 2026-february-26
	local y = self.drivePart.Position.Y

	if moveFrac == 0 then
		-- instead of turning this on/off, maybe should just consider reducing its power
		self.alignOrientationConstraint.Enabled = not self.isShootingFireball

		local damping = 0.8
		local velocityVector = self.linearVelocityConstraint.VectorVelocity * damping

		local riseSpeed = self.riseSpeed

		local groundHeight = utils.getGroundHeight(self.drivePart.Position.X, self.drivePart.Position.Z)

		if groundHeight then
			if y > groundHeight - 10 and y < groundHeight - 5 then
				--print("idle moving down below ground")
				-- this is pretty useless, should really be looking at a getGroundHeightAbove to determine this
				velocityVector = Vector3.new(velocityVector.X, -riseSpeed, velocityVector.Z)
			elseif y >= groundHeight - 5 and y < groundHeight + 8 then
				--print("idle moving up above ground")
				local scale
				if y > groundHeight + 4 then
					scale = 1 - (self.drivePart.Position.Y - groundHeight - 4) / (8 - 4)
				else
					scale = 1
				end
				velocityVector = Vector3.new(velocityVector.X, riseSpeed * scale, velocityVector.Z)
			end
		end

		if self.drivePart.Position.Y > 500 then
			--print("too high, moving down")
			velocityVector = Vector3.new(velocityVector.X, -riseSpeed, velocityVector.Z)
		end

		self.linearVelocityConstraint.VectorVelocity = velocityVector

		--print("not moving velocity constraint", velocityVector, self.linearVelocityConstraint)
	else
		self.alignOrientationConstraint.Enabled = false

		-- adjust cameraCFrame to not let the player fly up or down at too crazy an angle
		-- also clamp it worse near the ground, so dragon doesn't fly into the ground
		-- also, if the intended direction would go straight into land, bend away

		-- take camera look vector, angle with same thing with y = 0
		local cameraLookVector = cameraCFrame.LookVector
		local cameraLookXZ = Vector3.new(cameraLookVector.X, 0, cameraLookVector.Z)
		local cameraAngle = cameraLookVector:Angle(cameraLookXZ)
		if cameraLookVector.Y < 0 then
			cameraAngle = cameraAngle * -1
		end
		local degrees = math.deg(cameraAngle)
		--print("angle is", degrees)
		local angle
		local signum = math.clamp(degrees, -1, 1)
		local deadZone
		local maxDeg

		if signum > 0 then
			--print("going up")
			deadZone = 15
			maxDeg = 75

			local groundHeightAbove = utils.getGroundHeightAbove(self.drivePart.Position)

			if groundHeightAbove then
				local minY = groundHeightAbove - 30
				local fullY = groundHeightAbove - 5

				-- smooth the ascent angle
				maxDeg = math.clamp(maxDeg * (1 - ((y - minY) / (fullY - minY))), 0, maxDeg)
				--print("maxdeg going up is", maxDeg)
			end
		else
			--print("going down")
			deadZone = 30
			maxDeg = 60

			local groundHeightBelow = utils.getGroundHeightBelow(self.drivePart.Position)

			if groundHeightBelow then
				local minY = groundHeightBelow + 3
				local fullY = groundHeightBelow + 15

				-- smooth the descent angle
				maxDeg = math.clamp(maxDeg * ((y - minY) / (fullY - minY)), 0, maxDeg)
				--print("maxdeg going down is", maxDeg)
			end

			--print("going down, y", y, "maxDeg", maxDeg, "deadZone", deadZone, "degrees", degrees)
		end
		if math.abs(degrees) < deadZone then
			angle = 0
		else
			degrees = math.abs(degrees)
			local newDeg = (degrees - deadZone) * maxDeg / (90 - deadZone)
			angle = signum * math.rad(newDeg)
		end

		local adjustedCameraCFrame = cameraCFrame * CFrame.fromEulerAnglesXYZ(angle - cameraAngle, 0, 0)

		--[[
		-- debug result
		local adjustedCameraLookVector = adjustedCameraCFrame.LookVector
		local adjustedCameraLookXZ = Vector3.new(adjustedCameraLookVector.X, 0, adjustedCameraLookVector.Z)
		local adjustedCameraAngle = adjustedCameraLookVector:Angle(adjustedCameraLookXZ, Vector3.zAxis)
		local adjustedDegrees = math.deg(adjustedCameraAngle)
		print("adjusted angle is magnitude, ignore sign", adjustedDegrees)
		]]

		--[[
		local delta = self.drivePart.CFrame:Inverse() * adjustedCameraCFrame
		local x, y, z = delta:ToEulerAnglesXYZ()
		print("rotation is", x, y, z)
		local scaledRotationVector = Vector3.new(x, y, z) * deltaTime * 60 / INTERPOLATE_MATCH_CAMERA_SEC
		--local scaledRotationVector = Vector3.new(x, y, z)
		print("scaled rotation is", scaledRotationVector)
		local interpolatedDeltaMatrix = CFrame.fromEulerAnglesXYZ(scaledRotationVector.X, scaledRotationVector.Y, scaledRotationVector.Z)
			local interpolatedMatrix = self.drivePart.CFrame * interpolatedDeltaMatrix
		]]

		local speedFrac = 1

		local avoidLandCFrame = adjustedCameraCFrame.Rotation
		--[[
		local avoidLandCFrame
		if isAdjusted then
			avoidLandCFrame = adjustedCameraCFrame.Rotation
		else
			speedFrac, avoidLandCFrame = self:adjustCFrameAwayFromLand(adjustedCameraCFrame.Rotation + self.drivePart.Position, moveFrac)
		end
		]]

		-- I think this is equivalent to the blob above
		local interpolatedMatrix = self.drivePart.CFrame.Rotation:Lerp(avoidLandCFrame, deltaTime * 60 / INTERPOLATE_MATCH_CAMERA_SEC)

		-- aim our drive part in the new direction
		self.drivePart.CFrame = interpolatedMatrix.Rotation + self.drivePart.Position
		local forwardDirection = interpolatedMatrix.LookVector

		local speedMultiplier
		if isFlyingFast then
			speedMultiplier = Constants.FLY_FAST_MULTIPLIER
		else
			speedMultiplier = 1
		end

		local velocityVector = (speedFrac * moveFrac * Constants.BASE_RIDE_SPEED * speedMultiplier) * forwardDirection

		--local forwardDirectionXZ = Vector3.new(forwardDirection.X, 0, forwardDirection.Z)
		--local forwardAngle = forwardDirection:Angle(forwardDirectionXZ, Vector3.zAxis)
		--print("forward direction angle to xz plane is", math.deg(forwardAngle))

		self.linearVelocityConstraint.VectorVelocity = velocityVector

		--print("moving velocity constraint", velocityVector, self.linearVelocityConstraint)
	end

	self:sendServerRidingItemCFrame()
end

function ClientRideController.enableTargeting(self: ClientRideController, objectId: any)
	self.targetObjectId = objectId

	local indicatorData = self.indicatorMap[self.targetObjectId]

	local inst = indicatorData.instance

	if not self.targetHighlight or not self.targetBase then
		local color
		if indicatorData.targetType == TARGET_TYPE_NODE or indicatorData.targetType == TARGET_TYPE_CRITTER then
			color = Color3.fromRGB(255, 255, 255)
		else
			local primaryElement = self.shadow:GetAttribute(Attributes.PRIMARY_ELEMENT)
			color = utils.getEffectColorForPrimaryElement(primaryElement)
		end

		if not self.targetHighlight then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TargetHighlight"
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillColor = color
			highlight.FillTransparency = 1
			highlight.OutlineColor = color
			highlight.OutlineTransparency = 0

			self.targetHighlight = highlight
		end

		if not self.targetBase then
			local size = inst:GetAttribute(Attributes.SIZE)
			if not size then
				-- now that we purposefully have some targetable things that don't get targetBase, we just set a default size for them since they won't be displayed anyway
				-- warn("targetable item missing size", inst)
				size = 20
			end

			self.targetBase = TargetBase.new(inst, size, color)
			self.targetBase:animateShow()
		end
	end

	local position = inst:getPivot().Position
	local groundHeight = utils.getGroundHeightBelow(position)
	if not groundHeight then
		-- sometimes the thing we can fire upon is not above ground; in that case, just don't have a target (the mega nodes are like this as of 2026-april-9)
		-- critters are like this as of 2026-may-29 too
		self.targetBase:hide()
		self.targetBase:setParent(inst)
	end

	--print("height is", groundHeight)
	self.targetBase:setPosition(Vector3.new(position.X, groundHeight, position.Z))
	if self.targetBase:getParent() ~= inst then
		self.targetBase:setParent(inst)
	end

	if self.targetHighlight.Parent ~= inst then
		self.targetHighlight.Enabled = false
		self.targetHighlight.Parent = inst
		self.targetHighlight.Enabled = true
	end

	local promptParent = inst.PrimaryPart or inst
	if self.prompt.Parent ~= promptParent then
		-- if you don't explicitly change enabled & parent in this way, then sometimes the proximity prompt won't move to its new place
		self.prompt.Enabled = false
		self.prompt.Parent = nil

		self.prompt.Parent = promptParent
		self.prompt.Enabled = true
	end

end

function ClientRideController.disableTargeting(self: ClientRideController)
	self.targetObjectId = nil

	if self.prompt then
		-- stash it away
		self.prompt.Parent = (player.Character :: any).HumanoidRootPart
		self.prompt.Enabled = false
	end

	if self.targetHighlight then
		self.targetHighlight:Destroy()
		self.targetHighlight = nil
	end

	if self.targetBase then
		-- maybe should animate it out instead?
		self.targetBase:destroy()
		self.targetBase = nil
	end
end

function ClientRideController.updateTargeting(self: ClientRideController)
	if self.isShootingFireball then
		self.prompt.Enabled = false
		return
	end

	local dragonPosition = self.shadow.Position

	local bestObjectId = nil
	local bestAngle = math.huge

	local primaryElement = self.shadow:GetAttribute(Attributes.PRIMARY_ELEMENT)
	local fireballModification = Elements.getFireballModificationForPrimaryElement(primaryElement)

	for objectId, indicatorData in self.indicatorMap do
		local inst = indicatorData.instance
		if inst.Parent ~= workspace then
			continue
		end

		local instPosition = inst:GetPivot().Position
		local distance = (dragonPosition - instPosition).Magnitude
		if distance > self.fireballRange then
			continue
		end

		if indicatorData.targetType == TARGET_TYPE_CROP then
			local encodedModifications = inst:GetAttribute(Attributes.MODIFICATIONS)
			local modifications = utils.getDecodedModifications(encodedModifications)
			if utils.doesArrayContain(modifications, fireballModification) then
				-- can't apply what it already has
				--xxx
				continue
			end
		end


		--print("candidate", inst.Name, objectId, distance)

		-- now see if it's the cone in front of us

		-- 1. Get the direction vector from origin to target
		local directionToTarget = (instPosition - dragonPosition).Unit

		-- 2. Get the CFrame's LookVector
		local dragonLookVector = self.shadow.CFrame.LookVector

		-- 3. Calculate the dot product
		-- The dot product of two unit vectors is the cosine of the angle between them
		local dotProduct = dragonLookVector:Dot(directionToTarget)

		-- 4. Convert the dot product back to degrees
		-- math.acos returns radians, so we convert to degrees
		local angle = math.deg(math.acos(dotProduct))
		if angle > self.fireballAngle then
			continue
		end

		-- now find angle with camera, and try to get closest there

		local cameraCFrame = workspace.CurrentCamera.CFrame
		local cameraLookVector = cameraCFrame.LookVector
		local cameraDirectionToTarget = (instPosition - cameraCFrame.Position).Unit
		local cameraDotProduct = cameraLookVector:Dot(cameraDirectionToTarget)
		local cameraAngle = math.deg(math.acos(cameraDotProduct))
		--print(string.format("angle to camera look vector %.0f", cameraAngle), inst)

		if bestAngle < cameraAngle then
			continue
		end

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = {(workspace :: any).Level}

		local raycastResult = workspace:Raycast(dragonPosition, directionToTarget * (distance - 0.01), raycastParams)

		if raycastResult then
			--print("obstruction, not a usable target", inst)
			continue
		end

		-- no obstruction, this is a legit target

		bestObjectId = objectId
		bestAngle = cameraAngle
	end

	if bestObjectId then
		--print("legit target", bestObjectId, bestAngle)
		self:enableTargeting(bestObjectId)
	else
		self:disableTargeting()
	end
end

function ClientRideController.run(self: ClientRideController, deltaTime: any)
	if not self.shadow then
		-- saw this in prod on 2026-april-17, not sure how it happens xxx
		return
	end

	self:updateStaminaHighlight(deltaTime)

	self:updateMovement(deltaTime)

	self:updateTargeting()
end

function ClientRideController.notifyTargetRemoving(self: ClientRideController, objectId: any)
	if self.targetObjectId ~= objectId then
		return
	end

	self:disableTargeting()
end

function ClientRideController.notifyNewInstance(self: ClientRideController, inst: any, objectId: any, targetType: any)
	if self.indicatorMap[objectId] then
		--print("told to track target we already have", objectId)
		return
	end

	if targetType == TARGET_TYPE_NODE then
		-- add them all
	elseif targetType == TARGET_TYPE_CROP then
		-- already filtered to be targetable, so it's good
	elseif targetType == TARGET_TYPE_CRITTER then
		-- just care about distance, so filter them somewhere else
	else
		warn("unknown target type", targetType)
		return
	end

	self.indicatorMap[objectId] = {
		instance = inst,
		targetType = targetType,
	}

end

function ClientRideController.notifyRemoveInstance(self: ClientRideController, inst: any, objectId: any)
	local indicatorData	= self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	self.indicatorMap[objectId] = nil
end

function ClientRideController.setupPlayerRiding(self: ClientRideController)

	-- find where the seat is
	local seatLocation = nil
	for _, descendant in self.caster:GetDescendants() do
		--print("have", caster, caster:GetAttribute(Attributes.SEAT_LOCATION))
		if not descendant:GetAttribute(Attributes.SEAT_LOCATION) then
			continue
		end

		seatLocation = descendant
		break
	end


	-- this stuff belongs in clientRideController
	--useful for debugging, comparing to server side
	--local playerPosition = (player.Character :: any).HumanoidRootPart.Position
	--local seatPosition = indicatorData.seatLocation.CFrame.Position
	--print("client positions player", playerPosition, "seat", seatPosition, "dragon", indicatorData.shadow:GetPivot().Position)

	local character = player.Character

	local seatLocationRelativeCFrame = CFrame.new(Vector3.new(0, seatLocation.Size.Y / 2 + 1.1, 0))
	local playerSittingCFrame = seatLocation.CFrame:toWorldSpace(seatLocationRelativeCFrame)

	-- disable default player movements
	local humanoid = (player.Character :: any).Humanoid
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	-- the character rig's children only exist at runtime, so they are untyped here
	local characterRig: any = character
	characterRig.HumanoidRootPart.Massless = true

	characterRig.HumanoidRootPart:PivotTo(playerSittingCFrame)

	local weldConstraint = Instance.new("WeldConstraint")
	weldConstraint.Name = "PlayerToSeatLocationWeld"
	weldConstraint.Part0 = characterRig.HumanoidRootPart
	weldConstraint.Part1 = seatLocation
	weldConstraint.Parent = self.caster

	self.playerSeatLocationWeld = weldConstraint

	local playerRelativeToDragonCFrame = self.shadow.CFrame:Inverse() * characterRig.HumanoidRootPart:GetPivot()

	--[[
	--useful debugging--even after player is welded, the relative position to the dragon is changing for unknown reasons
	print("player relative is", playerRelativeToDragonCFrame.Position, character.Humanoid:GetState())
	print("player is now at", (player.Character :: any).HumanoidRootPart:GetPivot().Position)
	task.delay(0,
		function()
			local newPlayerRelativeToDragonCFrame
			local c = 0
			while true do
				newPlayerRelativeToDragonCFrame = self.shadow.CFrame:Inverse() * (player.Character :: any).HumanoidRootPart:GetPivot()
				print("later player relative is", newPlayerRelativeToDragonCFrame.Position, character.Humanoid:GetState())
				c += 1
				if c == 5 then
					break
				end
				task.wait(1)
			end
		end
	)
	]]

	clientPlayerAnimationManager:disableBuiltInAnimations()
	clientPlayerAnimationManager:stopAllAnimations()

	clientPlayerAnimationManager:playSitAndRide()

	Satchel:SetBackpackEnabled(false)

	RemoteEvents.TryBeginRideDragon:FireServer(self.ridingItemId, playerRelativeToDragonCFrame)

end

function ClientRideController.cleanupPlayerRiding(self: ClientRideController)
	clientPlayerAnimationManager:stopAllAnimations()

	local characterRig: any = player.Character
	characterRig.HumanoidRootPart.Massless = false

	-- reenable default player movements
	local humanoid = (player.Character :: any).Humanoid
	humanoid.WalkSpeed = self.baseWalkSpeed
	humanoid.JumpPower = 50

	if self.playerSeatLocationWeld then
		self.playerSeatLocationWeld:Destroy()
	end

	clientPlayerAnimationManager:playJumpAndFall()
end

function ClientRideController.beginRiding(self: ClientRideController, shadow: any, caster: any)
	self.ridingItemId = shadow:GetAttribute(Attributes.ITEM_ID)

	self.shadow = shadow
	self.caster = caster

	self.fastDuration = clientPlayerVariables:get(Attributes.FLY_FAST_DURATION)

	self.riseSpeed = shadow:GetAttribute(Attributes.DRAGON_RISE_SPEED)
	self.flightDurationSec = 0

	self.isFlyingFast = self.fastDuration > 0

	self.prevStamina = 0
	self.isStaminaDecreasing = false

	self.fireballRange = clientPlayerVariables:get(Attributes.FIREBALL_RANGE)
	self.fireballAngle = clientPlayerVariables:get(Attributes.FIREBALL_ANGLE)

	--print("flight parameters", self.riseSpeed)

	local attachment: any = utils.findFirstDescendant(caster, "DriveAttachment")

	-- not sure why we need to set this here as of 2025-october-8
	attachment.Axis = Vector3.new(0, 1, 0)

	self.drivePart = attachment.Parent

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "KeepHeadFlat"
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.AlignType = Enum.AlignType.PrimaryAxisParallel
	alignOrientation.PrimaryAxis = Vector3.yAxis
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxTorque = 1000000
	alignOrientation.MaxAngularVelocity = math.huge
	alignOrientation.Responsiveness = 20 -- scale is 5 to 200
	alignOrientation.Attachment0 = attachment
	alignOrientation.Parent = self.drivePart
	self.alignOrientationConstraint = alignOrientation

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Attachment0 = attachment
	linearVelocity.Parent = self.drivePart
	self.linearVelocityConstraint = linearVelocity

	--print("drive part is", self.drivePart)

	self.drivePart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	if self.isFlyingFast then
		clientDragonManager:enableTrail(self.ridingItemId)
	end

	self.runConnect = runService.PreSimulation:Connect(
		function(deltaTime)
			self:run(deltaTime)
		end
	)

	self.attributeChangedConnect = shadow:GetAttributeChangedSignal(Attributes.DRAGON_STAMINA):Connect(
		function()
			self:updateStamina()
		end
	)

	screenGuiManager:setCurrentItemInstanceDisplay(shadow)

	screenGuiManager:setStaminaDisplayBlinkState(false)
	self:updateStamina()

	self:beginListenInputs()

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = utils.getLowStaminaColor()
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1

	highlight.Parent = caster

	self.staminaHighlight = highlight

	self.audioMountDragon:Play()
	self.audioRideDragon.Looping = true
	self.audioRideDragon:Play()

	self.latestRideStateChangeTime = workspace:GetServerTimeNow()

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = "FirePrompt"
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 0)
	objProximityPrompt.ActionText = "Fire"
	objProximityPrompt.HoldDuration = 0
	objProximityPrompt.MaxActivationDistance = math.huge
	objProximityPrompt.Enabled = false -- only enable prompt when have a target
	objProximityPrompt.Triggered:Connect(
		function()
			local indicatorData = self.indicatorMap[self.targetObjectId]
			if not indicatorData then
				-- shouldn't be possible
				return
			end
			self.isShootingFireball = true
			local ridingItemId = self.ridingItemId
			local targetObjectId = self.targetObjectId

			RemoteEvents.TryChargeUpRidingDragon:FireServer()

			task.delay(Constants.FIREBALL_CHARGE_SEC,
				function()
					-- we just delayed so make sure we should still fire
					if self.ridingItemId ~= ridingItemId then
						self.isShootingFireball = false
						return
					end

					if indicatorData.targetType == TARGET_TYPE_NODE then
						RemoteEvents.TryMineWhileRiding:FireServer(targetObjectId)
					elseif indicatorData.targetType == TARGET_TYPE_CROP then
						RemoteEvents.TryShootFireballAtCrop:FireServer(targetObjectId)
					elseif indicatorData.targetType == TARGET_TYPE_CRITTER then
						RemoteEvents.TryShootFireballAtCritter:FireServer(targetObjectId)
					else
						warn("unknown target type", indicatorData.targetType)
					end
				end
			)

		end
	)
	objProximityPrompt.Parent = (player.Character :: any).HumanoidRootPart

	self.prompt = objProximityPrompt


	self:setupPlayerRiding()

	-- start tracking targetable things here

	self.targetConnections = {}

	table.insert(self.targetConnections,
		collectionService:GetInstanceAddedSignal(Tags.MINABLE_NODE):Connect(
			function(inst)
				--print("new minable node")
				local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
				self:notifyNewInstance(inst, objectId, TARGET_TYPE_NODE)
			end
		)
	)

	table.insert(self.targetConnections,
		collectionService:GetInstanceRemovedSignal(Tags.MINABLE_NODE):Connect(
			function(inst)
				--print("minable node gone")
				local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
				self:notifyRemoveInstance(inst, objectId)
			end
		)
	)

	for _, inst in collectionService:GetTagged(Tags.MINABLE_NODE) do
		--print("existing minable node exists", inst)
		local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
		self:notifyNewInstance(inst, objectId, TARGET_TYPE_NODE)
	end

	table.insert(self.targetConnections,
		collectionService:GetInstanceAddedSignal(Tags.CROP):Connect(
			function(inst)
				--print("new crop", inst, inst:GetAttribute(Attributes.USER_ID), player.UserId)
				if inst:GetAttribute(Attributes.USER_ID) == player.UserId then
					-- can't target own crops
					return
				end
				--print("really using new crop", inst)
				local objectId = inst:GetAttribute(Attributes.ITEM_ID)
				self:notifyNewInstance(inst, objectId, TARGET_TYPE_CROP)
			end
		)
	)

	table.insert(self.targetConnections,
		collectionService:GetInstanceRemovedSignal(Tags.CROP):Connect(
			function(inst)
				--print("crop gone")
				local objectId = inst:GetAttribute(Attributes.ITEM_ID)
				self:notifyRemoveInstance(inst, objectId)
			end
		)
	)

	for _, inst in collectionService:GetTagged(Tags.CROP) do
		--print("existing crop exists", inst, inst:GetAttribute(Attributes.USER_ID), player.UserId)
		if inst:GetAttribute(Attributes.USER_ID) == player.UserId then
			-- can't target own crops
			continue
		end
		--print("really using new crop", inst)
		local objectId = inst:GetAttribute(Attributes.ITEM_ID)
		self:notifyNewInstance(inst, objectId, TARGET_TYPE_CROP)
	end

	table.insert(self.targetConnections,
		collectionService:GetInstanceAddedSignal(Tags.CRITTER_CASTER):Connect(
			function(inst)
				--print("new critter")
				local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
				self:notifyNewInstance(inst, objectId, TARGET_TYPE_CRITTER)
			end
		)
	)

	table.insert(self.targetConnections,
		collectionService:GetInstanceRemovedSignal(Tags.CRITTER_CASTER):Connect(
			function(inst)
				--print("critter gone")
				local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
				self:notifyRemoveInstance(inst, objectId)
			end
		)
	)

	for _, inst in collectionService:GetTagged(Tags.CRITTER_CASTER) do
		--print("existing critter exists", inst)
		local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
		self:notifyNewInstance(inst, objectId, TARGET_TYPE_CRITTER)
	end


	local isRiding = true

	self.event:Fire(isRiding)
end

function ClientRideController.cleanupRiding(self: ClientRideController)
	self.isShootingFireball = false

	-- stop tracking targets
	for _, targetConnection in self.targetConnections do
		targetConnection:Disconnect()
	end
	self.targetConnections = {}

	self.indicatorMap = {}

	self:disableTargeting()

	if self.prompt then
		self.prompt:Destroy()
		self.prompt = nil
	end

	self.audioRideDragon:Stop()

	if self.casterDestroyConnect then
		self.casterDestroyConnect:Disconnect()
		self.casterDestroyConnect = nil
	end

	if self.staminaHighlight then
		self.staminaHighlight:Destroy()
		self.staminaHighlight = nil
	end

	self:cleanupListenInputs()

	if self.sweatInst then
		self.sweatInst:Destroy()
		self.sweatInst = nil
	end

	self.lastSendServer = nil

	self:cleanupPlayerRiding()

	-- if dragon was destroyed (for example, it was merged away) then we can't check its stamina (but also we don't care)
	-- (or maybe we want to launch in that situation too, actually?)

	local launchSpeed = 60
	local wasDragonDestroyed = false
	if self.shadow then
		wasDragonDestroyed = (self.shadow.Parent == nil)
		if wasDragonDestroyed then
			launchSpeed *= 2
		else
			local stamina = self.shadow:GetAttribute(Attributes.DRAGON_STAMINA)
			if stamina == 0 then
				launchSpeed *= 2
			end
		end
	end

	-- launch player vertically a bit
	local launchRig: any = player.Character
	local impulse = launchSpeed * launchRig.HumanoidRootPart.AssemblyMass * Vector3.yAxis
	launchRig.HumanoidRootPart:ApplyImpulse(impulse)

	self.drivePart = nil

	if self.alignOrientationConstraint then
		self.alignOrientationConstraint:Destroy()
		self.alignOrientationConstraint = nil
	end

	if self.linearVelocityConstraint then
		self.linearVelocityConstraint:Destroy()
		self.linearVelocityConstraint = nil
	end

	if self.runConnect then
		self.runConnect:Disconnect()
		self.runConnect = nil
	end

	if self.attributeChangedConnect then
		self.attributeChangedConnect:Disconnect()
		self.attributeChangedConnect = nil
	end

	screenGuiManager:setStaminaDisplay(nil)

	Satchel:SetBackpackEnabled(true)

	clientDragonManager:disableTrail(self.ridingItemId)

	if self.modificationsConnect then
		self.modificationsConnect:Disconnect()
		self.modificationsConnect = nil
	end
	if self.mutationConnect then
		self.mutationConnect:Disconnect()
		self.mutationConnect = nil
	end

	screenGuiManager:setCurrentItemInstanceDisplay(nil)

	if not wasDragonDestroyed then
		-- enforce a cooldown before riding again, as long as the dragon wasn't just destroyed
		-- if the dragon was just destroyed, then that means it was merged, and we want the player
		-- to be able to ride a new dragon immediately
		self.latestRideStateChangeTime = workspace:GetServerTimeNow()
	end

	self.shadow = nil
	self.caster = nil

	self.ridingItemId = nil

	local isRiding = false
	self.event:Fire(isRiding)

end

function ClientRideController.notifyBeginRideDragonStatus(self: ClientRideController, isSuccess: any)
	if isSuccess then
		return
	end

	if not self:isRiding() then
		return
	end

	-- this calls back into us to cleanup too
	clientDragonManager:cleanupRiding(self.ridingItemId)
end

function ClientRideController.notifyTrySetRidingCFrameRejected(self: ClientRideController, ridingCFrame: any)
	if not self:isRiding() then
		return
	end

	self.shadow:PivotTo(ridingCFrame)
	self.caster:PivotTo(self.shadow:GetPivot())
end

-- when player decides to stop
function ClientRideController.tryEndRiding(self: ClientRideController)
	if not self:isRiding() then
		return
	end

	RemoteEvents.TryEndRideDragon:FireServer(self.ridingItemId)

	-- this calls back into us to cleanup too
	clientDragonManager:cleanupRiding(self.ridingItemId)
end

-- when server tells us (dragon ran out of stamina)
function ClientRideController.notifyStopRiding(self: ClientRideController)
	if not self:isRiding() then
		return
	end

	-- this calls back into us to cleanup too
	clientDragonManager:cleanupRiding(self.ridingItemId)
end

function ClientRideController.notifyMineWhileRidingStatus(self: ClientRideController, isSuccess: any)
	--print("mine while riding status", isSuccess)

	if not self:isRiding() then
		return
	end

	if not isSuccess then
		self.isShootingFireball = false
	end


	-- this means the fireball has started, not that it's done
end

function ClientRideController.notifyShootFireballAtCropStatus(self: ClientRideController, isSuccess: any)
	--print("shoot fireball at crop status", isSuccess)

	if not self:isRiding() then
		return
	end

	if not isSuccess then
		self.isShootingFireball = false
	end

	-- this means the fireball has started, not that it's done
end

function ClientRideController.notifyShootFireballAtCritterStatus(self: ClientRideController, isSuccess: any)
	--print("shoot fireball at critter status", isSuccess)

	if not self:isRiding() then
		return
	end

	if not isSuccess then
		self.isShootingFireball = false
	end

	-- this means the fireball has started, not that it's done
end

function ClientRideController.notifyFireballCompleted(self: ClientRideController)
	self.isShootingFireball = false
end

function ClientRideController.isRiding(self: ClientRideController): boolean
	return self.caster ~= nil
end

function ClientRideController.isRidingAndControlling(self: ClientRideController): boolean
	if not self:isRiding() then
		return false
	end

	if not self.shadow:GetAttribute(Attributes.CLIENT_CONTROL) then
		return false
	end

	return true
end

function ClientRideController.isRidingAndControllingAndInFreeFlyZone(self: ClientRideController): boolean
	if not self:isRidingAndControlling() then
		return false
	end

	if not self.shadow:GetAttribute(Attributes.DRAGON_IS_IN_FREE_FLY_ZONE) then
		return false
	end

	return true
end

function ClientRideController.isInRideBeginCooldown(self: ClientRideController)
	return workspace:GetServerTimeNow() - RIDE_BEGIN_COOLDOWN_SEC <= self.latestRideStateChangeTime
end

function ClientRideController.getRidingObj(self: ClientRideController): any
	return self.shadow
end

function ClientRideController.getStamina(self: ClientRideController)
	if not self:isRiding() then
		return 0
	end

	return self.shadow:GetAttribute(Attributes.DRAGON_STAMINA)
end

function ClientRideController.notifyBeginSitting(self: ClientRideController, shadow: any, caster: any)
	self:beginRiding(shadow, caster)

	self.casterDestroyConnect = caster.Destroying:Connect(
		function()
			self.casterDestroyConnect = nil
			self:cleanupRiding()
		end
	)
end

function ClientRideController.notifyEndSitting(self: ClientRideController)
	self:cleanupRiding()
end

function ClientRideController.getEvent(self: ClientRideController): RBXScriptSignal
	return self.event.Event
end

function ClientRideController.getMapSize(self: ClientRideController)
	return utils.getTableSize(self.indicatorMap)
end

function ClientRideController.init(self: ClientRideController)
	-- late load to avoid circular references

	local ridingDragonAudioParent = RidingDragonAudioParent:Clone()
	ridingDragonAudioParent.Parent = workspace

	self.audioMountDragon = ridingDragonAudioParent:FindFirstChild("AudioMountDragon")
	self.audioRideDragon = ridingDragonAudioParent:FindFirstChild("AudioRideDragon")

	local character: any = player.Character or player.CharacterAdded:Wait()
	local humanoid = character.Humanoid
	self.baseWalkSpeed = humanoid.WalkSpeed
end

function ClientRideController.new(): ClientRideController
	local self = setmetatable({} :: ClientRideControllerFields, ClientRideController)

	self.ridingItemId = nil

	self.shadow = nil
	self.caster = nil

	self.drivePart = nil

	self.riseSpeed = nil

	self.alignOrientationConstraint = nil
	self.linearVelocityConstraint = nil

	self.runConnect = nil

	self.staminaHighlight = nil

	self.event = Instance.new("BindableEvent")

	self.latestRideStateChangeTime = workspace:GetServerTimeNow()

	-- target stuff
	self.isShootingFireball = false
	self.indicatorMap = {}

	return self
end

function ClientRideController.initClass(deps: any)
	clientDragonManager = deps.clientDragonManager
	clientPlayerAnimationManager = deps.clientPlayerAnimationManager
end

local singleton = ClientRideController.new()

return singleton
