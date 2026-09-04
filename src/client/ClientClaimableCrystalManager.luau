--!strict

local ClientClaimableCrystalManager = {}
ClientClaimableCrystalManager.__index = ClientClaimableCrystalManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the template's shape only exists in Studio, so it is untyped here
local UnlockedIndicator: any = UX:WaitForChild("UnlockedIndicator")

-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientCrystalManager = require("./ClientCrystalManager")
local clientRideController = require("./ClientRideController")

local PROMPT_NAME = "ClaimProxPrompt"
local UNLOCKED_INDICATOR_NAME = "UnlockedIndicator"

local EXCLAMATION_PULSE_DURATION = 1
local EXCLAMATION_PULSE_AMPLITUDE = 1

local CLAIMABLE_BASE_HEIGHT = 3
local CLAIMABLE_PULSE_AMPLITUDE = 0.5

local HOLD_SEC = 1
local GLOW_SEC = 0.75
local JUMP_MAX_MAGNITUDE = 1
local JUMP_STEP_SEC = 0.05

local player = game:GetService("Players").LocalPlayer :: Player

-- this is only for the UI of crystals that THIS player owns and can control

type IndicatorData = {
	instance: any, -- world crystal instance; its shape only exists at runtime
	part: any,
	anchor: BasePart,
	prompt: ProximityPrompt,
	unlockedIndicator: any, -- UnlockedIndicator clone
	runConnect: RBXScriptConnection?,
	partTransparency: number,
	serverCFrame: CFrame?,
	floatingCFrame: CFrame?,
	pulseSec: number,
	riseTween: Tween?,
	isBeingClaimed: boolean,
	highlight: Highlight?,
	highlightTween: Tween?,
	shouldJump: boolean,
	jumpSec: number,
	jumpBaseCFrame: CFrame?,
}

type ClientClaimableCrystalManagerFields = {
	random: Random,
	indicatorMap: { [number]: IndicatorData },
}

export type ClientClaimableCrystalManager = typeof(setmetatable({} :: ClientClaimableCrystalManagerFields, ClientClaimableCrystalManager))

function ClientClaimableCrystalManager.removeIndicators(self: ClientClaimableCrystalManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	indicatorData.anchor:Destroy()
	indicatorData.prompt:Destroy()
	indicatorData.unlockedIndicator:Destroy()
	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
	end

	self.indicatorMap[itemId] = nil

end

function ClientClaimableCrystalManager.configureIndicators(self: ClientClaimableCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- update exclamation point

	if indicatorData.shouldJump or indicatorData.isBeingClaimed then
		utils.setPropertyTreeBaseParts(indicatorData.unlockedIndicator, "Transparency", 1)
	else
		utils.setPropertyTreeBaseParts(indicatorData.unlockedIndicator, "Transparency", 0)
	end

	-- update proximity prompt

	local tool = utils.getHoldingToolWithHandle(player)
	local isToolEquipped = tool ~= nil
	local isRiding = clientRideController:isRiding()

	--print("updating with", indicatorData.isBeingClaimed, isToolEquipped, isRiding)

	local objProximityPrompt = indicatorData.prompt

	if indicatorData.isBeingClaimed or isToolEquipped or isRiding then
		objProximityPrompt.Enabled = false
	else
		objProximityPrompt.Enabled = true
	end

end

function ClientClaimableCrystalManager.createHighlight(self: ClientClaimableCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- highlights don't work on parts that are semi-transparent, so we turn it off on the crystal
	local inst = indicatorData.instance
	local part = indicatorData.part

	part.Transparency = 0

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1

	highlight.Parent = inst
	local tween = tweenService:Create(highlight, TweenInfo.new(GLOW_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FillTransparency = 0})
	indicatorData.highlightTween = tween
	tween:Play()

	indicatorData.highlight = highlight
end

function ClientClaimableCrystalManager.run(self: ClientClaimableCrystalManager, deltaTime: number, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	if indicatorData.shouldJump then
		local prevJumpSec = indicatorData.jumpSec
		local jumpSec = prevJumpSec + deltaTime
		indicatorData.jumpSec = jumpSec
		if jumpSec // JUMP_STEP_SEC ~= prevJumpSec // JUMP_STEP_SEC then
			local factor = math.min(1, 0.5 + 0.5 * jumpSec)

			local jumpMagnitudeVector = self.random:NextNumber(0, 1) * (JUMP_MAX_MAGNITUDE * factor)
			local jumpOffset = Vector3.new(self.random:NextNumber(-1, 1), self.random:NextNumber(-1, 1), self.random:NextNumber(-1, 1)).Unit * jumpMagnitudeVector
			local position = (indicatorData.jumpBaseCFrame :: CFrame).Position + jumpOffset
			local cframe = (indicatorData.floatingCFrame :: CFrame).Rotation + position
			inst:PivotTo(cframe)
		end

		if prevJumpSec < HOLD_SEC - GLOW_SEC and jumpSec >= HOLD_SEC - GLOW_SEC then
			self:createHighlight(itemId)
		end

		return
	end
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientClaimableCrystalManager.notifyNewInstance(self: ClientClaimableCrystalManager, inst: any)
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item is claimable", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	-- there shouldn't be any, but just be safe...
	self:removeIndicators(inst)

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	--print("new instance--hooking to consume", inst)

	local part = utils.getMainPart(inst)
	if not part then
		warn("claimable crystal has no parts", inst)
		return
	end

	-- create invisible anchor for prompt since we will be moving the crystal
	local anchor = Instance.new("Part")
	anchor.Name = "CrystalPromptAnchor"
	anchor.CFrame = part.CFrame
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = workspace

	-- note that these prompts won't work if the prompt is a child of a model and the model doesn't have a PrimaryPart

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 80)
	objProximityPrompt.ActionText = "Hold to Break Crystal"
	objProximityPrompt.HoldDuration = HOLD_SEC
	objProximityPrompt.MaxActivationDistance = Constants.OPEN_CRYSTAL_DISTANCE

	-- parent it to our unmoving anchor
	objProximityPrompt.Parent = anchor

	-- setup the exclamation point
	local instHeight = utils.getInstanceHeight(inst)

	local unlockedIndicator = UnlockedIndicator:Clone()
	unlockedIndicator.Name = UNLOCKED_INDICATOR_NAME
	utils.setPropertyTreeBaseParts(unlockedIndicator, "Anchored", true)

	local unlockedIndicatorBottomY = anchor.Position.Y + CLAIMABLE_BASE_HEIGHT + CLAIMABLE_PULSE_AMPLITUDE + instHeight + math.max(3, instHeight * 0.15)
	local unlockedIndicatorTopY = unlockedIndicatorBottomY + EXCLAMATION_PULSE_AMPLITUDE * 2
	local unlockedPosition = Vector3.new(anchor.Position.X, unlockedIndicatorBottomY, anchor.Position.Z)
	local unlockedCFrame = CFrame.new(unlockedPosition) * CFrame.Angles(0, math.rad(90), 0)
	local unlockedTopPosition = Vector3.new(anchor.Position.X, unlockedIndicatorTopY, anchor.Position.Z)
	local topCFrame = CFrame.new(unlockedTopPosition) * CFrame.Angles(0, math.rad(90), 0)

	unlockedIndicator:PivotTo(unlockedCFrame)
	unlockedIndicator.Parent = workspace

	local duration = EXCLAMATION_PULSE_DURATION
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true, -- reverses afterwards
		0
	)

	PivotToTween(unlockedIndicator, tweenInfo, topCFrame):Play()

	local indicatorData: IndicatorData = {
		instance = inst,
		part = part,
		anchor = anchor,
		prompt = objProximityPrompt,
		unlockedIndicator = unlockedIndicator,
		runConnect = nil,
		partTransparency = part.Transparency,
		floatingCFrame = nil,
		pulseSec = 0,
		riseTween = nil,
		isBeingClaimed = false,
		highlight = nil,
		highlightTween = nil,
		shouldJump = false,
		jumpSec = 0,
	}
	self.indicatorMap[itemId] = indicatorData

	objProximityPrompt.PromptButtonHoldBegan:Connect(
		function(_player)
			--print("starting claim hold")
			local currentIndicatorData = self.indicatorMap[itemId]
			if not currentIndicatorData then
				return
			end
			local riseTween = currentIndicatorData.riseTween
			if riseTween then
				riseTween:Cancel()
				currentIndicatorData.riseTween = nil
			end
			currentIndicatorData.shouldJump = true
			currentIndicatorData.jumpBaseCFrame = inst:GetPivot()
			currentIndicatorData.jumpSec = 0
			clientCrystalManager:setClaimablePulseEnabled(itemId, false)

			local audioParent = inst:FindFirstChild("ClaimableCrystalAudioParent")
			if audioParent then
				local audioClaimingCrystal = audioParent:FindFirstChild("AudioClaimingCrystal")
				audioClaimingCrystal.TimePosition = 0
				audioClaimingCrystal:Play()
			else
				warn("claimable crystal missing audio parent")
			end

			part.CanCollide = false
		end
	)
	objProximityPrompt.PromptButtonHoldEnded:Connect(
		function(_player)
			--print("ended claim hold")
			local currentIndicatorData = self.indicatorMap[itemId]
			if not currentIndicatorData then
				return
			end
			currentIndicatorData.shouldJump = false

			inst:PivotTo(currentIndicatorData.floatingCFrame)
			clientCrystalManager:setClaimablePulseEnabled(itemId, true)
			currentIndicatorData.pulseSec = 0

			part.Transparency = currentIndicatorData.partTransparency
			part.CanCollide = true

			local audioParent = inst:FindFirstChild("ClaimableCrystalAudioParent")
			if audioParent then
				local audioClaimingCrystal = audioParent:FindFirstChild("AudioClaimingCrystal")
				audioClaimingCrystal:Stop()
			else
				warn("claimable crystal missing audio parent")
			end

		end
	)
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("triggered claim")
			local currentIndicatorData = self.indicatorMap[itemId]
			if not currentIndicatorData then
				return
			end
			currentIndicatorData.isBeingClaimed = true

			clientCrystalManager:setClaimablePulseEnabled(itemId, false)
			part.Transparency = 0
			part.CanCollide = false

			currentIndicatorData.shouldJump = true

			--print("sending server trying to claim", inst)
			RemoteEvents.TryClaimCrystal:FireServer(itemId)
		end
	)

	local runConnect = runService.PreSimulation:Connect(
		function(deltaTime)
			self:configureIndicators(itemId)
			self:run(deltaTime, itemId)
		end
	)
	indicatorData.runConnect = runConnect

	local cframe = inst:GetPivot() :: CFrame
	indicatorData.serverCFrame = cframe
	local floatingCFrame = cframe.Rotation + (cframe.Position + Vector3.new(0, CLAIMABLE_BASE_HEIGHT, 0))
	indicatorData.floatingCFrame = floatingCFrame

	self:configureIndicators(itemId)

end

function ClientClaimableCrystalManager.notifyRemoveClaimableInstance(self: ClientClaimableCrystalManager, inst: any)
	self:removeIndicators(inst)
end

function ClientClaimableCrystalManager.notifyClaimCrystalStatus(self: ClientClaimableCrystalManager, isSuccess: boolean)
	--print("got claim status result", isSuccess)
	for itemId, indicatorData in self.indicatorMap do
		if not indicatorData.isBeingClaimed then
			continue
		end

		local highlightTween = indicatorData.highlightTween
		if highlightTween then
			highlightTween:Destroy()
			indicatorData.highlightTween = nil
		end
		local highlight = indicatorData.highlight
		if highlight then
			highlight:Destroy()
			indicatorData.highlight = nil
		end

		local part = indicatorData.part
		if isSuccess then
			-- it was successful so we will be destroyed imminently... just try to make it look good here
			part.Transparency = 1
		else
			part.Transparency = indicatorData.partTransparency
			part.CanCollide = true

			clientCrystalManager:setClaimablePulseEnabled(itemId, true)
			indicatorData.pulseSec = 0

			indicatorData.isBeingClaimed = false
		end
	end

end

function ClientClaimableCrystalManager.getMapSize(self: ClientClaimableCrystalManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientClaimableCrystalManager.init(self: ClientClaimableCrystalManager)

	collectionService:GetInstanceAddedSignal(Tags.CLAIMABLE_CRYSTAL):Connect(
		function(inst)
			--print("new item can be claimed", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CLAIMABLE_CRYSTAL):Connect(
		function(inst)
			--print("item no longer claimable", inst)
			self:notifyRemoveClaimableInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CLAIMABLE_CRYSTAL) do
		--print("existing item can be claimed", inst)
		self:notifyNewInstance(inst)
	end

	clientRideController:getEvent():Connect(
		function(isRiding)
			--print("claimable crystal manager knows is riding", isRiding)
			for itemId, indicatorData in self.indicatorMap do
				self:configureIndicators(itemId)
			end
		end
	)
end

function ClientClaimableCrystalManager.new(): ClientClaimableCrystalManager
	local self = setmetatable({} :: ClientClaimableCrystalManagerFields, ClientClaimableCrystalManager)

	self.random = Random.new()

	self.indicatorMap = {}

	return self
end


local singleton = ClientClaimableCrystalManager.new()

return singleton
