--!strict

local runService = game:GetService("RunService")

local ClientMergeController = {}
ClientMergeController.__index = ClientMergeController

local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the templates' shapes only exist in Studio, so they are untyped here
local MergeAudioParent: any = Effects:WaitForChild("MergeAudioParent")
--local MergeSetupHaptic = Effects:WaitForChild("MergeSetupHaptic")
--local MergeCompleteHaptic = Effects:WaitForChild("MergeCompleteHaptic")
local UX = GameAssets:WaitForChild("UX")
local MergeBillboard: any = UX:WaitForChild("MergeBillboard")
local MergeComboBillboard: any = UX:WaitForChild("MergeComboBillboard")
local MergeMutationBillboard: any = UX:WaitForChild("MergeMutationBillboard")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientConsumableCropManager = require("./ClientConsumableCropManager")
local clientOptionsManager = require("./ClientOptionsManager")
local clientRideController = require("./ClientRideController")
local clientPlayerAnimationManager = require("./ClientPlayerAnimationManager")
local clientPlayerVariables = require("./ClientPlayerVariables")
local clientShadowManager = require("./ClientShadowManager")

local player = game:GetService("Players").LocalPlayer :: Player

local MERGE_TYPE_HOLDING = 1
local MERGE_TYPE_RIDING = 2

local MergeStatus = {
	NONE = 1,
	ACTIVATING = 2,
	DEACTIVATING = 3,
	WAITING_START = 4,
	IN_PROGRESS = 5,
}

local ACTIVATION_SEC = 1
local CANCEL_ACTIVATION_SEC = 0.5

local RING_EASE_SEC = 0.2
local HIGHLIGHT_FADE_SEC = 0.2

local ACTIVATION_CIRCLE_FRAC = 0.4
local BEAM_NORMAL_HEIGHT = 5
local BEAM_ACTIVATION_HEIGHT = 3

local RING_CENTER_NORMAL_TRANSPARENCY = 0.89
local RING_CENTER_ACTIVATION_TRANSPARENCY = 0.6

local TEXT_DURATION_SEC = 2.5
local TEXT_FADE_SEC = 1

local MUTATION_TEXT_DURATION_SEC = 2.5
local MUTATION_TEXT_FADE_SEC = 1

local COMBO_TEXT_MOVE_DURATION_SEC = Constants.MERGE_COMBO_GAP_SEC
local COMBO_TEXT_SIZE_DURATION_SEC = 1.5
local COMBO_TEXT_SIZE_PULSE_DURATION_SEC = 0.3
local COMBO_TEXT_FADE_SEC = 2

local COMBO_TEXT_SIZE_MULTIPLIER = 1.8


local function getCurveSizeForRadius(radius: number): number
	return radius * 4 / 3
end

type ClientMergeControllerFields = {
	activationCirclePosition: any,
	activationObjsData: { [any]: any },
	activationTweens: { [any]: any },
	allMergeCasters: { any }?,
	animateInOutTweens: { [any]: any },
	bestMutation: any,
	cancelActivationCoroutine: any,
	cancelActivationTweens: { [any]: any },
	comboData: any,
	debugBlock: any,
	event: BindableEvent,
	highlightCircle: any,
	highlightCircleMoveTween: any,
	highlightObjMap: { [any]: any },
	highlightTrigger: any,
	isInPlot: any,
	isMergeAll: any,
	isRemoving: boolean,
	mergeAllParticle: any,
	mergeAudioParent: any,
	mergeBestMutation: any,
	mergeCasters: any,
	mergeItemIds: any,
	mergeParticleParent: any,
	mergePrimaryElement: any,
	mergeRadius: any,
	mergeRadiusSquared: any,
	mergeStatus: any,
	mergeTriggerItemId: any,
	mergeType: any,
	prompt: any,
	totalMergeCount: any,
	triggerPart: any,
}

export type ClientMergeController = typeof(setmetatable({} :: ClientMergeControllerFields, ClientMergeController))

function ClientMergeController.addComboCountTextDisplay(self: ClientMergeController, count: any, position: any)
	local isReusingElements
	if self.comboData then
		for _, tween in self.comboData.tweens do
			tween:Cancel()
		end

		self.comboData.doneConnect:Disconnect()

		-- move the anchor to where the new merge happened
		tweenService:Create(self.comboData.anchor, TweenInfo.new(0.2), {CFrame = CFrame.new(position)}):Play()

		isReusingElements = true
	else
		local anchor = Instance.new("Part")
		anchor.Name = "MergeComboTextAnchor"
		anchor.CFrame = CFrame.new(position)
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.Anchored = true
		anchor.Parent = workspace

		local billboard: any = MergeComboBillboard:Clone()
		billboard.Name = "MergeComboBillboard"
		billboard.Adornee = anchor
		billboard.Size = UDim2.new(15 * 0.6, 0, 6 * 0.6, 0)

		self.comboData = {
			anchor = anchor,
			billboard = billboard,
			tweens = {},
			doneConnect = nil,
			waitStartCo = nil,
		}

		isReusingElements = false
	end

	local anchor = self.comboData.anchor
	local billboard = self.comboData.billboard

	local label = billboard:FindFirstChild("TextLabel")
	label.Text = string.format("COMBO x%i", count)
	label.TextTransparency = 0

	local uistroke = label:FindFirstChild("UIStroke")
	uistroke.Color = utils.getContrastingColor(label.TextColor3)
	uistroke.Transparency = 0

	billboard.Parent = workspace

	local sizeTween
	if isReusingElements then
		-- make it get bigger then smaller
		local sizeTweenInfo = TweenInfo.new(COMBO_TEXT_SIZE_PULSE_DURATION_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true)
		local sizeGoal = {Size = UDim2.new(15 * COMBO_TEXT_SIZE_MULTIPLIER, 0, 6 * COMBO_TEXT_SIZE_MULTIPLIER, 0)}
		sizeTween = tweenService:Create(billboard, sizeTweenInfo, sizeGoal)
		sizeTween:Play()
	else
		local sizeTweenInfo = TweenInfo.new(COMBO_TEXT_SIZE_DURATION_SEC, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		local sizeGoal = {Size = UDim2.new(15, 0, 6, 0)}
		sizeTween = tweenService:Create(billboard, sizeTweenInfo, sizeGoal)
		sizeTween:Play()
	end

	local moveTweenInfo = TweenInfo.new(COMBO_TEXT_MOVE_DURATION_SEC, Enum.EasingStyle.Linear)
	local startVec = billboard.studsOffset
	local moveGoal = {StudsOffset = startVec + Vector3.new(0, 1, 0)}
	local moveTween = tweenService:Create(billboard, moveTweenInfo, moveGoal)
	table.insert(self.comboData.tweens, moveTween)

	self.comboData.doneConnect = moveTween.Completed:Connect(
		function()
			--print("destroying merge billboard")
			billboard:Destroy()
			anchor:Destroy()

			self.comboData = nil
		end
	)

	moveTween:Play()

	local tweenInfo = TweenInfo.new(COMBO_TEXT_FADE_SEC, Enum.EasingStyle.Quad,	Enum.EasingDirection.Out, 1, false, COMBO_TEXT_MOVE_DURATION_SEC - COMBO_TEXT_FADE_SEC)
	local goal: { [string]: any } = {TextTransparency = 1}
	local tween
	tween = tweenService:Create(label, tweenInfo, goal)
	table.insert(self.comboData.tweens, tween)
	tween:Play()

	goal = {Transparency = 1}
	tween = tweenService:Create(uistroke, tweenInfo, goal)
	table.insert(self.comboData.tweens, tween)
	tween:Play()

end

function ClientMergeController.addBigMergeTextDisplay(self: ClientMergeController, primaryElement: any, count: any, position: any)
	local anchor = Instance.new("Part")
	anchor.Name = "MergeTextAnchor"
	anchor.CFrame = CFrame.new(position)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = workspace

	local billboard: any = MergeBillboard:Clone()
	billboard.Name = "MergeBillboard"
	billboard.Adornee = anchor

	--local elementColor = utils.get2DColorForPrimaryElement(primaryElement)

	local label = billboard:FindFirstChild("TextLabel")
	label.TextColor3 = Color3.fromRGB(255, 255, 255)

	label.Text = string.format("FUSE %i", count)

	local uistroke = label:FindFirstChild("UIStroke")
	uistroke.Color = utils.getContrastingColor(label.TextColor3)

	billboard.Parent = workspace

	local moveTweenInfo = TweenInfo.new(
		TEXT_DURATION_SEC,
		Enum.EasingStyle.Linear
		--Enum.EasingStyle.Exponential,
		--Enum.EasingDirection.Out
	)
	local moveGoal = {StudsOffset = Vector3.new(0, 6, 0)}
	local moveTween = tweenService:Create(billboard, moveTweenInfo, moveGoal)

	moveTween.Completed:Connect(
		function()
			--print("destroying merge billboard")
			billboard:Destroy()
			anchor:Destroy()
		end
	)

	moveTween:Play()

	local fadeTweenInfo = TweenInfo.new(
		TEXT_FADE_SEC,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		1,
		false,
		TEXT_DURATION_SEC - TEXT_FADE_SEC
	)
	local fadeGoal: { [string]: any } = {TextTransparency = 1}
	local tween
	tween = tweenService:Create(label, fadeTweenInfo, fadeGoal)
	tween:Play()

	fadeGoal = {Transparency = 1}
	tween = tweenService:Create(uistroke, fadeTweenInfo, fadeGoal)
	tween:Play()

end

function ClientMergeController.addMutationTextDisplay(self: ClientMergeController, mutation: any, position: any)
	local text = enums.getPublicName(enums.Mutations, mutation) :: string
	local richText = utils.getColoredTextForMutation(text, mutation)

	local anchor = Instance.new("Part")
	anchor.Name = "MergeMutationTextAnchor"
	anchor.CFrame = CFrame.new(position)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = workspace

	local billboard: any = MergeMutationBillboard:Clone()
	billboard.Name = "MergeMutationBillboard"
	billboard.Adornee = anchor

	local label = billboard:FindFirstChild("TextLabel")
	label.Text = richText

	local uistroke = label:FindFirstChild("UIStroke")
	uistroke.Color = utils.getContrastingColor(utils.getColorsForMutation(mutation)[1])

	billboard.Parent = workspace

	local moveTweenInfo = TweenInfo.new(
		MUTATION_TEXT_DURATION_SEC,
		Enum.EasingStyle.Linear
	)
	local moveGoal = {StudsOffset = Vector3.new(0, 3, 0)}
	local moveTween = tweenService:Create(billboard, moveTweenInfo, moveGoal)

	moveTween.Completed:Connect(
		function()
			--print("destroying merge mutation billboard")
			billboard:Destroy()
			anchor:Destroy()
		end
	)

	moveTween:Play()

	local fadeTweenInfo = TweenInfo.new(
		MUTATION_TEXT_FADE_SEC,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out,
		1,
		false,
		MUTATION_TEXT_DURATION_SEC - MUTATION_TEXT_FADE_SEC
	)
	local fadeGoal: { [string]: any } = {TextTransparency = 1}
	local tween
	tween = tweenService:Create(label, fadeTweenInfo, fadeGoal)
	tween:Play()

	fadeGoal = {Transparency = 1}
	tween = tweenService:Create(uistroke, fadeTweenInfo, fadeGoal)
	tween:Play()

end

function ClientMergeController.setRingAnimateIn(self: ClientMergeController)
	if #self.animateInOutTweens > 0 then
		for _, tween in self.animateInOutTweens do
			--print("in canceling a tween")
			tween:Cancel()
		end
	end

	self.isRemoving = false

	self.animateInOutTweens = {}

	local beam1 = self.highlightCircle:FindFirstChild("Beam1")
	local beam2 = self.highlightCircle:FindFirstChild("Beam2")

	local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")

	local particle = ringParticleParent:FindFirstChild("ParticleEmitter")
	particle.Enabled = true

	local tweenInfo = TweenInfo.new(
		RING_EASE_SEC,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
	local goal: { [string]: any } = {}
	goal.Width0 = BEAM_NORMAL_HEIGHT
	goal.Width1 = BEAM_NORMAL_HEIGHT
	local tween
	tween = tweenService:Create(beam1, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()
	tween = tweenService:Create(beam2, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()

	goal = {Transparency = RING_CENTER_NORMAL_TRANSPARENCY}
	tween = tweenService:Create(ringParticleParent, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()

	tween.Completed:Connect(
		function()
			--print("done animating in")
			self.animateInOutTweens = {}
		end
	)
end

function ClientMergeController.setRingAnimateOut(self: ClientMergeController, completionFunc: any)
	if #self.animateInOutTweens > 0 then
		for _, tween in self.animateInOutTweens do
			--print("out canceling a tween")
			tween:Cancel()
		end
	end

	self.animateInOutTweens = {}

	local beam1 = self.highlightCircle:FindFirstChild("Beam1")
	local beam2 = self.highlightCircle:FindFirstChild("Beam2")

	local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")

	local particle = ringParticleParent:FindFirstChild("ParticleEmitter")
	particle.Enabled = false

	local tweenInfo = TweenInfo.new(
		RING_EASE_SEC,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
	local goal: { [string]: any } = {}
	goal.Width0 = 0
	goal.Width1 = 0
	local tween
	tween = tweenService:Create(beam1, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()
	tween = tweenService:Create(beam2, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()

	goal = {Transparency = 1}
	tween = tweenService:Create(ringParticleParent, tweenInfo, goal)
	table.insert(self.animateInOutTweens, tween)
	tween:Play()

	tween.Completed:Connect(
		function()
			--print("done animating out")
			self.animateInOutTweens = {}
			completionFunc()
		end
	)
end

function ClientMergeController.removeMergeCircle(self: ClientMergeController)
	if self.isRemoving then
		return
	end

	if self.highlightCircle then
		self.isRemoving = true
		self:setRingAnimateOut(
			function ()
				self.isRemoving = false
				--print("destroying circle")
				self.highlightCircle:Destroy()
				self.highlightCircle = nil
			end
		)

	end
end

function ClientMergeController.createHighlightForObj(self: ClientMergeController, obj: any)
	local highlight = Instance.new("Highlight")

	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0

	highlight.Parent = obj

	tweenService:Create(highlight, TweenInfo.new(HIGHLIGHT_FADE_SEC), {OutlineTransparency = 0}):Play()

	local part
	if obj:IsA("Model") then
		part = obj.PrimaryPart
	else
		part = obj
	end

	self.highlightObjMap[obj] = {
		highlight = highlight,
		part = part,
		origTransparency = part.Transparency
	}
end

function ClientMergeController.removeHighlightForObj(self: ClientMergeController, obj: any)
	local highlightData = self.highlightObjMap[obj]
	local highlight = highlightData.highlight
	local origTransparency = highlightData.origTransparency
	local part = highlightData.part

	local tween = tweenService:Create(highlight, TweenInfo.new(HIGHLIGHT_FADE_SEC), {OutlineTransparency = 1})
	tween.Completed:Connect(
		function()
			part.Transparency = origTransparency
		end
	)
	tween:Play()

	self.highlightObjMap[obj] = nil
end

function ClientMergeController.removeHighlightTrigger(self: ClientMergeController)
	if not self.highlightTrigger then
		return
	end

	local highlight = self.highlightTrigger
	local tween = tweenService:Create(highlight, TweenInfo.new(HIGHLIGHT_FADE_SEC), {OutlineTransparency = 1})
	tween.Completed:Connect(
		function()
			highlight:Destroy()
		end
	)
	tween:Play()
	self.highlightTrigger = nil
end

function ClientMergeController.removeMergeHighlight(self: ClientMergeController)
	self:removeMergeCircle()

	for obj, _ in self.highlightObjMap do
		self:removeHighlightForObj(obj)
	end

	self:removeHighlightTrigger()

	self:endMergeAllAudio()
	self:endMergeAllParticle()

	self.prompt.Enabled = false

end

function ClientMergeController.createDebugBlock(self: ClientMergeController, position: any)
	if not self.debugBlock then
		-- Create a new Part instance
		self.debugBlock = Instance.new("Part")
		self.debugBlock.Name = "DebugBlock"
		self.debugBlock.Shape = Enum.PartType.Ball

		-- Set the size of the part
		self.debugBlock.Size = Vector3.new(1, 1, 1) -- A small 1x1x1 stud cube

		-- Set the color to a bright, noticeable color like red
		self.debugBlock.BrickColor = BrickColor.new("Really red")
		self.debugBlock.partMaterial = Enum.Material.Neon

		-- Make the part a transparent, non-colliding visual marker
		self.debugBlock.Transparency = 0.5
		self.debugBlock.CanCollide = false
		self.debugBlock.Anchored = true
	end

	-- Position the part using a CFrame (recommended for precise placement)
	self.debugBlock.CFrame = CFrame.new(position)

	-- Add the part to the workspace so it becomes visible
	self.debugBlock.Parent = workspace

end

function ClientMergeController.updateHighlightCircleSize(self: ClientMergeController)
	if not self.highlightCircle then
		return
	end

	local attachment1 = self.highlightCircle:FindFirstChild("Attachment1")
	attachment1.Position = Vector3.new(0, 0, self.mergeRadius)
	local attachment2 = self.highlightCircle:FindFirstChild("Attachment2")
	attachment2.Position = Vector3.new(0, 0, -self.mergeRadius)
	local beam1 = self.highlightCircle:FindFirstChild("Beam1")
	beam1.CurveSize0 = -getCurveSizeForRadius(self.mergeRadius)
	beam1.CurveSize1 = getCurveSizeForRadius(self.mergeRadius)

	local beam2 = self.highlightCircle:FindFirstChild("Beam2")
	beam2.CurveSize0 = getCurveSizeForRadius(self.mergeRadius)
	beam2.CurveSize1 = -getCurveSizeForRadius(self.mergeRadius)

	local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")
	-- the 0.3 is to make sure there's no gaps where it connects to the beams
	ringParticleParent.Size = Vector3.new(0.1, self.mergeRadius * 2 + 0.3, self.mergeRadius * 2 + 0.3)

end

function ClientMergeController.beginMergeAllAudio(self: ClientMergeController)
	--print("begin merge all audio")
	if (player.Character :: any):FindFirstChild("MergeAllIdleAudioParent") then
		return
	end

	--print("begin merge all audio creating one")

	local MergeAllIdleAudioParent: any = Effects:FindFirstChild("MergeAllIdleAudioParent")
	local audioParent: any = MergeAllIdleAudioParent:Clone()

	local audioMergeAllIdle = audioParent:FindFirstChild("AudioMergeAllIdle")
	audioMergeAllIdle.Looping = true
	audioMergeAllIdle:Play()

	audioParent.Parent = player.Character
end

function ClientMergeController.endMergeAllAudio(self: ClientMergeController)
	--print("end merge all audio")
	local audioParent = (player.Character :: any):FindFirstChild("MergeAllIdleAudioParent")
	if not audioParent then
		return
	end
	--print("end merge all audio found one to destroy")

	audioParent:Destroy()
end

function ClientMergeController.beginMergeAllParticle(self: ClientMergeController, obj: any)
	--print("begin merge all particle")
	if self.mergeAllParticle then
		return
	end

	--print("begin merge all particle creating one")

	local MergeAllParticleParent: any = Effects:FindFirstChild("MergeAllParticleParent")
	local ParticleEmitter = MergeAllParticleParent:FindFirstChild("ParticleEmitter")
	local particleEmitter: any = ParticleEmitter:Clone()

	particleEmitter.Parent = obj

	self.mergeAllParticle = particleEmitter
end

function ClientMergeController.endMergeAllParticle(self: ClientMergeController)
	--print("end merge all particle")
	if not self.mergeAllParticle then
		return
	end
	--print("end merge all particle found one to destroy")

	utils.safelyDisposeOfParticle(self.mergeAllParticle)
	self.mergeAllParticle = nil
end

function ClientMergeController.setHighlightCircleToLocation(self: ClientMergeController, location: any)
	local position = utils.getGroundPositionForLocation(location)

	local prevPosition = nil

	-- get the player's current merge radius
	self:updateMergeRadius()

	if self.highlightCircle then
		prevPosition = self.highlightCircle.Position
	else
		--print("cloning highlight")
		local CircleHighlight: any = Effects:FindFirstChild("CircleHighlight")
		self.highlightCircle = CircleHighlight:Clone()

		-- see https://www.youtube.com/watch?v=pq9-MLk9QQU to understand this thing

		self:updateHighlightCircleSize()

		local beam1 = self.highlightCircle:FindFirstChild("Beam1")
		beam1.Width0 = 0
		beam1.Width1 = 0

		local beam2 = self.highlightCircle:FindFirstChild("Beam2")
		beam2.Width0 = 0
		beam2.Width1 = 0

		local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")

		ringParticleParent.Transparency = 1

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = self.highlightCircle
		weld.Part1 = ringParticleParent
		weld.Parent = self.highlightCircle

		self:setRingAnimateIn()

		local audioMergeAvailable = self.highlightCircle:FindFirstChild("AudioMergeAvailable")
		audioMergeAvailable:Play()

		local audioMergeIdle = self.highlightCircle:FindFirstChild("AudioMergeIdle")
		audioMergeIdle.Looping = true
		audioMergeIdle:Play()

		self.highlightCircle.Parent = workspace
	end

	if self.highlightCircleMoveTween then
		self.highlightCircleMoveTween:Cancel()
	end

	if not prevPosition or (position - self.highlightCircle.Position).Magnitude < 1 then
		-- just teleport there
		self.highlightCircle.CFrame = self.highlightCircle.CFrame.Rotation + position
	else
		local duration = 0.1
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear
		)

		local goal: { [string]: any } = {}
		goal.CFrame = self.highlightCircle.CFrame.Rotation + position

		self.highlightCircleMoveTween = tweenService:Create(self.highlightCircle, tweenInfo, goal)
		self.highlightCircleMoveTween.Completed:Connect(
			function ()
				self.highlightCircleMoveTween = nil
			end
		)
		self.highlightCircleMoveTween:Play()
	end

	--self:createDebugBlock(position)
end

function ClientMergeController.setHighlightTriggerObj(self: ClientMergeController, triggerObj: any)
	if self.highlightTrigger then
		return
	end

	local adornee
	local triggerItemId = triggerObj:GetAttribute(Attributes.ITEM_ID)
	if clientShadowManager:isShadow(triggerItemId) then
		-- held or riding dragons should get here as of 2026-february-21
		-- triggerObj is the shadow of the item, get the caster
		adornee = clientShadowManager:getCaster(triggerItemId)
	else
		-- anything held is a part--probably want its parent which is a tool
		-- this should be dragon eggs, crystals, and plants as of 2026-february-21
		if triggerObj.Parent:IsA("Tool") then
			adornee = triggerObj.Parent
		else
			-- I don't think this is possible as of 2026-february-21
			print("merge trigger obj is not a dragon but not parented by a tool? What is it?", triggerObj)
			adornee = triggerObj
		end

	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = adornee
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 1

	highlight.Parent = triggerObj

	tweenService:Create(highlight, TweenInfo.new(HIGHLIGHT_FADE_SEC), {OutlineTransparency = 0}):Play()

	self.highlightTrigger = highlight
end

function ClientMergeController.getInventoryItemIdsMatchingName(self: ClientMergeController, mergeName: any)
	local itemIds: { any } = {}
	for _, tool in (player :: any).Backpack:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end
		local part
		local handle = tool:FindFirstChild("Handle")
		if handle then
			part = handle
		end
		local unequippable = tool:FindFirstChild(Constants.UNEQUIPPABLE_NAME)
		if unequippable then
			part = unequippable
		end
		if not part then
			continue
		end

		-- ok, have part and obj. Now, filter
		if part:GetAttribute(Attributes.MERGE_ALL_NAME) ~= mergeName then
			continue
		end

		local itemId = part:GetAttribute(Attributes.ITEM_ID)

		table.insert(itemIds, itemId)
	end

	return itemIds
end

function ClientMergeController.getCountOfItemId(self: ClientMergeController, itemId: any): number
	local obj = utils.tryGetObjByPlayerAndItemId(player, itemId)
	local itemCount: number
	if obj then
		itemCount = obj:GetAttribute(Attributes.COUNT) :: number
	else
		itemCount = 1
	end

	return itemCount
end

function ClientMergeController.calculateCountOfItemIds(self: ClientMergeController, itemIds: any): number
	local totalCount = 0

	for _, itemId in itemIds do
		totalCount += self:getCountOfItemId(itemId)
	end

	return totalCount
end


function ClientMergeController.calculateInventoryCountOfName(self: ClientMergeController, mergeName: any)
	local totalCount = 0

	local checkTools = {}
	for _, tool in (player :: any).Backpack:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end
		table.insert(checkTools, tool)
	end

	for _, tool in (player.Character :: any):GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end
		table.insert(checkTools, tool)
	end

	for _, tool in checkTools do
		local part
		local handle = tool:FindFirstChild("Handle")
		if handle then
			part = handle
		end
		local unequippable = tool:FindFirstChild(Constants.UNEQUIPPABLE_NAME)
		if unequippable then
			part = unequippable
		end
		if not part then
			continue
		end

		local itemId = part:GetAttribute(Attributes.ITEM_ID)
		local obj = utils.tryGetObjByPlayerAndItemId(player, itemId)
		if not obj then
			warn("missing object for part", part)
			continue
		end

		-- ok, have part and obj. Now, filter
		if part:GetAttribute(Attributes.MERGE_ALL_NAME) ~= mergeName then
			continue
		end

		-- it matches--get the count
		local itemCount = obj:GetAttribute(Attributes.COUNT)

		--print("found matching item in inventory", itemId, tool, part, obj, itemCount)

		totalCount += itemCount :: number

		-- held items already are counted for 1, so subtract that out
		if tool.Parent == player.Character then
			totalCount -= 1
		end
	end

	return totalCount
end

function ClientMergeController.run(self: ClientMergeController)

	-- the character rig's children only exist at runtime, so it is untyped here
	local character: any = player.Character
	if not character or not character.HumanoidRootPart or not self.isInPlot then
		self:removeMergeHighlight()
		return
	end

	if self.mergeStatus ~= MergeStatus.NONE then
		-- only one merge at a time
		return
	end

	-- check if player is holding something mergeable OR riding something mergeable

	local triggerObj: any = nil

	local toolPart: any
	local tool: any = utils.getHoldingToolWithHandle(player)
	if tool then
		toolPart = tool:FindFirstChild("Handle")
		--print("have names", toolObj:getAttribute(mergeAttributeName))

		triggerObj = toolPart
	end
	if not triggerObj then
		if clientRideController:isRidingAndControlling() then
			triggerObj = clientRideController:getRidingObj() :: any
			--print("riding obj is", triggerObj)
		end
	end

	-- even when doing merge all, check standard MERGE_NAME to see if the item is mergeable at all
	if not triggerObj or not triggerObj:GetAttribute(Attributes.MERGE_NAME) then
		self:removeMergeHighlight()
		return
	end

	local triggerItemId = triggerObj:GetAttribute(Attributes.ITEM_ID)

	local triggerPart

	if triggerObj:IsA("Model") then
		warn("client merge controller does not support models, shouldn't be possible")
	else
		-- carrying an object comes here, because tools can only have a part as a child

		-- riding a dragon comes here, because shadows are parts, not models
		triggerPart = triggerObj
	end

	self.isMergeAll = false
	local splendidDataFolder = player.PlayerGui:FindFirstChild("SplendidData")
	if splendidDataFolder then
		local playerFeaturesDataFolder = splendidDataFolder:FindFirstChild("PlayerFeatures")
		if playerFeaturesDataFolder and playerFeaturesDataFolder:GetAttribute(Attributes.IS_MERGE_ALL_UNLOCKED) then
			self.isMergeAll = clientOptionsManager:getOption(PlayerOptionKeys.MERGE_ALL_ENABLED)
		end
	end

	local mergeAttributeName
	if self.isMergeAll then
		mergeAttributeName = Attributes.MERGE_ALL_NAME
	else
		mergeAttributeName = Attributes.MERGE_NAME
	end

	-- as of 2026-august-12 this calls GetAttribute (lowercase getAttribute is not a member
	-- and would have thrown here)
	local mergeName = triggerPart:GetAttribute(mergeAttributeName)

	local triggerPosition = (triggerPart :: any).Position

	--print("player has mergeable object", mergeName)

	-- ok, player is holding something mergeable. We want to find the
	-- closest 2 items on the ground, owned by the player, that are close enough
	-- to potentially be merged.
	-- if this exists, then we want to draw a circle around them on the ground

	local matches: { any } = {}
	-- start by making list of items that could be merged, sorted by distance from player
	for _, part in collectionService:GetTagged(Tags.MERGEABLE) :: { any } do
		-- as of 2026-august-12 this calls GetAttribute (lowercase would have thrown)
		if mergeName ~= part:GetAttribute(mergeAttributeName) then
			continue
		end

		local partItemId = part:GetAttribute(Attributes.ITEM_ID)
		if partItemId == triggerItemId then
			continue
		end

		if part:GetAttribute(Attributes.USER_ID) ~= player.UserId then
			continue
		end

		local obj
		if part.Parent and part.Parent ~= workspace and part.Parent:IsA("Model") then
			obj = part.Parent
		else
			obj = part
		end

		if clientShadowManager:isShadow(partItemId :: number) then
			local caster = clientShadowManager:getCaster(partItemId :: number)
			--print("found potential merge caster", partItemId, caster)
			obj = caster
		end

		table.insert(matches,
			{
				obj = obj,
				part = part,
				distanceSquared = utils.getMagnitudeXZSquared(part.Position - triggerPosition),
			}
		)
		--print("mergeable matching our name", obj:GetAttribute(Attributes.ITEM_ID))
	end

	local inventoryItemIds = {}
	local inventoryCount = 0
	local extraCount = 0 -- when the trigger item is a number item you're holding, this is the rest of them
	if self.isMergeAll then
		inventoryItemIds = self:getInventoryItemIdsMatchingName(mergeName)
		inventoryCount = self:calculateCountOfItemIds(inventoryItemIds)
		extraCount = self:getCountOfItemId(triggerItemId) - 1

		-- don't need to look at distances for merge alls, so determine if it's valid now or not
		local potentialMergeCount = 1 + inventoryCount + extraCount + #matches
		if potentialMergeCount < 3 then
			--print("no matches in the plot")
			self:removeMergeHighlight()
			return
		end
	end

	table.sort(matches,
		function (a: any, b: any)
			return a.distanceSquared < b.distanceSquared
		end
	)

	--[[
	for i = 1, #matches do
		print("possible match", matches[i])
	end
	]]

	-- find the overall closest one to the player with another close-enough one (this might not be the actual closest CIRCLE to the player, but whatever)
	-- n^2 for now is kind of lame

	local bestIndex1: number? = nil
	local bestIndex2: number? = nil
	for i = 1, #matches do
		for j = i + 1, #matches do
			if self.isMergeAll or utils.getMagnitudeXZ(matches[i].part.Position - matches[j].part.Position) < 2 * self.mergeRadius then
				--print("FOUND CLOSE ONES", (matches[i].part.Position - matches[j].part.Position).Magnitude)
				bestIndex1 = i
				bestIndex2 = j
				break
			end
		end
		if bestIndex1 ~= nil then
			break
		end
	end

	if not self.isMergeAll and bestIndex1 == nil then
		--print("there's at least one match, but no pairs to make a 3rd")
		self:removeMergeHighlight()
		return
	end

	--print("closest pair", bestIndex1, matches[bestIndex1 :: number].distance, bestIndex2, matches[bestIndex2 :: number].distance)

	-- set position and size of highlight

	local circleCenter: any
	local readyToMerge = false
	local casters: { any } = {}
	if self.isMergeAll then
		-- add them all
		for _, match in matches do
			table.insert(casters, match.obj)
		end

		readyToMerge = true
	else
		local radius = self.mergeRadius

		circleCenter = utils.findClosestContainedCircleCenterXZ(matches[bestIndex1 :: number].part.Position, matches[bestIndex2 :: number].part.Position, triggerPosition, radius)

		--local midpoint = (matches[bestIndex1 :: number].part.Position + matches[bestIndex2 :: number].part.Position) / 2
		--print("got position", position, "midpoint is", midpoint, "player at", triggerPosition)

		if not circleCenter then
			--print("no position computed")
			self:removeMergeHighlight()
			return
		end

		-- determine if player is within merge area and hence ready to merge
		local triggerToCircleVector = triggerPosition - circleCenter
		--print("circle center is", circleCenter, "trigger dist", utils.getMagnitudeXZ(triggerToCircleVector))

		casters = {matches[bestIndex1 :: number].obj, matches[bestIndex2 :: number].obj}

		readyToMerge = (utils.getMagnitudeXZSquared(triggerToCircleVector) <= self.mergeRadiusSquared)

		-- if player is within the circle, then we want find a circle that contains 2 more of the objects if possible
		-- also, want to have a more "central" circle
		if readyToMerge then
			circleCenter = utils.calculateCentroidXZ(triggerPosition, matches[bestIndex1 :: number].part.Position, matches[bestIndex2 :: number].part.Position)

			-- USE_SMART_CIRCLES is an expensive calculation to find a circle enclosing the maximum amount of the mergeable items that still encloses the trigger item
			-- if false, we just grab everything within our _current_ circle--much cheaper
			local USE_SMART_CIRCLES = true
			if USE_SMART_CIRCLES then
				-- we see if there are other circles that could contain more matches, probably, at least to try to do a match 5...

				local matchingPositions = {triggerPosition, matches[bestIndex1 :: number].part.Position, matches[bestIndex2 :: number].part.Position}

				-- ok, we have a circle containing 2 non-trigger items. They may or may not be the closest individuals to the trigger
				-- plan: remove the two matches we're using from the array and re-sort matches based on distance from current circleCenter
				-- take each additional next-closest object, get minimum enclosing circle, and stop when the minimum radius is larger than merge radius
				table.remove(matches, bestIndex2 :: number)
				table.remove(matches, bestIndex1 :: number)
				table.sort(matches,
					function (a, b)
						return utils.getMagnitudeXZSquared(a.part.Position - circleCenter) < utils.getMagnitudeXZSquared(b.part.Position - circleCenter)
					end
				)

				local countCalculations = 0

				-- old linear scan
				--[[
					local additionalToInclude = 0
					local positions = table.clone(matchingPositions)
					-- this is a linear search here--should binary search instead and it'd be a lot faster
					for i = 1, #matches do
					table.insert(positions, matches[i].part.Position)
					local enclosingCircle = utils.getSmallestEnclosingCircleXZ(positions)
					if enclosingCircle.radius > self.mergeRadius then
					break
					end
					additionalToInclude = i
					circleCenter = enclosingCircle.center
					end
				]]

				-- new binary search
				local additionalToInclude = 0

				local low = 1
				local high = #matches
				while low <= high do
					local mid = math.floor((low + high) / 2)

					-- Build the positions array for the current midpoint
					local positions = table.clone(matchingPositions)
					for i = 1, mid do
						table.insert(positions, matches[i].part.Position)
					end

					countCalculations += 1
					local enclosingCircle = utils.getSmallestEnclosingCircleXZ(positions)

					if enclosingCircle.radius < self.mergeRadius then
						-- The radius is within the limit, so this number of matches works.
						-- Record the valid state, then search the upper half to see if we can fit more.
						additionalToInclude = mid
						circleCenter = enclosingCircle.center
						low = mid + 1
					else
						-- The radius exceeded the limit, so we included too many matches.
						-- Search the lower half.
						high = mid - 1
					end
				end

				if additionalToInclude > 0 then
					--print("found more to include", additionalToInclude, countCalculations, circleCenter)
					for i = 1, additionalToInclude do
						table.insert(casters, matches[i].obj)
					end
				end
			else
				-- any other matches that are within our merge circle become part of the merge too

				for _, match in matches do
					local distanceSquared = utils.getMagnitudeXZSquared(circleCenter - match.part.Position)
					if distanceSquared > self.mergeRadiusSquared then
						break
					end

					table.insert(casters, match.obj)
				end
			end

		end
	end

	-- add/update highlight of mergeable objects
	--[[
		-- used to do this
		local distance = utils.getMagnitudeXZ(triggerPosition - circleCenter)
		local fillTransparency = 0 + (math.max(0, distance - self.mergeRadius) / (self.mergeRadius * 2)) * 0.75
	]]

	-- un-highlight any obj that shouldn't be highlighted any longer
	for obj, _ in self.highlightObjMap do
		local shouldHighlight = false
		for _, highlightObj in casters do
			if obj == highlightObj then
				shouldHighlight = true
			end
		end
		if shouldHighlight then
			continue
		end

		self:removeHighlightForObj(obj)
	end

	-- create or update highlights for objs that should be highlighted
	for _, caster in casters do
		if not self.highlightObjMap[caster] then
			self:createHighlightForObj(caster)
		end
	end

	local promptParent = triggerPart
	local hold: any = utils.findFirstDescendant(triggerPart, "Hold")
	if hold then
		promptParent = hold
	else
		promptParent = triggerPart
	end

	if self.isMergeAll then
		self:removeMergeCircle()
		self:beginMergeAllAudio()
		self:beginMergeAllParticle(triggerPart)
	else
		self:setHighlightCircleToLocation(circleCenter)
		self:endMergeAllAudio()
		self:endMergeAllParticle()

	end

	local totalMergeCount = math.min(Constants.MERGE_ALL_MAX_COUNT, 1 + inventoryCount + extraCount + #casters)

	self.prompt.Enabled = readyToMerge
	--print("have merge counts 1", #casters, inventoryCount, extraCount)
	self.prompt.ActionText = string.format("Hold to Fuse %i", totalMergeCount)
	self.prompt.Parent = promptParent
	if readyToMerge then
		if triggerObj == toolPart then
			self.mergeType = MERGE_TYPE_HOLDING
		else
			self.mergeType = MERGE_TYPE_RIDING
		end

		-- as of 2026-august-12 this calls GetAttribute (lowercase would have thrown)
		self.mergePrimaryElement = triggerPart:GetAttribute(Attributes.PRIMARY_ELEMENT)
		self.mergeTriggerItemId = triggerItemId
		self.triggerPart = triggerPart
		-- mergeCasters is purely used for our animation purposes; for talking to the server, we use mergeItemIds
		-- so for shadow items, we swap out the objs (shadows) for the client-side rendering (casters)
		self.mergeCasters = casters
		self.allMergeCasters = utils.shallowCopy(self.mergeCasters)
		if clientShadowManager:isShadow(triggerItemId :: number) then
			local caster = clientShadowManager:getCaster(triggerItemId :: number)
			table.insert(self.allMergeCasters :: { any }, caster)
		else
			table.insert(self.allMergeCasters :: { any }, triggerObj)
		end

		self:setHighlightTriggerObj(triggerObj)
		local itemIds: { any } = {}
		for _, caster in casters do
			table.insert(itemIds, caster:GetAttribute(Attributes.ITEM_ID) :: any)
		end
		self.mergeItemIds = itemIds
		utils.arrayAppend(self.mergeItemIds, inventoryItemIds)
		self.totalMergeCount = totalMergeCount
	else
		self.mergeType = nil
		self.mergePrimaryElement = nil
		self.mergeTriggerItemId = nil
		self.triggerPart = nil
		self.mergeCasters = nil
		self.allMergeCasters = nil
		self.mergeItemIds = nil
		self.totalMergeCount = 0

		self:removeHighlightTrigger()
	end
end

function ClientMergeController.endMergeActivationEffects(self: ClientMergeController)
	if self.mergeParticleParent then
		utils.safelyDisposeOfParticleParent(self.mergeParticleParent, 0)
	end
end

function ClientMergeController.beginActivateMerge(self: ClientMergeController)
	self.mergeStatus = MergeStatus.ACTIVATING

	self.activationTweens = {}

	local activationCircleRadius = self.mergeRadius * ACTIVATION_CIRCLE_FRAC

	local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
	local MergePre = ParticleEffects:WaitForChild("MergePre")

	local particleParent: any = MergePre:Clone()
	particleParent:PivotTo(self.triggerPart.CFrame)
	particleParent.Parent = self.triggerPart

	self.mergeParticleParent = particleParent

	-- hide arrow while this is happening, if it's a crop
	for _, obj in self.mergeCasters do
		clientConsumableCropManager:notifyBeginMergeActivation(obj)
	end

	local tween

	-- fade items
	for _, highlightData in self.highlightObjMap do
		local highlight = highlightData.highlight
		local part = highlightData.part
		part.Transparency = 0
		tween = tweenService:Create(highlight, TweenInfo.new(ACTIVATION_SEC), {FillTransparency = 0})
		table.insert(self.activationTweens, tween)
		tween:Play()
	end
	tween = tweenService:Create(self.highlightTrigger, TweenInfo.new(ACTIVATION_SEC), {FillTransparency = 0})
	table.insert(self.activationTweens, tween)
	tween:Play()

	local destCFrame = self.triggerPart.CFrame

	if self.highlightCircle and not self.isMergeAll then
		self.activationCirclePosition = self.highlightCircle.Position

		local groundDestPosition = utils.getGroundPositionForLocation(destCFrame.Position)
		local groundDestCircleLocation = self.activationCirclePosition + (groundDestPosition - self.activationCirclePosition) * 0.8
		local groundDestCirclePosition = utils.getGroundPositionForLocation(groundDestCircleLocation)

		-- move circle and shrink it

		local highlightCircleGoal = {
			CFrame = self.highlightCircle.CFrame.Rotation + groundDestCirclePosition, -- maintain its orientation, just move position
			Size = Vector3.new(1, activationCircleRadius, activationCircleRadius),
		}
		tween = tweenService:Create(self.highlightCircle, TweenInfo.new(ACTIVATION_SEC), highlightCircleGoal)
		table.insert(self.activationTweens, tween)
		tween:Play()

		-- move attachments

		local attachment1 = self.highlightCircle:FindFirstChild("Attachment1")
		tween = tweenService:Create(attachment1, TweenInfo.new(ACTIVATION_SEC), {Position = Vector3.new(0, 0, activationCircleRadius)})
		table.insert(self.activationTweens, tween)
		tween:Play()

		local attachment2 = self.highlightCircle:FindFirstChild("Attachment2")
		tween = tweenService:Create(attachment2, TweenInfo.new(ACTIVATION_SEC), {Position = Vector3.new(0, 0, -activationCircleRadius)})
		table.insert(self.activationTweens, tween)
		tween:Play()

		-- raise height of the beams and shrink them

		local beam1 = self.highlightCircle:FindFirstChild("Beam1")

		local beam1Goal = {
			Width0 = BEAM_ACTIVATION_HEIGHT,
			Width1 = BEAM_ACTIVATION_HEIGHT,
			CurveSize0 = -getCurveSizeForRadius(activationCircleRadius),
			CurveSize1 = getCurveSizeForRadius(activationCircleRadius),
		}
		tween = tweenService:Create(beam1, TweenInfo.new(ACTIVATION_SEC), beam1Goal)
		table.insert(self.activationTweens, tween)
		tween:Play()

		local beam2 = self.highlightCircle:FindFirstChild("Beam2")
		local beam2Goal = {
			Width0 = BEAM_ACTIVATION_HEIGHT,
			Width1 = BEAM_ACTIVATION_HEIGHT,
			CurveSize0 = getCurveSizeForRadius(activationCircleRadius),
			CurveSize1 = -getCurveSizeForRadius(activationCircleRadius),
		}
		tween = tweenService:Create(beam2, TweenInfo.new(ACTIVATION_SEC), beam2Goal)
		table.insert(self.activationTweens, tween)
		tween:Play()

		-- partially solidify the circle

		local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")

		local ringGoal = {
			CFrame = ringParticleParent.CFrame.Rotation + groundDestCirclePosition, -- maintain its orientation, just move position
			Size = Vector3.new(0.01, 2 * activationCircleRadius + 0.2, 2 * activationCircleRadius + 0.2),
			Transparency = RING_CENTER_ACTIVATION_TRANSPARENCY,
		}
		tween = tweenService:Create(ringParticleParent, TweenInfo.new(ACTIVATION_SEC), ringGoal)
		table.insert(self.activationTweens, tween)
		tween:Play()
	end

	-- start moving merge items towards destination
	self.activationObjsData = {}

	for _, caster in self.mergeCasters do
		local part
		if caster:IsA("Model") then
			part = caster.PrimaryPart
		else
			part = caster
		end
		if not part then
			continue
		end

		-- save some info here in case we need to undo it (in cancel)
		self.activationObjsData[caster] = {
			canCollide = part.CanCollide,
			cframe = caster:GetPivot(),
		}

		utils.setPropertyTreeBaseParts(caster, "CanCollide", false)

		-- send the item in the world flying towards the held one it'll merge with
		local tweenInfo = TweenInfo.new(ACTIVATION_SEC)
		local objDestCFrame = part.CFrame.Rotation + destCFrame.Position -- maintain its orientation, just move position
		tween = PivotToTween(caster, tweenInfo, objDestCFrame)
		table.insert(self.activationTweens, tween)
		tween:Play()
	end

	for _, caster in self.allMergeCasters :: { any } do
		-- tell other systems what's going on--don't override our movements
		caster:SetAttribute(Attributes.MERGING, true)
	end

	local mergeAudioParent: any = MergeAudioParent:Clone()
	mergeAudioParent.Position = destCFrame.Position
	mergeAudioParent.Parent = workspace
	self.mergeAudioParent = mergeAudioParent

	local audioMergeEvent = mergeAudioParent:FindFirstChild("AudioMergeEvent")
	audioMergeEvent:Play()

	--local audioMergeEnd = mergeAudioParent:FindFirstChild("AudioMergeEnd")
	--audioMergeEnd:Play()

	if not clientRideController:isRiding() then
		-- player may have been running--stop that
		clientPlayerAnimationManager:stopWalkingRunningAnimations()
	end

	-- don't let player move, though if they jump this means they can be suspended in the air. That seems OK.
	-- this will also prevent a dragon that player is riding from moving, because they are welded together by the seat
	(player.Character :: any).HumanoidRootPart.Anchored = true

	local isMerging = true
	local isTrigger = true
	self.event:Fire(self.mergeTriggerItemId, isMerging, isTrigger)
	isTrigger = false
	for _, itemId in self.mergeItemIds do
		self.event:Fire(itemId, isMerging, isTrigger)
	end

	--MergeSetupHaptic:Play()

end

function ClientMergeController.cancelActivateMerge(self: ClientMergeController)
	-- sigh this happens even when it succeeds (the proximity prompt Triggered event happens directly after this)

	self.mergeStatus = MergeStatus.DEACTIVATING

	--MergeSetupHaptic:Stop()

	local characterRig: any = player.Character
	characterRig.HumanoidRootPart.Anchored = false

	self:endMergeActivationEffects()

	for _, tween in self.activationTweens do
		tween:Cancel()
	end

	self.cancelActivationTweens = {}

	local tween

	for _, highlightData in self.highlightObjMap do
		local highlight = highlightData.highlight
		local origTransparency = highlightData.origTransparency
		local part = highlightData.part
		tween = tweenService:Create(highlight, TweenInfo.new(CANCEL_ACTIVATION_SEC), {FillTransparency = 1})
		tween.Completed:Connect(
			function()
				part.Transparency = origTransparency
			end
		)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()
	end

	if self.highlightTrigger then
		tween = tweenService:Create(self.highlightTrigger, TweenInfo.new(CANCEL_ACTIVATION_SEC), {FillTransparency = 1})
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()
	end

	if self.highlightCircle and not self.isMergeAll then
		local highlightCircleGoal = {
			CFrame = self.highlightCircle.CFrame.Rotation +	self.activationCirclePosition, -- maintain its orientation, just move position
			Size = Vector3.new(1, self.mergeRadius, self.mergeRadius),
		}
		tween = tweenService:Create(self.highlightCircle, TweenInfo.new(CANCEL_ACTIVATION_SEC), highlightCircleGoal)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()

		local attachment1 = self.highlightCircle:FindFirstChild("Attachment1")
		tween = tweenService:Create(attachment1, TweenInfo.new(CANCEL_ACTIVATION_SEC), {Position = Vector3.new(0, 0, self.mergeRadius)})
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()

		local attachment2 = self.highlightCircle:FindFirstChild("Attachment2")
		tween = tweenService:Create(attachment2, TweenInfo.new(CANCEL_ACTIVATION_SEC), {Position = Vector3.new(0, 0, -self.mergeRadius)})
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()

		local beam1 = self.highlightCircle:FindFirstChild("Beam1")
		local beam1Goal = {
			Width0 = BEAM_NORMAL_HEIGHT,
			Width1 = BEAM_NORMAL_HEIGHT,
			CurveSize0 = -getCurveSizeForRadius(self.mergeRadius),
			CurveSize1 = getCurveSizeForRadius(self.mergeRadius),
		}
		tween = tweenService:Create(beam1, TweenInfo.new(CANCEL_ACTIVATION_SEC), beam1Goal)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()

		local beam2 = self.highlightCircle:FindFirstChild("Beam2")
		local beam2Goal = {
			Width0 = BEAM_NORMAL_HEIGHT,
			Width1 = BEAM_NORMAL_HEIGHT,
			CurveSize0 = getCurveSizeForRadius(self.mergeRadius),
			CurveSize1 = -getCurveSizeForRadius(self.mergeRadius),
		}
		tween = tweenService:Create(beam2, TweenInfo.new(CANCEL_ACTIVATION_SEC), beam2Goal)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()

		local ringParticleParent = self.highlightCircle:FindFirstChild("RingParticleParent")

		local ringGoal = {
			CFrame = ringParticleParent.CFrame.Rotation + self.activationCirclePosition, -- maintain its orientation, just move position
			Size = Vector3.new(0.01, self.mergeRadius * 2 + 0.3, self.mergeRadius * 2 + 0.3),
			Transparency = RING_CENTER_NORMAL_TRANSPARENCY,
		}
		tween = tweenService:Create(ringParticleParent, TweenInfo.new(CANCEL_ACTIVATION_SEC), ringGoal)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()
	end

	for _, caster in self.mergeCasters do
		local activationData = self.activationObjsData[caster]
		if not activationData then
			-- activationData was nil in prod on 2026-april-15
			continue
		end

		local tweenInfo = TweenInfo.new(CANCEL_ACTIVATION_SEC)
		local goal: { [string]: any } = {}
		goal.CFrame = activationData.cframe
		tween = PivotToTween(caster, tweenInfo, activationData.cframe)
		table.insert(self.cancelActivationTweens, tween)
		tween:Play()
	end

	if self.mergeAudioParent then
		self.mergeAudioParent:Destroy()
		self.mergeAudioParent = nil
	end

	self.cancelActivationCoroutine = task.delay(CANCEL_ACTIVATION_SEC,
		function()
			self.cancelActivationCoroutine = nil
			if self.mergeStatus ~= MergeStatus.DEACTIVATING then
				return
			end

			-- show nameplates again
			local isMerging = false
			self.event:Fire(self.mergeTriggerItemId, isMerging)
			for _, itemId in self.mergeItemIds do
				self.event:Fire(itemId, isMerging)
			end

			-- reset CanCollide for the object appropriately
			for _, caster in self.mergeCasters do
				caster:SetAttribute(Attributes.MERGING, nil)
				local activationData = self.activationObjsData[caster]
				if not activationData then
					-- activationData was nil in prod on 2026-april-16
					continue
				end

				utils.setPropertyTreeBaseParts(caster, "CanCollide", activationData.canCollide)
			end

			-- restore arrow while this is happening, if it's a crop
			for _, obj in self.mergeCasters do
				clientConsumableCropManager:notifyCancelMergeActivation(obj)
			end

			self.mergeStatus = MergeStatus.NONE

			self.activationObjsData = {}
		end
	)

end

function ClientMergeController.completeActivateMerge(self: ClientMergeController)
	self.mergeStatus = MergeStatus.WAITING_START

	if self.cancelActivationCoroutine then
		coroutine.close(self.cancelActivationCoroutine)
		self.cancelActivationCoroutine = nil
	end

	self.activationObjsData = {}

	for _, tween in self.cancelActivationTweens do
		tween:Cancel()
	end

	--MergeSetupHaptic:Stop()

	--MergeCompleteHaptic:Play()

	for _, caster in self.allMergeCasters :: { any } do
		caster:SetAttribute(Attributes.MERGING, true)
	end

	--print("client sending merge", self.mergeTriggerItemId, self.mergeItemIds, self.isMergeAll)

	if self.mergeType == MERGE_TYPE_HOLDING then
		RemoteEvents.TryMergeItemsWithHeldItem:FireServer(self.mergeTriggerItemId, self.mergeItemIds, self.isMergeAll)
	else
		RemoteEvents.TryMergeItemsWithRidingItem:FireServer(self.mergeTriggerItemId, self.mergeItemIds, self.isMergeAll)
	end
end

function ClientMergeController.notifyMergeBeginStatus(self: ClientMergeController, isSuccess: any, consecutiveMergeCount: any, bestMutation: any)
	self:removeMergeCircle()

	self:endMergeActivationEffects()

	if not isSuccess then
		self.mergeStatus = MergeStatus.NONE

		-- try to put everything back
		self:cancelActivateMerge()

		return
	end

	if consecutiveMergeCount >= 2 then
		local position = (player.Character :: any).HumanoidRootPart.Position
		self:addComboCountTextDisplay(consecutiveMergeCount, position)
	end

	if self.totalMergeCount >= 4 then
		local position = self.triggerPart.Position
		self:addBigMergeTextDisplay(self.mergePrimaryElement, self.totalMergeCount, position)
	end

	self.mergeBestMutation = bestMutation

	self.mergeStatus = MergeStatus.IN_PROGRESS
end

function ClientMergeController.notifyMergeEnd(self: ClientMergeController)
	self:removeHighlightTrigger()

	if self.mergeBestMutation ~= enums.Mutations.NORMAL then
		local position = self.triggerPart.Position
		self:addMutationTextDisplay(self.mergeBestMutation, position)
	end

	self.bestMutation = nil

	self.mergeStatus = MergeStatus.NONE
end

function ClientMergeController.getMergeStatusName(self: ClientMergeController): string?
	for key, value in MergeStatus :: { [string]: number } do
		if value ~= self.mergeStatus then
			continue
		end

		return key
	end

	return "UNKNOWN"
end

function ClientMergeController.notifyIsInPlot(self: ClientMergeController, isInPlot: any)
	self.isInPlot = isInPlot
end

function ClientMergeController.updateMergeRadius(self: ClientMergeController)
	self.mergeRadius = clientPlayerVariables:get(Attributes.MERGE_CIRCLE_RADIUS)
	self.mergeRadiusSquared = self.mergeRadius * self.mergeRadius

	if self.highlightCircle then
		self:updateHighlightCircleSize()
	end

end

function ClientMergeController.getMergeableCount(self: ClientMergeController)
	local mergeableObjs = collectionService:GetTagged(Tags.MERGEABLE)
	return #mergeableObjs
end

function ClientMergeController.getEvent(self: ClientMergeController)
	return self.event.Event
end

function ClientMergeController.isIdle(self: ClientMergeController)
	return self.mergeStatus == MergeStatus.NONE
end


function ClientMergeController.init(self: ClientMergeController)

	self:updateMergeRadius()

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.ActionText = ""
	objProximityPrompt.HoldDuration = ACTIVATION_SEC
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 40)

	objProximityPrompt.PromptButtonHoldBegan:Connect(
		function(player)
			--print("starting merge hold")

			self:beginActivateMerge()
		end
	)
	objProximityPrompt.PromptButtonHoldEnded:Connect(
		function(player)
			--print("ended merge hold")
			objProximityPrompt.Enabled = false

			self:cancelActivateMerge()
		end
	)
	objProximityPrompt.Triggered:Connect(
		function(player)
			--print("trying to merge")
			objProximityPrompt.Enabled = false

			self:completeActivateMerge()
		end
	)
	objProximityPrompt.Enabled = false

	self.prompt = objProximityPrompt

	-- we just put it here to not lose it I think? Not really sure as of 2026-january-27
	objProximityPrompt.Parent = player.Character or player.CharacterAdded:Wait()

	runService.PreRender:Connect(
		function()
			self:run()
		end
	)

	--[[
	-- Define the custom waveform with time (ms) and intensity (0-1)
	local rampUpWaveform = {
		FloatCurveKey.new(0, 0.2, Enum.KeyInterpolationMode.Linear), -- Start at 0ms, intensity 0.2
		FloatCurveKey.new(1000 * ACTIVATION_SEC, 1, Enum.KeyInterpolationMode.Constant)  -- At end, full intensity (1.0)
	}

	-- Apply the waveform to the effect
	MergeSetupHaptic:SetWaveformKeys(rampUpWaveform)
	]]

end

function ClientMergeController.new(): ClientMergeController
	local self = setmetatable({} :: ClientMergeControllerFields, ClientMergeController)

	self.isInPlot = false

	self.mergeType = nil -- MERGE_TYPE_HOLDING or MERGE_TYPE_HIDING
	self.isMergeAll = nil
	self.mergePrimaryElement = nil
	self.mergeTriggerItemId = nil
	self.triggerPart = nil
	self.mergeCasters = nil
	self.mergeItemIds = nil

	self.highlightCircle = nil
	self.highlightCircleMoveTween = nil
	self.animateInOutTweens = {}
	self.isRemoving = false
	self.highlightObjMap = {}
	self.highlightTrigger = nil

	self.event = Instance.new("BindableEvent")

	self.mergeStatus = MergeStatus.NONE

	self.comboData = nil

	return self
end


local singleton = ClientMergeController.new()

return singleton
