--!strict

local ClientOpenableCrateManager = {}
ClientOpenableCrateManager.__index = ClientOpenableCrateManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
-- the effect templates' shapes only exist in Studio, so they are untyped here
local PackOpen: any = ParticleEffects:WaitForChild("PackOpen")
local Effects = GameAssets:WaitForChild("Effects")
local OpenedPackAudioParent: any = Effects:WaitForChild("OpenedPackAudioParent")
local OpeningPackAudioParent: any = Effects:WaitForChild("OpeningPackAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local ScaleToTween = require("@game/ReplicatedStorage/Shared/ScaleToTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")

local PROMPT_NAME = "OpenCrateProxPrompt"

local ACTIVATION_SEC = 1
local POP_OPEN_SEC = 0.2
local CANCEL_ACTIVATION_SEC = 0.5


local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	instance: any, -- world crate instance; its shape only exists at runtime
	prompt: ProximityPrompt?,
	anchor: BasePart?,
	highlight: Highlight?,
	runConnect: RBXScriptConnection?,
	isOpening: boolean,
	baseCFrame: CFrame?,
	baseScale: number?,
	baseLidCFrame: CFrame?,
	liftObj: any?,
	highlightTween: Tween?,
	sizeTween: Tween?,
	undoSizeTween: Tween?,
	liftTween: Tween?,
	lidTween: Tween?,
	undoLiftTween: Tween?,
	undoLidTween: Tween?,
	animationOpeningChangedConnect: RBXScriptConnection?,
}

type ClientOpenableCrateManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	openingItemId: number?,
	openingCrateAudioParent: any?,
}

export type ClientOpenableCrateManager = typeof(setmetatable({} :: ClientOpenableCrateManagerFields, ClientOpenableCrateManager))

function ClientOpenableCrateManager.removeIndicators(self: ClientOpenableCrateManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt:Destroy()
		indicatorData.prompt = nil
	end

	local anchor = indicatorData.anchor
	if anchor then
		anchor:Destroy()
		indicatorData.anchor = nil
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	local animationOpeningChangedConnect = indicatorData.animationOpeningChangedConnect
	if animationOpeningChangedConnect then
		animationOpeningChangedConnect:Disconnect()
		indicatorData.animationOpeningChangedConnect = nil
	end

	self.indicatorMap[itemId] = nil
end

function ClientOpenableCrateManager.configureIndicators(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- update proximity prompt

	local isOpening = indicatorData.isOpening
	local tool = utils.getHoldingToolWithHandle(player)
	local isToolEquipped = tool ~= nil
	local isRiding = clientRideController:isRiding()

	--print("updating with", indicatorData.isBeingClaimed, isToolEquipped, isRiding)

	-- set when the indicator is created; the cast records that
	local objProximityPrompt = indicatorData.prompt :: ProximityPrompt

	if isOpening or isToolEquipped or isRiding then
		objProximityPrompt.Enabled = false
	else
		objProximityPrompt.Enabled = true
	end

end

function ClientOpenableCrateManager.beginOpenCrate(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	local baseCFrame = inst:GetPivot() :: CFrame
	indicatorData.baseCFrame = baseCFrame
	--print("base", indicatorData.baseCFrame.Position)

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 1

	highlight.Parent = inst
	indicatorData.highlight = highlight

	local highlightTween = tweenService:Create(highlight, TweenInfo.new(ACTIVATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FillTransparency = 0})
	indicatorData.highlightTween = highlightTween
	highlightTween:Play()

	local baseScale = inst:GetScale() :: number
	indicatorData.baseScale = baseScale
	local tweenInfo = TweenInfo.new(ACTIVATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local sizeTween = ScaleToTween(inst, tweenInfo, baseScale * 0.9)
	indicatorData.sizeTween = sizeTween
	sizeTween:Play()

	local openingPackAudioParent = OpeningPackAudioParent:Clone()
	openingPackAudioParent.Position = baseCFrame.Position
	openingPackAudioParent.Parent = workspace

	local audioOpeningPack = openingPackAudioParent:FindFirstChild("AudioOpeningPack")
	audioOpeningPack:Play()

	self.openingCrateAudioParent = openingPackAudioParent

end

function ClientOpenableCrateManager.cancelOpenCrate(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local openingCrateAudioParent = self.openingCrateAudioParent
	if openingCrateAudioParent then
		openingCrateAudioParent:Destroy()
		self.openingCrateAudioParent = nil
	end

	local highlightTween = indicatorData.highlightTween
	if highlightTween then
		highlightTween:Cancel()
		indicatorData.highlightTween = nil
	end

	local liftTween = indicatorData.liftTween
	if liftTween then
		--print("canceling lift")
		liftTween:Cancel()
		indicatorData.liftTween = nil
	end

	local lidTween = indicatorData.lidTween
	if lidTween then
		--print("canceling lid")
		lidTween:Cancel()
		indicatorData.lidTween = nil
	end

	local sizeTween = indicatorData.sizeTween
	if sizeTween then
		--print("canceling size")
		sizeTween:Cancel()
		indicatorData.sizeTween = nil
	end

	local highlight = indicatorData.highlight
	if highlight then
		local tween = tweenService:Create(highlight, TweenInfo.new(CANCEL_ACTIVATION_SEC, Enum.EasingStyle.Linear), {FillTransparency = 1})
		indicatorData.highlightTween = tween
		tween.Completed:Connect(
			function(playbackState)
				indicatorData.highlightTween = nil
				if playbackState == Enum.PlaybackState.Cancelled then
					-- don't clean up/remove highlight, because we were terminated (happens when completeOpenCrate is called)
					return
				end

				local currentHighlight = indicatorData.highlight
				if currentHighlight then
					currentHighlight:Destroy()
					indicatorData.highlight = nil
				end
			end
		)
		tween:Play()
	end

	local baseScale = indicatorData.baseScale
	if baseScale then
		local tweenInfo = TweenInfo.new(CANCEL_ACTIVATION_SEC, Enum.EasingStyle.Linear)
		local undoSizeTween = ScaleToTween(inst, tweenInfo, baseScale)
		indicatorData.undoSizeTween = undoSizeTween
		undoSizeTween:Play()
	end
end

function ClientOpenableCrateManager.completeOpenCrate(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	indicatorData.isOpening = true

	-- cancel the "cancel" (undo) tweens
	local highlightTween = indicatorData.highlightTween
	if highlightTween then
		highlightTween:Cancel()
		indicatorData.highlightTween = nil
	end

	local undoSizeTween = indicatorData.undoSizeTween
	if undoSizeTween then
		undoSizeTween:Cancel()
		indicatorData.undoSizeTween = nil
	end

	local popOffsetVector = Vector3.new(0, 3, 0)

	-- lift the pack up

	local lid: any = utils.findFirstDescendant(inst, "Lid")
	if lid then
		indicatorData.baseLidCFrame = lid.CFrame
	end

	--print("starting to lift", newCFrame.Position)
	local tweenInfo = TweenInfo.new(POP_OPEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if lid then
		indicatorData.liftObj = utils.findFirstDescendant(inst, "Box")
	else
		indicatorData.liftObj = inst
	end
	local newCFrame = (indicatorData.liftObj :: any):GetPivot() + popOffsetVector

	local liftTween = PivotToTween(indicatorData.liftObj :: any, tweenInfo, newCFrame)
	indicatorData.liftTween = liftTween
	liftTween:Play()

	-- pop open the lid if there is one
	if lid then
		--disable welds so we can move the lid around on client
		utils.setPropertyTreeClassName(inst, "WeldConstraint", "Enabled", false)

		local attachment = lid:FindFirstChildOfClass("Attachment")

		local pivot = attachment.WorldCFrame :: CFrame

		local beginCFrame = lid.CFrame

		--print("pivot is", pivot)
		--print("beginCFrame is", beginCFrame)
		local rotation = CFrame.fromEulerAnglesXYZ(math.rad(90), 0, 0)
		local rotationAroundPivot = pivot * rotation * pivot:Inverse()
		--print("rotation around pivot is", rotationAroundPivot)
		local openCFrame = rotationAroundPivot * beginCFrame + popOffsetVector

		local lidTween = tweenService:Create(lid, TweenInfo.new(POP_OPEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = openCFrame})
		indicatorData.lidTween = lidTween
		lidTween:Play()
	end

	tweenInfo = TweenInfo.new(POP_OPEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local sizeTween = ScaleToTween(inst, tweenInfo, (indicatorData.baseScale :: number) * 1.2)
	sizeTween:Play()
	indicatorData.sizeTween = sizeTween

	self.openingItemId = itemId
	RemoteEvents.TryOpenCrate:FireServer(itemId)

end

function ClientOpenableCrateManager.beginAnimateOpening(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local packOpenParent = PackOpen:Clone()
	packOpenParent:PivotTo(inst:GetPivot())
	packOpenParent.Parent = workspace

	packOpenParent:FindFirstChild("Burst"):Emit(6)
	utils.safelyDisposeOfParticleParent(packOpenParent, 0.05)


	local openedPackAudioParent = OpenedPackAudioParent:Clone()
	openedPackAudioParent.Position = inst:GetPivot().Position
	openedPackAudioParent.Parent = workspace

	local audioOpenedPack = openedPackAudioParent:FindFirstChild("AudioOpenedPack")
	audioOpenedPack:Play()

	game:GetService("Debris"):AddItem(openedPackAudioParent, 5) -- destroy after 5s

end

function ClientOpenableCrateManager.cleanupAnimateOpening(self: ClientOpenableCrateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientOpenableCrateManager.notifyNewInstance(self: ClientOpenableCrateManager, inst: any)
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item is openable", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	-- there shouldn't be any, but just be safe...
	self:removeIndicators(inst)

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	--print("new instance--hooking to open", inst)

	-- note that these prompts won't work if the prompt is a child of a model and the model doesn't have a PrimaryPart

	local part
	if inst:IsA("Model") then
		part = inst.PrimaryPart
		if not part then
			warn("openable crate is a model with no primary part", inst)
			return
		end
	else
		part = inst
	end

	-- we create an anchor here so that the prompt doesn't move around when we animate the pack during Hold
	local anchor = Instance.new("Part")
	anchor.Name = "OpenCrateAnchor"
	anchor.CFrame = inst:GetPivot()
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = workspace

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 80)
	objProximityPrompt.ActionText = "Hold to Open"
	objProximityPrompt.HoldDuration = ACTIVATION_SEC
	objProximityPrompt.MaxActivationDistance = Constants.OPEN_CRATE_DISTANCE

	objProximityPrompt.Parent = anchor

	local runConnect = runService.PreSimulation:Connect(
		function(deltaTime)
			self:configureIndicators(itemId)
		end
	)

	self.indicatorMap[itemId] = {
		instance = inst,
		prompt = objProximityPrompt,
		anchor = anchor,
		highlight = nil,
		runConnect = runConnect,
		isOpening = false,
	}

	local indicatorData = self.indicatorMap[itemId]

	objProximityPrompt.PromptButtonHoldBegan:Connect(
		function(_player)
			--print("starting open pack")
			self:beginOpenCrate(itemId)
		end
	)
	objProximityPrompt.PromptButtonHoldEnded:Connect(
		function(_player)
			--print("ended open pack")
			self:cancelOpenCrate(itemId)
		end
	)
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to open pack", inst)
			self:completeOpenCrate(itemId)
		end
	)

	indicatorData.animationOpeningChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_OPENING):Connect(
		function()
			local animationOpeningStr = inst:GetAttribute(Attributes.ANIMATION_OPENING)
			if animationOpeningStr then
				self:beginAnimateOpening(itemId)
			else
				self:cleanupAnimateOpening(itemId)
			end
		end
	)


	self:configureIndicators(itemId)

end

function ClientOpenableCrateManager.notifyRemoveOpenableInstance(self: ClientOpenableCrateManager, inst: any)
	self:removeIndicators(inst)
end

function ClientOpenableCrateManager.notifyOpenCrateStatus(self: ClientOpenableCrateManager, isSuccess: boolean)
	--print("got open pack status", isSuccess)

	for itemId, indicatorData in self.indicatorMap do
		if not indicatorData.isOpening then
			continue
		end

		indicatorData.isOpening = false

		if not isSuccess then
			--print("need to undo some stuff about opening a pack")
			local inst = indicatorData.instance

			if indicatorData.liftObj then
				--print("undoing lift")
				local tweenInfo = TweenInfo.new(CANCEL_ACTIVATION_SEC, Enum.EasingStyle.Linear)
				local undoLiftTween = PivotToTween(indicatorData.liftObj, tweenInfo, indicatorData.baseCFrame :: CFrame)
				indicatorData.undoLiftTween = undoLiftTween
				undoLiftTween:Play()
			end

			local baseLidCFrame = indicatorData.baseLidCFrame
			if baseLidCFrame then
				--print("undoing lid")
				local lid: any = utils.findFirstDescendant(inst, "Lid")
				local tweenInfo = TweenInfo.new(CANCEL_ACTIVATION_SEC, Enum.EasingStyle.Linear)
				local undoLidTween = PivotToTween(lid, tweenInfo, baseLidCFrame)
				indicatorData.undoLidTween = undoLidTween
				undoLidTween:Play()
			end
		end

	end
end

function ClientOpenableCrateManager.getMapSize(self: ClientOpenableCrateManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientOpenableCrateManager.init(self: ClientOpenableCrateManager)

	collectionService:GetInstanceAddedSignal(Tags.OPENABLE_CRATE):Connect(
		function(inst)
			self:notifyNewInstance(inst)
			--print("new item can be opened", inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.OPENABLE_CRATE):Connect(
		function(inst)
			--print("item no longer openable", inst)
			self:notifyRemoveOpenableInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.OPENABLE_CRATE) do
		self:notifyNewInstance(inst)
		--print("existing item can be opened", inst)
	end

	clientRideController:getEvent():Connect(
		function(isRiding)
			--print("openable pack manager knows is riding", isRiding)
			for itemId, indicatorData in self.indicatorMap do
				self:configureIndicators(itemId)
			end
		end
	)
end

function ClientOpenableCrateManager.new(): ClientOpenableCrateManager
	local self = setmetatable({} :: ClientOpenableCrateManagerFields, ClientOpenableCrateManager)

	self.indicatorMap = {}

	self.openingItemId = nil

	return self
end


local singleton = ClientOpenableCrateManager.new()

return singleton
