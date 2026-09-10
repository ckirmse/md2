--!strict


local runService = game:GetService("RunService")

local ClientDragonManager = {}
ClientDragonManager.__index = ClientDragonManager

local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
local DragonBreathWeapon = Effects:WaitForChild("DragonBreathWeapon")
local ChargeUpFireballAudioParent = Effects:WaitForChild("ChargeUpFireballAudioParent")
local ShootFireballAudioParent = Effects:WaitForChild("ShootFireballAudioParent")
local DragonEatAudioParent = Effects:WaitForChild("DragonEatAudioParent")
local UX = GameAssets:WaitForChild("UX")
local RideDragonBillboard = UX:WaitForChild("RideDragonBillboard")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
local FireballCharge = ParticleEffects:WaitForChild("FireballCharge")
local FireballShoot = ParticleEffects:WaitForChild("FireballShoot")
local MergePost = ParticleEffects:WaitForChild("MergePost")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientEventHandlers = require("./ClientEventHandlers")
local clientOptionsManager = require("./ClientOptionsManager")
local clientRideController = require("./ClientRideController")
local clientShadowManager = require("./ClientShadowManager")
local clientTradingManager = require("./ClientTradingManager")

-- this is to handle a ridiculous built-in roblox behavior around trying to jump
local JUMP_COOLDOWN_SEC = 0.5

local PULSE_NEAR_MAX_DESCEND_PER_SEC = 3
local PULSE_FAR_MAX_ASCEND_PER_SEC = 3

local PULSE_LEVEL_SEC = 2

-- every this many seconds, we should expect to do a head animation
local EXPECTED_ANIMATE_HEAD_SEC = 20

local ANIMATE_HEAD_MAX_ANGLE = 15
local player = game:GetService("Players").LocalPlayer :: Player

type ClientDragonManagerFields = {
	flapSec: any,
	indicatorMap: { [any]: any },
	latestJumpRequestTime: any,
}

export type ClientDragonManager = typeof(setmetatable({} :: ClientDragonManagerFields, ClientDragonManager))

function ClientDragonManager.tryBeginRidingNearestDragon(self: ClientDragonManager): boolean
	if clientTradingManager:isTrading() then
		-- can't start riding while trading
		return false
	end

	-- nearest dragon will be the only one with an enabled billboard
	local bestItemId = nil
	local indicatorData = nil
	for itemId, thisIndicatorData in self.indicatorMap do
		if not thisIndicatorData.billboard or not thisIndicatorData.billboard.Enabled then
			continue
		end
		bestItemId = itemId
		indicatorData = thisIndicatorData
		break
	end

	if not bestItemId then
		return false
	end

	--print("trying to ride", bestItemId)
	indicatorData.isRiding = true

	indicatorData.caster.PrimaryPart.Anchored = not indicatorData.shadow:GetAttribute(Attributes.CLIENT_CONTROL)

	clientRideController:notifyBeginSitting(indicatorData.shadow, indicatorData.caster)

	return true
end

function ClientDragonManager.cleanupRiding(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster
	if caster.PrimaryPart then
		caster.PrimaryPart.Anchored = true
	end

	clientRideController:notifyEndSitting()

	indicatorData.isRiding = false

	-- rebuild an equipped dragon's ghost so it flies home from a clean pose, not the ride pose
	if indicatorData.shadow:GetAttribute(Attributes.DRAGON_SLOT_INDEX) ~= nil then
		clientShadowManager:recreateCaster(itemId)
	end
end

function ClientDragonManager.findBodyParts(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster

	local root: any = caster
	local part: any
	if caster:IsA("Model") then
		part = caster.PrimaryPart
		if not part then
			part = utils.tryGetHandleForModel(caster)
			root = part
		end
	else
		part = caster
	end

	local parts: any = {}
	indicatorData.parts = parts
	parts.isComplete = false

	parts.part = part

	parts.attachmentBodyLeftWing = utils.findFirstDescendantOfClassAndName(root, "Attachment", "Wing_Left")
	if not parts.attachmentBodyLeftWing then
		return
	end
	parts.leftWing = root:FindFirstChild("Wing_Left")
	if not parts.leftWing then
		return
	end
	parts.attachmentLeftWing = parts.leftWing:FindFirstChild("Wing")
	if not parts.attachmentLeftWing then
		return
	end

	parts.attachmentBodyRightWing = utils.findFirstDescendantOfClassAndName(root, "Attachment", "Wing_Right")
	if not parts.attachmentBodyRightWing then
		return
	end
	parts.rightWing = root:FindFirstChild("Wing_Right")
	if not parts.rightWing then
		return
	end
	parts.attachmentRightWing = parts.rightWing:FindFirstChild("Wing")
	if not parts.attachmentRightWing then
		return
	end

	parts.isComplete = true
end

function ClientDragonManager.setupFlappingWings(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("starting some client flapping", indicatorData.flapPeriod, indicatorData.flapAmplitude)

	local shadow = indicatorData.shadow

	indicatorData.flapSec = 0

	indicatorData.runFlapConnect = runService.PostSimulation:Connect(
		function(deltaTime: number)
			--print("flapping", indicatorData.flapPeriod, indicatorData.flapAmplitude)

			if not indicatorData.parts or not indicatorData.parts.isComplete then
				self:findBodyParts(itemId)
			end

			if not indicatorData.parts.isComplete then
				--print("missing parts to flap dragon wings")
				return
			end

			local caster = indicatorData.caster

			if not caster:GetAttribute(Attributes.MERGING) then
				indicatorData.flapSec = (indicatorData.flapSec + deltaTime) % indicatorData.flapPeriod
			end

			local angle = 90 + math.sin(indicatorData.flapSec * 2 * math.pi / indicatorData.flapPeriod) * indicatorData.flapAmplitude / 2

			-- left wing
			do
				local rotation = CFrame.fromEulerAnglesXYZ(math.rad(angle), 0, 0)
				local attachmentWorldCFrame = indicatorData.parts.attachmentBodyLeftWing.WorldCFrame * rotation
				indicatorData.parts.leftWing.CFrame = attachmentWorldCFrame * indicatorData.parts.attachmentLeftWing.CFrame:Inverse()
			end

			-- right wing
			do
				local rotation = CFrame.fromEulerAnglesXYZ(math.rad(180 - angle), 0, 0)
				local attachmentWorldCFrame = indicatorData.parts.attachmentBodyRightWing.WorldCFrame * rotation
				indicatorData.parts.rightWing.CFrame = attachmentWorldCFrame * indicatorData.parts.attachmentRightWing.CFrame:Inverse()
			end
		end
	)

	indicatorData.flapDataConnect = shadow:GetAttributeChangedSignal(Attributes.DRAGON_FLAP_DATA):Connect(
		function()
			local flapDataStr = shadow:GetAttribute(Attributes.DRAGON_FLAP_DATA)
			local iterFunc = string.gmatch(flapDataStr, "%S+")

			local flapPeriod = tonumber(iterFunc())
			local flapAmplitude = tonumber(iterFunc())

			--print("new flap data", flapPeriod, flapAmplitude)

			local currentFlapPeriodFrac = (indicatorData.flapSec % indicatorData.flapPeriod) / indicatorData.flapPeriod
			self.flapSec = currentFlapPeriodFrac * indicatorData.flapPeriod

			indicatorData.flapPeriod = flapPeriod
			indicatorData.flapAmplitude = flapAmplitude
		end
	)
end

function ClientDragonManager.getPartFromIndicatorData(self: ClientDragonManager, indicatorData: any)
	local caster = indicatorData.caster
	local shadow = indicatorData.shadow

	local part
	if caster:IsA("Model") then
		part = caster.PrimaryPart
		if not part then
			part = utils.tryGetHandleForModel(shadow)
		end
	else
		part = caster
	end

	return part
end

function ClientDragonManager.updateAnimateHead(self: ClientDragonManager, itemId: any, deltaTime: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local part = self:getPartFromIndicatorData(indicatorData)
	if not part then
		return
	end

	if indicatorData.isAnimatingHead then
		indicatorData.animateHeadSec += deltaTime
		while indicatorData.animateHeadSec > indicatorData.animateHeadStepSec do
			indicatorData.animateHeadSec -= indicatorData.animateHeadStepSec
			indicatorData.animateHeadStep += 1

			indicatorData.animateHeadBeginAngle = indicatorData.animateHeadEndAngle

			if indicatorData.animateHeadStep >= indicatorData.animateHeadTotalSteps then
				indicatorData.animateHeadEndAngle = 0
				indicatorData.animateHeadStepSec = indicatorData.animateHeadFullStepSec / 2
			else
				if (indicatorData.animateHeadStep % 2) == 0 then
					indicatorData.animateHeadEndAngle = ANIMATE_HEAD_MAX_ANGLE
				else
					indicatorData.animateHeadEndAngle = -ANIMATE_HEAD_MAX_ANGLE
				end
				indicatorData.animateHeadStepSec = indicatorData.animateHeadFullStepSec
			end

			if indicatorData.animateHeadStep > indicatorData.animateHeadTotalSteps then
				indicatorData.animateHeadSec = 0
				indicatorData.isAnimatingHead = false
			end
		end

		indicatorData.animateHeadCurrentAngle = indicatorData.animateHeadBeginAngle + (indicatorData.animateHeadEndAngle - indicatorData.animateHeadBeginAngle) * (indicatorData.animateHeadSec / indicatorData.animateHeadStepSec)

		--print("angle is now", itemId, indicatorData.animateHeadCurrentAngle)
	else
		local random = Random.new()
		if random:NextNumber(0, 1) < (deltaTime * (1 / EXPECTED_ANIMATE_HEAD_SEC)) then
			--print("starting head animation")
			indicatorData.animateHeadBaseRotation = part.CFrame.Rotation
			-- configuration data that applies to the whole animation
			local rotationAxisIndex = random:NextInteger(1, 5)
			if rotationAxisIndex == 1 then
				-- axis is relative to the dragon--x is the straight ahead axis
				indicatorData.animateHeadRotationAxis = Vector3.xAxis
				indicatorData.animateHeadFullStepSec = random:NextNumber(3, 10)
				indicatorData.animateHeadTotalSteps = random:NextInteger(1, 3)
			elseif rotationAxisIndex == 2 then
				indicatorData.animateHeadRotationAxis = Vector3.zAxis
				indicatorData.animateHeadFullStepSec = random:NextNumber(0.5, 1.5)
				indicatorData.animateHeadTotalSteps = random:NextInteger(1, 2)
			else
				-- we do this most of the time
				indicatorData.animateHeadRotationAxis = Vector3.yAxis
				indicatorData.animateHeadFullStepSec = random:NextNumber(0.5, 10)
				indicatorData.animateHeadTotalSteps = random:NextInteger(1, 6)
			end

			-- initialize data that gets updated regularly
			indicatorData.animateHeadSec = 0
			indicatorData.animateHeadStepSec = indicatorData.animateHeadFullStepSec / 2
			indicatorData.animateHeadStep = 1
			indicatorData.animateHeadCurrentAngle = 0
			indicatorData.animateHeadBeginAngle = 0
			indicatorData.animateHeadEndAngle = -ANIMATE_HEAD_MAX_ANGLE

			indicatorData.isAnimatingHead = true
		end
	end
end


function ClientDragonManager.setupIdlePulsing(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("starting some client idle pulsing")

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

	local part = self:getPartFromIndicatorData(indicatorData)

	indicatorData.pulseSec = 0
	indicatorData.basePosition = part.Position
	indicatorData.groundHeight = utils.getGroundHeightBelow(part.Position) or 0

	indicatorData.playerNearIntensity = 0
	indicatorData.playerNearAdjustmentY = 0

	local _, size = caster:GetBoundingBox()
	--print("obj", obj, "modelDepth", orientation.Position.Y - size.Y, "pos", orientation.Position.Y, "size", size.Y)
	indicatorData.modelDepth = size.Y / 2

	indicatorData.isAnimatingHead = false

	indicatorData.runPulseConnect = runService.PostSimulation:Connect(
		function(deltaTime: number)
			local caster = indicatorData.caster
			local part = self:getPartFromIndicatorData(indicatorData)
			if not part then
				return
			end

			if caster:GetAttribute(Attributes.MERGING) then
				return
			end

			if shadow:GetAttribute(Attributes.DRAGON_RIDER) or not shadow:GetAttribute(Attributes.CLIENT_CONTROL) or not shadow:GetAttribute(Attributes.DRAGON_PULSE_DATA) then
				--print("resetting pulsing", shadow:GetAttribute(Attributes.DRAGON_RIDER), shadow:GetAttribute(Attributes.CLIENT_CONTROL), shadow:GetAttribute(Attributes.DRAGON_PULSE_DATA))
				indicatorData.pulseSec = 0
				indicatorData.basePosition = part.Position
				indicatorData.groundHeight = utils.getGroundHeightBelow(part.Position) or 0

				indicatorData.playerNearIntensity = 0
				indicatorData.playerNearAdjustmentY = 0

				indicatorData.baseRotation = CFrame.identity

				return
			end

			if caster.Parent ~= workspace then
				-- this can happen when the caster is destroyed and recreated (only done if we're trying to clean up for crazy unknown stuff)
				return
			end

			if shadow.Parent ~= workspace then
				return
			end

			if not (player.Character :: any).HumanoidRootPart then
				return
			end

			local playerPosition = (player.Character :: any).HumanoidRootPart.Position
			local dragonPosition
			if indicatorData.seatLocation then
				dragonPosition = indicatorData.seatLocation.Position
			else
				dragonPosition = part.Position
			end
			local distance = utils.getMagnitudeXZ(playerPosition - dragonPosition)

			local shouldLowerDragon = indicatorData.isOwnedByPlayer and distance <= Constants.BEGIN_RIDE_DISTANCE
			local isPlayerWellAboveDragon = ((player.Character :: any).HumanoidRootPart.Position.Y > part.Position.Y + 10)
			if isPlayerWellAboveDragon then
				shouldLowerDragon = false
			end
			if not shadow:HasTag(Tags.RIDABLE) then
				shouldLowerDragon = false
			end


			if indicatorData.pulseSec == 0 then
				-- this means we are just starting a pulse, not that we just started pulsing in general

				local pulseDataStr = shadow:GetAttribute(Attributes.DRAGON_PULSE_DATA)
				local iterFunc = string.gmatch(pulseDataStr, "%S+")

				indicatorData.pulsePeriodSec = tonumber(iterFunc())
				local pulseAmplitudePlayerFar = tonumber(iterFunc())
				local pulseAmplitudePlayerNear = tonumber(iterFunc())

				if shouldLowerDragon then
					indicatorData.pulseAmplitude = pulseAmplitudePlayerNear
				else
					indicatorData.pulseAmplitude = pulseAmplitudePlayerFar
				end

				--print("dragon with period", indicatorData.pulsePeriodSec, "amplitudePlayerFar", pulseAmplitudePlayerFar, "amplitudePlayerNear", pulseAmplitudePlayerNear, "pulseAmplitude", indicatorData.pulseAmplitude)
			end

			if shadow:HasTag(Tags.RIDABLE) then
				if shouldLowerDragon then
					--print("player under us", indicatorData.playerNearIntensity, indicatorData.playerNearAdjustmentY)
					indicatorData.playerNearIntensity = math.min(1, indicatorData.playerNearIntensity + deltaTime)
					local maxAdjustmentY = indicatorData.basePosition.Y - indicatorData.groundHeight - indicatorData.modelDepth
					indicatorData.playerNearAdjustmentY = math.max(-maxAdjustmentY, indicatorData.playerNearAdjustmentY - indicatorData.playerNearIntensity * deltaTime * PULSE_NEAR_MAX_DESCEND_PER_SEC)
				else
					--print("player not under us", indicatorData.playerNearIntensity)
					indicatorData.playerNearIntensity = math.max(0, indicatorData.playerNearIntensity - deltaTime)
					indicatorData.playerNearAdjustmentY = math.min(0, (indicatorData.playerNearAdjustmentY + (1 - indicatorData.playerNearIntensity) * deltaTime * PULSE_FAR_MAX_ASCEND_PER_SEC))
				end
			end

			indicatorData.pulseSec = (indicatorData.pulseSec + deltaTime)
			while indicatorData.pulseSec > indicatorData.pulsePeriodSec do
				indicatorData.pulseSec -= indicatorData.pulsePeriodSec
			end

			local sinInput = (3 * math.pi / 2) + 2 * math.pi * indicatorData.pulseSec / indicatorData.pulsePeriodSec
			local sinResult = math.sin(sinInput)

			local pulseDiffY = indicatorData.pulseAmplitude * ((1 + sinResult) / 2)

			self:updateAnimateHead(itemId, deltaTime)

			local rotation
			if indicatorData.isAnimatingHead then
				local animateHeadRotation = CFrame.fromAxisAngle(indicatorData.animateHeadRotationAxis, math.rad(indicatorData.animateHeadCurrentAngle))
				rotation = indicatorData.animateHeadBaseRotation * animateHeadRotation
			else
				rotation = part.CFrame.Rotation
			end

			local diffY = pulseDiffY + indicatorData.playerNearAdjustmentY

			-- check ground, don't let dragon get below ground plus min clearance
			local minimumY = indicatorData.groundHeight + indicatorData.modelDepth
			if indicatorData.basePosition.Y + diffY < minimumY then
				--print("too low; ground", indicatorData.groundHeight, "model depth", indicatorData.modelDepth, "baseY", indicatorData.basePosition.Y, "minimumY", minimumY, "diffY", diffY, "diffY set to", minimumY - indicatorData.basePosition.Y)
				diffY = minimumY - indicatorData.basePosition.Y
			end

			--print("sinInput", sinInput, "sinResult", sinResult, "pulseDiffY", pulseDiffY, "diffY", diffY, "mininumY", minimumY)

			local diffPosition = Vector3.new(0, diffY, 0)
			local newPosition = indicatorData.basePosition + diffPosition
			local baseCFrame = CFrame.new(newPosition) * rotation

			--local angleFromVertical = utils.getAngleFromVertical(baseCFrame)
			--print("angle from vertical", utils.getAngleFromVertical(baseCFrame))

			local newCFrame
			if indicatorData.isAnimatingHead then
				newCFrame = baseCFrame
			else
				-- work towards leveling dragon head over time
				local levelCFrame = CFrame.new(newPosition) * rotation
				levelCFrame = utils.getCFrameParallelToGround(levelCFrame)

				newCFrame = baseCFrame:Lerp(levelCFrame, deltaTime / PULSE_LEVEL_SEC)
			end

			part:PivotTo(newCFrame)
		end
	)
end

function ClientDragonManager.setupEnergyDecay(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("starting client dragon energy decay")

	local caster = indicatorData.caster
	local shadow = indicatorData.shadow

	local assemblies = utils.getAssembliesInModel(caster)
	--print("dragon assemblies", itemId, caster, assemblies)

	-- let dragons explode while we test by doing this
	--if true then return end

	indicatorData.runEnergyDecayConnect = runService.PreSimulation:Connect(
		function(deltaTime: number)
			if shadow.Parent ~= workspace then
				return
			end

			if caster:GetAttribute(Attributes.MERGING) then
				return
			end

			if indicatorData.isRiding then
				return
			end

			for _, part in assemblies do
				-- force dragons to explode doing this
				--part.AssemblyLinearVelocity = part.AssemblyLinearVelocity * (1 + deltaTime)
				--if true then continue end

				if part.AssemblyLinearVelocity.Magnitude > 10 then
					--print(part, "linear", part.AssemblyLinearVelocity, "angular", part.AssemblyAngularVelocity)
					part.AssemblyLinearVelocity = (part.AssemblyLinearVelocity / part.AssemblyLinearVelocity.Magnitude) * 10
				elseif part.AssemblyLinearVelocity.Magnitude > 3 then
					part.AssemblyLinearVelocity *= 0.7 / (deltaTime * 60)
				else
					part.AssemblyLinearVelocity *= 0.95 / (deltaTime * 60)
				end

				if part.AssemblyAngularVelocity.Magnitude > 10 then
					part.AssemblyAngularVelocity = (part.AssemblyAngularVelocity / part.AssemblyAngularVelocity.Magnitude) * 10
				elseif part.AssemblyAngularVelocity.Magnitude > 3 then
					part.AssemblyAngularVelocity *= 0.7 / (deltaTime * 60)
				else
					part.AssemblyAngularVelocity *= 0.95 / (deltaTime * 60)
				end
			end
		end
	)
end


function ClientDragonManager.beginAnimateChargeUp(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.powerupParticleParent then
		return
	end

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

	local mouth: any = utils.findFirstDescendant(caster, "Particle_Emitter")

	local primaryElement = shadow:GetAttribute(Attributes.PRIMARY_ELEMENT)

	local particleParent: any = FireballCharge:Clone()
	utils.setPropertyTreeClassName(particleParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
	particleParent:PivotTo(mouth.CFrame)
	particleParent.Anchored = false
	particleParent.Parent = caster

	local weld
	weld = Instance.new("WeldConstraint")
	weld.Part0 = mouth
	weld.Part1 = particleParent
	weld.Parent = particleParent

	indicatorData.fireballChargeParticleParent = particleParent

	local chargeUpFireballAudioParent: any = ChargeUpFireballAudioParent:Clone()
	chargeUpFireballAudioParent.Position = mouth.Position
	chargeUpFireballAudioParent.Parent = caster

	weld = Instance.new("WeldConstraint")
	weld.Part0 = mouth
	weld.Part1 = chargeUpFireballAudioParent
	weld.Parent = caster

	game:GetService("Debris"):AddItem(chargeUpFireballAudioParent, 5) -- destroy after 5s
	game:GetService("Debris"):AddItem(weld, 5) -- destroy after 5s

	local audioChargeUpFireball = chargeUpFireballAudioParent:FindFirstChild("AudioChargeUpFireball")
	audioChargeUpFireball:Play()

end

function ClientDragonManager.cleanupAnimateChargeUp(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.fireballChargeParticleParent then
		utils.safelyDisposeOfParticleParent(indicatorData.fireballChargeParticleParent, 0)
		indicatorData.fireballChargeParticleParent = nil
	end
end


function ClientDragonManager.beginAnimateShootFireball(self: ClientDragonManager, itemId: any, fireballPath: any, destPosition: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("dragon shooting fireball", fireballPath, destPosition)

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

	local primaryElement = shadow:GetAttribute(Attributes.PRIMARY_ELEMENT)

	local mouth: any = utils.findFirstDescendant(caster, "Particle_Emitter")

	-- add some sparkleys around the mouth
	local sparkleyParent: any = FireballShoot:Clone()
	utils.setPropertyTreeClassName(sparkleyParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
	sparkleyParent:PivotTo(mouth.CFrame)
	sparkleyParent.Parent = caster
	utils.safelyDisposeOfParticleParent(sparkleyParent, 0.75)

	-- we send out a fireball
	local fireballTemplate = utils.getGameAssetPathReference(fireballPath)
	--print("fireballtemplate", fireballTemplate)
	if not fireballTemplate then
		return
	end

	local fireball: any = (fireballTemplate :: any):Clone()
	fireball:PivotTo(mouth.CFrame)
	fireball.Parent = workspace

	local fireEffect: any = utils.findFirstDescendant(fireball, "Fire")
	if fireEffect then
		fireEffect:Emit(5)
	end

	local moveTweenInfo = TweenInfo.new(Constants.FIREBALL_TRAVEL_SEC, Enum.EasingStyle.Linear)
	local targetCFrame = fireball:GetPivot().Rotation + destPosition
	local moveTween = PivotToTween(fireball, moveTweenInfo, targetCFrame)
	moveTween.Completed:Connect(
		function()
			fireball:Destroy()

			if not indicatorData.isRiding then
				return
			end

			clientRideController:notifyFireballCompleted()
		end
	)
	moveTween:Play()

	local shootFireballAudioParent: any = ShootFireballAudioParent:Clone()
	shootFireballAudioParent.Position = mouth.Position
	shootFireballAudioParent.Parent = caster

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = mouth
	weld.Part1 = shootFireballAudioParent
	weld.Parent = caster

	game:GetService("Debris"):AddItem(shootFireballAudioParent, 5) -- destroy after 5s
	game:GetService("Debris"):AddItem(weld, 5) -- destroy after 5s

	local audioShootFireball = shootFireballAudioParent:FindFirstChild("AudioShootFireball")
	audioShootFireball:Play()

end

function ClientDragonManager.cleanupAnimateShootFireball(self: ClientDragonManager, itemId: any)

end

function ClientDragonManager.beginAnimateEat(self: ClientDragonManager, itemId: any, audioPitchShift: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.eating then
		print("dragon already eating, cannot begin animate eat", itemId)
		return
	end

	--print("starting to eat")

	local caster = indicatorData.caster

	indicatorData.eating = {}
	-- while eating, twist the head back and forth
	local head = caster.PrimaryPart
	-- on 2026-april-23 saw this be nil in the logs; not sure how
	if not head then
		return
	end

	local aimLeft = CFrame.fromAxisAngle(head.CFrame.UpVector, math.rad(10))
	local aimRight = CFrame.fromAxisAngle(head.CFrame.UpVector, math.rad(-10))

	indicatorData.eating.isLeft = true

	indicatorData.eating.leftCFrame = aimLeft * head.CFrame.Rotation + head.CFrame.Position
	indicatorData.eating.rightCFrame = aimRight * head.CFrame.Rotation + head.CFrame.Position

	local duration = 0.15
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)

	local goal = {}
	goal.CFrame = indicatorData.eating.leftCFrame

	indicatorData.eating.currentTween = tweenService:Create(head, tweenInfo, goal)

	local tweenCompletedFunc
	duration = duration * 2
	tweenCompletedFunc = function()
		indicatorData.eating.currentTween = nil
		indicatorData.eating.isLeft = not indicatorData.eating.isLeft
		--print("starting new head direction is left?", indicatorData.eating.isLeft)
		goal.CFrame = indicatorData.eating.isLeft and indicatorData.eating.leftCFrame or indicatorData.eating.rightCFrame
		indicatorData.eating.currentTween = tweenService:Create(head, tweenInfo, goal)
		indicatorData.eating.tweenCompletedConnect = indicatorData.eating.currentTween.Completed:Connect(tweenCompletedFunc)

		indicatorData.eating.currentTween:Play()
	end

	indicatorData.eating.tweenCompletedConnect = indicatorData.eating.currentTween.Completed:Connect(tweenCompletedFunc)

	indicatorData.eating.currentTween:Play()

	-- prepare for any spatial audio
	local dragonEatAudioParent: any = DragonEatAudioParent:Clone()
	dragonEatAudioParent.Name = "DragonEatAudioParent"
	dragonEatAudioParent:PivotTo(caster:GetPivot())
	dragonEatAudioParent.Anchored = true
	dragonEatAudioParent.Parent = caster
	indicatorData.eating.dragonEatAudioParent = dragonEatAudioParent

	local audioDragonEat = dragonEatAudioParent:FindFirstChild("AudioDragonEat")
	local audioDragonEatPitchShifter = dragonEatAudioParent:FindFirstChild("AudioPitchShifter")

	if audioPitchShift == 1 then
		audioDragonEatPitchShifter.Bypass = true
		audioDragonEatPitchShifter.Pitch = 1
	else
		audioDragonEatPitchShifter.Bypass = false
		audioDragonEatPitchShifter.Pitch = audioPitchShift
	end

	audioDragonEat.Looping = true
	audioDragonEat:Play()

end

function ClientDragonManager.cleanupAnimateEat(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("cleaning up eating")

	if not indicatorData.eating then
		return
	end

	if indicatorData.eating.tweenCompletedConnect then
		indicatorData.eating.tweenCompletedConnect:Disconnect()
		indicatorData.eating.tweenCompletedConnect = nil
	end

	if indicatorData.eating.currentTween then
		indicatorData.eating.currentTween:Cancel()
		indicatorData.eating.currentTween = nil
	end

	local dragonEatAudioParent = indicatorData.eating.dragonEatAudioParent
	if dragonEatAudioParent then
		local audioDragonEat = dragonEatAudioParent:FindFirstChild("AudioDragonEat")
		if audioDragonEat then
			audioDragonEat.Looping = false -- don't play again, but let current one finish
		end
		game:GetService("Debris"):AddItem(dragonEatAudioParent, 5) -- destroy after 5s
	end

	indicatorData.eating = nil
end

function ClientDragonManager.beginAnimateHighlightFadeOut(self: ClientDragonManager, itemId: any, duration: any, color: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("starting to highlight fade out")

	local caster = indicatorData.caster

	local highlight = Instance.new("Highlight")
	highlight.Adornee = caster
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = color
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1

	local tween = tweenService:Create(highlight, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1})
	tween.Completed:Connect(
		function()
			highlight:Destroy()
		end
	)
	tween:Play()

	highlight.Parent = caster
end

function ClientDragonManager.cleanupAnimateHighlightFadeOut(self: ClientDragonManager, itemId: any)

end

function ClientDragonManager.beginAnimateMergeParticles(self: ClientDragonManager, itemId: any, burstCount: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster

	local mergePost: any = MergePost:Clone()
	mergePost:PivotTo(caster:GetPivot())
	mergePost.Parent = workspace

	mergePost:FindFirstChild("Burst"):Emit(burstCount)
	utils.safelyDisposeOfParticleParent(mergePost)
end

function ClientDragonManager.cleanupAnimateMergeParticles(self: ClientDragonManager, itemId: any)

end

function ClientDragonManager.beginAnimateOpening(self: ClientDragonManager, itemId: any, crystalItemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster
	local shadow = indicatorData.shadow

	--print("dragon now opening", shadow, crystalItemId)

	local crystalObj: any = clientEventHandlers:getOrWaitForObject(crystalItemId)
	if not crystalObj then
		print("no crystal obj found for", crystalItemId)
		return
	end

	local crystalPart: any
	if crystalObj:IsA("Model") then
		crystalPart = crystalObj.PrimaryPart
		if not crystalPart then
			warn("crystal is a model with no primary part", crystalObj)
			return
		end
	else
		crystalPart = crystalObj
	end

	local dragonPart = caster.PrimaryPart
	if not dragonPart then
		-- this can happen if it was destroyed; race condition to recreate
		print("dragon caster is a model with no primary part", caster)
		return
	end

	--print("starting breath weapon")

	local primaryElement = shadow:GetAttribute(Attributes.PRIMARY_ELEMENT)

	local dragonBreathWeapon: any = DragonBreathWeapon:Clone()
	utils.setPropertyTreeClassName(dragonBreathWeapon, "Beam", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
	utils.setPropertyTreeClassName(dragonBreathWeapon, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
	local breathSource = dragonBreathWeapon:FindFirstChild("Source")
	local breathDest = dragonBreathWeapon:FindFirstChild("Destination")

	local dragonParticleEmitter: any = utils.findFirstDescendant(caster, "Particle_Emitter")
	breathSource.Position = dragonParticleEmitter.Position
	breathDest.Position = crystalObj:GetPivot().Position

	local sourceWeld = Instance.new("WeldConstraint")
	sourceWeld.Part0 = breathSource
	sourceWeld.Part1 = dragonPart
	sourceWeld.Parent = caster

	local destWeld = Instance.new("WeldConstraint")
	destWeld.Part0 = breathDest
	destWeld.Part1 = crystalPart
	destWeld.Parent = caster

	dragonBreathWeapon.Parent = caster
end

function ClientDragonManager.cleanupAnimateOpening(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster
	--local shadow = indicatorData.shadow

	--print("cleanup dragon opening", shadow)

	--print("removing any breath weapon")
	local dragonBreathWeapon = caster:FindFirstChild("DragonBreathWeapon")
	if dragonBreathWeapon then
		dragonBreathWeapon:Destroy()
	end
end

function ClientDragonManager.setupToAllowRiding(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

	-- find where the seat is
	local seatLocation = nil
	for _, descendant in caster:GetDescendants() do
		--print("have", caster, caster:GetAttribute(Attributes.SEAT_LOCATION))
		if not descendant:GetAttribute(Attributes.SEAT_LOCATION) then
			continue
		end

		seatLocation = descendant
		break
	end

	if not seatLocation then
		-- server should have checked this, should not be possible
		warn("Riding not available because no part with attribute", Attributes.SEAT_LOCATION, "found in", caster)
		return
	end

	indicatorData.seatLocation = seatLocation

	local weldConstraint = Instance.new("WeldConstraint")
	weldConstraint.Name = "SeatLocationToHeadWeld"
	weldConstraint.Part0 = seatLocation
	weldConstraint.Part1 = caster.PrimaryPart
	weldConstraint.Enabled = not shadow:GetAttribute(Attributes.CLIENT_CONTROL)
	--print("start weld head/body:", not shadow:GetAttribute(Attributes.CLIENT_CONTROL))
	weldConstraint.Parent = caster

	indicatorData.controlChangedConnect = shadow:GetAttributeChangedSignal(Attributes.CLIENT_CONTROL):Connect(
		function()
			--print("change weld head/body:", not shadow:GetAttribute(Attributes.CLIENT_CONTROL))
			weldConstraint.Enabled = not shadow:GetAttribute(Attributes.CLIENT_CONTROL)

			if clientRideController:getRidingObj() == shadow then
				local part = caster.primaryPart
				if not part then
					return
				end

				part.Anchored = not shadow:GetAttribute(Attributes.CLIENT_CONTROL)
			end

		end
	)

	collectionService:AddTag(caster, Tags.RIDABLE)
end

function ClientDragonManager.enableTrail(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster

	local trail: any = utils.findFirstDescendant(caster, "Trail")
	if not trail then
		return
	end

	trail.Enabled = true
end

function ClientDragonManager.disableTrail(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster

	local trail: any = utils.findFirstDescendant(caster, "Trail")
	if not trail then
		return
	end

	trail.Enabled = false
end


function ClientDragonManager.removeIndicators(self: ClientDragonManager, itemId: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.animationOpeningChangedConnect then
		indicatorData.animationOpeningChangedConnect:Disconnect()
		indicatorData.animationOpeningChangedConnect = nil
	end

	if indicatorData.animationChargeUpChangedConnect then
		indicatorData.animationChargeUpChangedConnect:Disconnect()
		indicatorData.animationChargeUpChangedConnect = nil
	end

	if indicatorData.animationMineNodeChangedConnect then
		indicatorData.animationMineNodeChangedConnect:Disconnect()
		indicatorData.animationMineNodeChangedConnect = nil
	end

	if indicatorData.animationEatChangedConnect then
		indicatorData.animationEatChangedConnect:Disconnect()
		indicatorData.animationEatChangedConnect = nil
	end

	if indicatorData.animationHighlightFadeOutConnect then
		indicatorData.animationHighlightFadeOutConnect:Disconnect()
		indicatorData.animationHighlightFadeOutConnect = nil
	end

	if indicatorData.animationMergeParticlesConnect then
		indicatorData.animationMergeParticlesConnect:Disconnect()
		indicatorData.animationMergeParticlesConnect = nil
	end

	if indicatorData.casterRecreatedEventConnect then
		indicatorData.casterRecreatedEventConnect:Disconnect()
		indicatorData.casterRecreatedEventConnect = nil
	end

	if indicatorData.runFlapConnect then
		indicatorData.runFlapConnect:Disconnect()
		indicatorData.runFlapConnect = nil
	end

	if indicatorData.flapDataConnect then
		indicatorData.flapDataConnect:Disconnect()
		indicatorData.flapDataConnect = nil
	end

	if indicatorData.runPulseConnect then
		indicatorData.runPulseConnect:Disconnect()
		indicatorData.runPulseConnect = nil
	end

	if indicatorData.runEnergyDecayConnect then
		indicatorData.runEnergyDecayConnect:Disconnect()
		indicatorData.runEnergyDecayConnect = nil
	end

	if indicatorData.controlChangedConnect then
		indicatorData.controlChangedConnect:Disconnect()
		indicatorData.controlChangedConnect = nil
	end

	if indicatorData.isRiding then
		self:cleanupRiding(itemId)
	end

	self:cleanupAnimateChargeUp(itemId)

	self:cleanupAnimateShootFireball(itemId)

	self:cleanupAnimateEat(itemId)

	self:cleanupAnimateHighlightFadeOut(itemId)

	self:cleanupAnimateMergeParticles(itemId)

	self.indicatorMap[itemId] = nil
end

function ClientDragonManager.configureIsClosest(self: ClientDragonManager, itemId: any, isClosest: any)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if not indicatorData.billboard then
		return
	end

	local billboard = indicatorData.billboard

	billboard.Enabled = isClosest
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientDragonManager.notifyNewInstance(self: ClientDragonManager, shadow: any, caster: any)
	--print("client dragon manager notify new instance", shadow, caster)

	local itemId = shadow:GetAttribute(Attributes.ITEM_ID)

	if self.indicatorMap[itemId] then
		print("already have dragon", shadow, itemId)
		return
	end

	local isOwnedByPlayer = shadow:GetAttribute(Attributes.USER_ID) == player.UserId

	self.indicatorMap[itemId] = {
		caster = caster,
		shadow = shadow,
		isOwnedByPlayer = isOwnedByPlayer,
	}

	local indicatorData = self.indicatorMap[itemId]

	indicatorData.animationOpeningChangedConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_OPENING):Connect(
		function()
			local crystalItemId = shadow:GetAttribute(Attributes.ANIMATION_OPENING)
			if crystalItemId then
				self:beginAnimateOpening(itemId, crystalItemId)
			else
				self:cleanupAnimateOpening(itemId)
			end

		end
	)
	if shadow:GetAttribute(Attributes.ANIMATION_OPENING) then
		local crystalItemId = shadow:GetAttribute(Attributes.ANIMATION_OPENING)
		self:beginAnimateOpening(itemId, crystalItemId)
	end

	if shadow:GetAttribute(Attributes.DRAGON_FLAP_DATA) then
		local flapDataStr = shadow:GetAttribute(Attributes.DRAGON_FLAP_DATA)
		local iterFunc = string.gmatch(flapDataStr, "%S+")

		self.indicatorMap[itemId].flapPeriod = tonumber(iterFunc())
		self.indicatorMap[itemId].flapAmplitude = tonumber(iterFunc())

		if clientOptionsManager:haveOptionsLoaded() and clientOptionsManager:getOption(PlayerOptionKeys.POTATO_MODE_ENABLED) then
			--print("not flapping due to potato mode", itemId)
		else
			self:setupFlappingWings(itemId)
		end
	end

	if clientOptionsManager:haveOptionsLoaded() and not clientOptionsManager:getOption(PlayerOptionKeys.POTATO_MODE_ENABLED) then
		self:setupIdlePulsing(itemId)
	end
	self:setupEnergyDecay(itemId)

	indicatorData.animationChargeUpChangedConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_CHARGE_UP):Connect(
		function()
			local animationChargeUpStr = shadow:GetAttribute(Attributes.ANIMATION_CHARGE_UP)
			if animationChargeUpStr then
				self:beginAnimateChargeUp(itemId)
			else
				self:cleanupAnimateChargeUp(itemId)
			end
		end
	)

	indicatorData.animationMineNodeChangedConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_SHOOT_FIREBALL):Connect(
		function()
			local animationMineNodeStr = shadow:GetAttribute(Attributes.ANIMATION_SHOOT_FIREBALL)
			if animationMineNodeStr then
				local iterFunc = string.gmatch(animationMineNodeStr, "%S+")

				local fireballPath = iterFunc()
				local x = tonumber(iterFunc())
				local y = tonumber(iterFunc())
				local z = tonumber(iterFunc())
				local destPosition = Vector3.new(x, y, z)
				--print("animate shoot fireball", fireballPath, destPosition)

				self:beginAnimateShootFireball(itemId, fireballPath, destPosition)
			else
				self:cleanupAnimateShootFireball(itemId)
			end
		end
	)

	indicatorData.animationEatChangedConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_EAT):Connect(
		function()
			local animationEatStr = shadow:GetAttribute(Attributes.ANIMATION_EAT)
			if animationEatStr then
				local iterFunc = string.gmatch(animationEatStr, "%S+")

				local audioPitchShift = tonumber(iterFunc())

				self:beginAnimateEat(itemId, audioPitchShift)
			else
				self:cleanupAnimateEat(itemId)
			end

		end
	)

	indicatorData.animationHighlightFadeOutConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_HIGHLIGHT_FADE_OUT):Connect(
		function()
			local animationHighlightFadeOutStr = shadow:GetAttribute(Attributes.ANIMATION_HIGHLIGHT_FADE_OUT)
			if animationHighlightFadeOutStr then
				-- was added to dragon later
				local iterFunc = string.gmatch(animationHighlightFadeOutStr, "%S+")

				local duration = tonumber(iterFunc())
				local red = tonumber(iterFunc())
				local green = tonumber(iterFunc())
				local blue = tonumber(iterFunc())
				local color = Color3.fromRGB(red, green, blue)

				self:beginAnimateHighlightFadeOut(itemId, duration, color)
			else
				self:cleanupAnimateHighlightFadeOut(itemId)
			end
		end
	)

	indicatorData.animationMergeParticlesConnect = shadow:GetAttributeChangedSignal(Attributes.ANIMATION_MERGE_PARTICLES):Connect(
		function()
			local animationMergeParticlesStr = shadow:GetAttribute(Attributes.ANIMATION_MERGE_PARTICLES)
			if animationMergeParticlesStr then
				-- have it from creation of dragon
				local iterFunc = string.gmatch(animationMergeParticlesStr, "%S+")

				local burstCount = tonumber(iterFunc())

				self:beginAnimateMergeParticles(itemId, burstCount)
			else
				self:cleanupAnimateMergeParticles(itemId)
			end
		end
	)

	do
		local animationHighlightFadeOutStr = shadow:GetAttribute(Attributes.ANIMATION_HIGHLIGHT_FADE_OUT)
		if animationHighlightFadeOutStr then
			-- have it from creation of dragon
			local iterFunc = string.gmatch(animationHighlightFadeOutStr, "%S+")

			local duration = tonumber(iterFunc())
			local red = tonumber(iterFunc())
			local green = tonumber(iterFunc())
			local blue = tonumber(iterFunc())
			local color = Color3.fromRGB(red, green, blue)

			self:beginAnimateHighlightFadeOut(itemId, duration, color)
		end
	end

	do
		local animationMergeParticlesStr = shadow:GetAttribute(Attributes.ANIMATION_MERGE_PARTICLES)
		if animationMergeParticlesStr then
			-- have it from creation of dragon
			local iterFunc = string.gmatch(animationMergeParticlesStr, "%S+")

			local burstCount = tonumber(iterFunc())

			self:beginAnimateMergeParticles(itemId, burstCount)
		end
	end

	indicatorData.casterRecreatedEventConnect = (clientShadowManager:getCasterRecreatedEvent(itemId) :: RBXScriptSignal):Connect(
		function(caster)
			indicatorData.caster = caster
			self:findBodyParts(itemId)
			if indicatorData.shadow:HasTag(Tags.RIDABLE) then
				self:setupToAllowRiding(itemId)
				if indicatorData.billboard then
					indicatorData.billboard.Adornee = indicatorData.seatLocation
				end
			end
		end
	)

	if not isOwnedByPlayer then
		--print("someone else's dragon was made", shadow, shadow:GetAttribute(Attributes.USER_ID))
		return
	end

	if shadow:HasTag(Tags.RIDABLE) then
		self:setupToAllowRiding(itemId)

		-- been seeing some billboards seemingly not showing up with this set to true as of 2026-february-28
		local areBillboardsClickable = true

		local billboard: any = RideDragonBillboard:Clone()
		if areBillboardsClickable then
			billboard.Adornee = self.indicatorMap[itemId].seatLocation
		end
		billboard.Enabled = false
		billboard:SetAttribute(Attributes.ITEM_ID, itemId) -- for debugging

		local button = billboard:FindFirstChild("RideButton")
		button.Activated:Connect(
			function()
				self:tryBeginRidingNearestDragon()
			end
		)
		indicatorData.billboard = billboard
		if areBillboardsClickable then
			billboard.Parent = player.PlayerGui
		else
			billboard.Parent = self.indicatorMap[itemId].seatLocation
		end

	end


end

function ClientDragonManager.notifyRemoveInstance(self: ClientDragonManager, shadow: any)
	local itemId = shadow:GetAttribute(Attributes.ITEM_ID)
	self:removeIndicators(itemId)
end

function ClientDragonManager.updatePotatoModeEnabled(self: ClientDragonManager)
	--print("update potato mode")
	if clientOptionsManager:getOption(PlayerOptionKeys.POTATO_MODE_ENABLED) then
		-- turn on potato mode / disable flapping, pulsing
		for itemId, indicatorData in self.indicatorMap do
			if indicatorData.runFlapConnect then
				--print("killing flapping for", itemId)
				indicatorData.runFlapConnect:Disconnect()
				indicatorData.runFlapConnect = nil
			end

			if indicatorData.flapDataConnect then
				indicatorData.flapDataConnect:Disconnect()
				indicatorData.flapDataConnect = nil
			end

			if indicatorData.runPulseConnect then
				indicatorData.runPulseConnect:Disconnect()
				indicatorData.runPulseConnect = nil
			end

			-- weld wings into place
			if indicatorData.parts and indicatorData.parts.isComplete then
				local weldConstraint
				weldConstraint = Instance.new("WeldConstraint")
				weldConstraint.Name = "potatoModeLeftWingWeld"
				weldConstraint.Part0 = indicatorData.parts.part
				weldConstraint.Part1 = indicatorData.parts.leftWing
				weldConstraint.Parent = indicatorData.caster

				weldConstraint = Instance.new("WeldConstraint")
				weldConstraint.Name = "potatoModeRightWingWeld"
				weldConstraint.Part0 = indicatorData.parts.part
				weldConstraint.Part1 = indicatorData.parts.rightWing
				weldConstraint.Parent = indicatorData.caster
			end

			indicatorData.caster:PivotTo(indicatorData.shadow:GetPivot())
		end
	else
		-- turn off potato mode / enable flapping, pulsing
		for itemId, indicatorData in self.indicatorMap do
			if not indicatorData.runFlapConnect then
				local potatoModeLeftWingWeld: any = utils.findFirstDescendant(indicatorData.caster, "potatoModeLeftWingWeld")
				if potatoModeLeftWingWeld then
					potatoModeLeftWingWeld:Destroy()
				end

				local potatoModeRightWingWeld: any = utils.findFirstDescendant(indicatorData.caster, "potatoModeRightWingWeld")
				if potatoModeRightWingWeld then
					potatoModeRightWingWeld:Destroy()
				end

				--print("no flap data for", itemId, "so setting up flapping now")
				local shadow = indicatorData.shadow
				if shadow:GetAttribute(Attributes.DRAGON_FLAP_DATA) then
					local flapDataStr = shadow:GetAttribute(Attributes.DRAGON_FLAP_DATA)
					local iterFunc = string.gmatch(flapDataStr, "%S+")

					self.indicatorMap[itemId].flapPeriod = tonumber(iterFunc())
					self.indicatorMap[itemId].flapAmplitude = tonumber(iterFunc())

					self:setupFlappingWings(itemId)
				end
			end

			if not indicatorData.runPulseConnect then
				self:setupIdlePulsing(itemId)
			end
		end
	end
end

function ClientDragonManager.getMapSize(self: ClientDragonManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientDragonManager.init(self: ClientDragonManager)

	collectionService:GetInstanceAddedSignal(Tags.SHADOW_DRAGON):Connect(
		function(inst: any)
			--print("new shadow dragon exists", inst)

			local shadow, caster

			local itemId = inst:GetAttribute(Attributes.ITEM_ID)
			if not clientShadowManager:isShadow(itemId) then
				-- shadow casters can be turned off, so this can happen
				return
			end

			shadow = inst
			caster = clientShadowManager:getCaster(itemId)

			self:notifyNewInstance(shadow, caster)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.SHADOW_DRAGON):Connect(
		function(shadow: any)
			--print("shadow dragon is gone", inst)
			self:notifyRemoveInstance(shadow)
		end
	)

	for _, shadow in collectionService:GetTagged(Tags.SHADOW_DRAGON) :: { any } do
		--print("existing shadow dragon exists", inst)

		local caster

		local itemId = shadow:GetAttribute(Attributes.ITEM_ID)
		if not clientShadowManager:isShadow(itemId) then
			-- race condition with client shadow manager which may not have processed the message yet. Let's give it another try
			task.defer(
				function()
					if not clientShadowManager:isShadow(itemId) then
						if shadow.Parent == workspace then
							warn("shadow dragon is not a shadow? Should not happen", shadow, itemId)
						else
							-- this is totally fine, it's an unequippable dragon in backpack, never to be visible
						end

						return
					end

					--print("successfully got a deferred-processed shadow dragon", itemId)

					caster = clientShadowManager:getCaster(itemId)

					self:notifyNewInstance(shadow, caster)
				end
			)

			continue
		end

		caster = clientShadowManager:getCaster(itemId)

		self:notifyNewInstance(shadow, caster)
	end

	runService.PostSimulation:Connect(
		function(deltaTime: number)
			-- find closest ridable item; only it can be ridden on jump
			local tool = utils.getHoldingToolWithHandle(player)
			local isToolEquipped = tool ~= nil
			local isRiding = clientRideController:isRiding()
			local bestItemId = nil
			local bestDistance = nil

			for itemId, indicatorData in self.indicatorMap do
				if not indicatorData.seatLocation then
					continue
				end
				if indicatorData.shadow.Parent ~= workspace then
					continue
				end
				if indicatorData.shadow:GetAttribute(Attributes.DRAGON_SLOT_INDEX) ~= nil then
					-- equipped in a stable slot: inert, cannot be ridden (RideMixin.canRideItem)
					continue
				end

				local playerPosition = (player.Character :: any).HumanoidRootPart.Position
				local seatPosition = indicatorData.seatLocation.Position
				-- this needs to match computation in RideMixin:canRideItem
				local distance = utils.getMagnitudeXZ(playerPosition - seatPosition)
				if not isRiding and not isToolEquipped and distance <= Constants.BEGIN_RIDE_DISTANCE then
					if not bestDistance or distance < bestDistance then
						bestItemId = itemId
						bestDistance = distance
					end
				end
			end

			-- no riding while trading
			if clientTradingManager:isTrading() then
				bestItemId = nil
			end

			if bestItemId then
				local stamina = self.indicatorMap[bestItemId].shadow:GetAttribute(Attributes.DRAGON_STAMINA)
				if stamina <= 0 then
					--print("closest ridable dragon has no stamina, not ridable")
					bestItemId = nil
				end
			end

			if bestItemId and clientRideController:isInRideBeginCooldown() then
				--print("closest ridable dragon is in ride begin cooldown, cannot ride yet")
				bestItemId = nil
			end

			for itemId, indicatorData in self.indicatorMap do
				local isClosest = (itemId == bestItemId)
				if isClosest then
					--print("have a ridable dragon", bestItemId)
				end

				self:configureIsClosest(itemId, isClosest)
			end
		end
	)

	userInputService.JumpRequest:Connect(
		function()
			-- from https://create.roblox.com/docs/reference/engine/classes/UserInputService#JumpRequest
			-- Since this event fires multiple times for a single jump request, using a debounce is recommended.

			--print("jump request")

			local nowTime = workspace:GetServerTimeNow()
			if nowTime - self.latestJumpRequestTime < JUMP_COOLDOWN_SEC then
				return
			end

			if clientRideController:isRiding() then
				local ridingObj = clientRideController:getRidingObj()
				local itemId = ridingObj:GetAttribute(Attributes.ITEM_ID)
				local indicatorData = self.indicatorMap[itemId]
				if indicatorData then
					clientRideController:tryEndRiding()
				end
			else
				if self:tryBeginRidingNearestDragon() then
					-- succeeded
				end
			end

			self.latestJumpRequestTime = nowTime
		end
	)

	--[[
		-- haven't found this useful yet
	(player.Character :: any).Humanoid.StateChanged:Connect(
		function (prevState, state)
			if state == Enum.HumanoidStateType.Jumping then
			end
		end
	)
	]]

end

function ClientDragonManager.new(): ClientDragonManager
	local self = setmetatable({} :: ClientDragonManagerFields, ClientDragonManager)

	self.indicatorMap = {}

	self.latestJumpRequestTime = workspace:GetServerTimeNow()

	return self
end

local singleton = ClientDragonManager.new()

return singleton
