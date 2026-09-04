--!strict

local ClientFirstSessionOfferManager = {}
ClientFirstSessionOfferManager.__index = ClientFirstSessionOfferManager

local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Fixtures = GameAssets:WaitForChild("Fixtures")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local screenGuiManager = require("./ScreenGuiManager")
local Teleporters = require("./Teleporters")
local Types = require("./Types")

local ACTIVATION_SEC = 1
local CANCEL_ACTIVATION_SEC = 0.5
local FADE_HIGHLIGHT_SEC = 2

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local FirstSessionReward: any = PlayerGui:WaitForChild("FirstSessionReward")

type ClientFirstSessionOfferManagerFields = {
	firstSessionOfferState: any, -- server-sent offer state
	dragonBalloon: any?, -- DragonBalloon clone
	balloonHighlight: Highlight?,
	balloonHighlightTween: Tween?,
	prompt: any?,
	runConnect: RBXScriptConnection?,
	ftueProgress: any?, -- never assigned today; kept for isFirstSessionOfferActive
}

export type ClientFirstSessionOfferManager = typeof(setmetatable({} :: ClientFirstSessionOfferManagerFields, ClientFirstSessionOfferManager))

function ClientFirstSessionOfferManager.getGuiRoot(self: ClientFirstSessionOfferManager): Instance
	return FirstSessionReward
end

function ClientFirstSessionOfferManager.notifyForceEnd(self: ClientFirstSessionOfferManager)
	self:cleanupDialog()
end

function ClientFirstSessionOfferManager.notifyClickOutside(self: ClientFirstSessionOfferManager)
	self:notifyForceEnd()
end

function ClientFirstSessionOfferManager.getHudElements(self: ClientFirstSessionOfferManager): { number }
	return {}
end

function ClientFirstSessionOfferManager.beginDialog(self: ClientFirstSessionOfferManager)
	local objProximityPrompt = utils.findFirstDescendant(self.dragonBalloon :: any, "ProximityPrompt") :: any
	objProximityPrompt.Enabled = false

	FirstSessionReward.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientFirstSessionOfferManager.cleanupDialog(self: ClientFirstSessionOfferManager)
	local objProximityPrompt = utils.findFirstDescendant(self.dragonBalloon :: any, "ProximityPrompt") :: any
	objProximityPrompt.Enabled = true

	FirstSessionReward.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientFirstSessionOfferManager.getFinalCFrame(self: ClientFirstSessionOfferManager): CFrame
	local plotCFrame = Teleporters:getPlotCFrame() :: CFrame

	local dragonBalloonTemplate: any = Fixtures:WaitForChild("DragonBalloon")

	local plotLocation = Vector3.new(self.firstSessionOfferState.plotLocation[1], 0, self.firstSessionOfferState.plotLocation[2])
	local cframe = plotCFrame.Rotation * CFrame.fromEulerAnglesXYZ(0, math.rad(90), 0) + (plotCFrame * plotLocation) + Vector3.new(0, dragonBalloonTemplate:GetPivot().Position.Y, 0)

	return cframe
end

function ClientFirstSessionOfferManager.beginActivateRedeem(self: ClientFirstSessionOfferManager)
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 1

	highlight.Parent = self.dragonBalloon
	self.balloonHighlight = highlight

	local highlightTween = tweenService:Create(highlight, TweenInfo.new(ACTIVATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {FillTransparency = 0})
	self.balloonHighlightTween = highlightTween
	highlightTween:Play()
end

function ClientFirstSessionOfferManager.cancelActivateRedeem(self: ClientFirstSessionOfferManager)
	local balloonHighlightTween = self.balloonHighlightTween
	if balloonHighlightTween then
		balloonHighlightTween:Cancel()
		self.balloonHighlightTween = nil
	end

	local balloonHighlight = self.balloonHighlight
	if balloonHighlight then
		local tween = tweenService:Create(balloonHighlight, TweenInfo.new(CANCEL_ACTIVATION_SEC, Enum.EasingStyle.Linear), {FillTransparency = 1})
		self.balloonHighlightTween = tween
		tween.Completed:Connect(
			function(playbackState)
				self.balloonHighlightTween = nil
				if playbackState == Enum.PlaybackState.Cancelled then
					-- don't clean up/remove highlight, because we were terminated (happens when completeOpenPack is called)
					return
				end

				local currentHighlight = self.balloonHighlight
				if currentHighlight then
					currentHighlight:Destroy()
					self.balloonHighlight = nil
				end

				(self.prompt :: any).Enabled = true
			end
		)
		tween:Play()
	end
end

function ClientFirstSessionOfferManager.setupPrompt(self: ClientFirstSessionOfferManager)
	local objProximityPrompt = utils.findFirstDescendant(self.dragonBalloon :: any, "ProximityPrompt") :: any
	self.prompt = objProximityPrompt

	-- begin hold
	objProximityPrompt.PromptButtonHoldBegan:Connect(
		function(_player: Player)
			--print("starting redeem hold")

			self:beginActivateRedeem()
		end
	)
	objProximityPrompt.PromptButtonHoldEnded:Connect(
		function(_player: Player)
			--print("ended redeem hold")
			objProximityPrompt.Enabled = false

			self:cancelActivateRedeem()
		end
	)

	objProximityPrompt.Triggered:Connect(
		function()
			if self.firstSessionOfferState.state == enums.FirstSessionOfferState.REDEEMABLE then
				-- cancel the "cancel" (undo) tweens
				local balloonHighlightTween = self.balloonHighlightTween
				if balloonHighlightTween then
					balloonHighlightTween:Cancel()
					self.balloonHighlightTween = nil
				end

				RemoteEvents.TryRedeemFirstSessionOffer:FireServer()
			else
				self:beginDialog()
			end
		end
	)
end

function ClientFirstSessionOfferManager.animateBalloonIn(self: ClientFirstSessionOfferManager)
	if self.dragonBalloon then
		return
	end

	local dragonBalloonTemplate: any = Fixtures:WaitForChild("DragonBalloon")
	local dragonBalloon = dragonBalloonTemplate:Clone()
	local balloon = dragonBalloon:FindFirstChild("Balloon")
	utils.setPropertyTreeBaseParts(balloon, "Anchored", true)

	self.dragonBalloon = dragonBalloon

	self:setupPrompt()

	local finalCFrame = self:getFinalCFrame()
	local cframe = finalCFrame + Vector3.new(0, 50, 0)
	dragonBalloon:PivotTo(cframe)

	dragonBalloon.Parent = workspace

	finalCFrame = finalCFrame.Rotation + (finalCFrame.Position + Vector3.new(0, balloon:GetPivot().Position.Y - dragonBalloon:GetPivot().Position.Y, 0))

	local duration = 5
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local goal = {}
	goal.CFrame = finalCFrame
	local tween = PivotToTween(balloon, tweenInfo, finalCFrame)

	tween:Play()
end

function ClientFirstSessionOfferManager.animateBalloonOut(self: ClientFirstSessionOfferManager)
	local dragonBalloon = self.dragonBalloon
	if not dragonBalloon then
		return
	end

	local cframe = dragonBalloon:GetPivot()
	local finalCFrame = cframe + Vector3.new(0, 50, 0)

	local duration = 5
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	local tween = PivotToTween(dragonBalloon, tweenInfo, finalCFrame)
	tween.Completed:Connect(
		function()
			dragonBalloon:Destroy()
		end
	)
	self.dragonBalloon = nil
	tween:Play()
end

function ClientFirstSessionOfferManager.ensureBalloonExistsInPlace(self: ClientFirstSessionOfferManager)
	if self.dragonBalloon then
		return
	end

	local dragonBalloonTemplate: any = Fixtures:WaitForChild("DragonBalloon")
	local dragonBalloon = dragonBalloonTemplate:Clone()
	utils.setPropertyTreeBaseParts(dragonBalloon:FindFirstChild("Balloon"), "Anchored", true)

	self.dragonBalloon = dragonBalloon

	self:setupPrompt()

	dragonBalloon:PivotTo(self:getFinalCFrame())

	dragonBalloon.Parent = workspace
end

function ClientFirstSessionOfferManager.removeBalloon(self: ClientFirstSessionOfferManager)
	local dragonBalloon = self.dragonBalloon
	if not dragonBalloon then
		return
	end

	dragonBalloon:Destroy()
	self.dragonBalloon = nil
end

function ClientFirstSessionOfferManager.flyAwayBalloon(self: ClientFirstSessionOfferManager)
	local dragonBalloon = self.dragonBalloon
	if not dragonBalloon then
		return
	end

	-- destroy everything other than the balloon
	for _, inst in dragonBalloon:GetChildren() do
		if inst.name == "Balloon" then
			continue
		end
		if inst.name == "Highlight" then
			continue
		end

		inst:Destroy()
	end

	local balloonHighlight = self.balloonHighlight
	if balloonHighlight then
		local tween = tweenService:Create(balloonHighlight, TweenInfo.new(FADE_HIGHLIGHT_SEC, Enum.EasingStyle.Linear), {FillTransparency = 1})
		tween:Play()
	end

	self:animateBalloonOut()
end

function ClientFirstSessionOfferManager.setRedeemInterface(self: ClientFirstSessionOfferManager)
	local objProximityPrompt = utils.findFirstDescendant(self.dragonBalloon :: any, "ProximityPrompt") :: any
	objProximityPrompt.ActionText = "Claim"
	objProximityPrompt.HoldDuration = ACTIVATION_SEC

	local textLabel = utils.findFirstDescendant(self.dragonBalloon :: any, "Timer") :: any
	textLabel.Text = "YOU DID IT"
end

function ClientFirstSessionOfferManager.setWaitingInterface(self: ClientFirstSessionOfferManager, completeTime: number)
	local objProximityPrompt = utils.findFirstDescendant(self.dragonBalloon :: any, "ProximityPrompt") :: any
	objProximityPrompt.ActionText = "See Offer"
	objProximityPrompt.HoldDuration = 0



	--print("have complete time for", completeTime)
	local textLabel = utils.findFirstDescendant(self.dragonBalloon :: any, "Timer") :: any

	local dialogTextLabel = utils.findFirstDescendant(FirstSessionReward, "Timer") :: any

	self.runConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			local timeRemainingSec = math.ceil(math.max(1, completeTime - workspace:GetServerTimeNow()))

			local str = utils.convertDurationSecToString(timeRemainingSec)
			if textLabel.Text ~= str then
				textLabel.Text = str
			end

			if dialogTextLabel.Text ~= str then
				dialogTextLabel.Text = str
			end
		end
	)
end

function ClientFirstSessionOfferManager.endCountdown(self: ClientFirstSessionOfferManager)
	local runConnect = self.runConnect
	if runConnect then
		runConnect:Disconnect()
		self.runConnect = nil
	end
end

function ClientFirstSessionOfferManager.setFirstSessionOfferState(self: ClientFirstSessionOfferManager, firstSessionOfferState: any)
	--print("client setting first session offer state", firstSessionOfferState)

	local prevState = self.firstSessionOfferState

	self.firstSessionOfferState = firstSessionOfferState

	if self.firstSessionOfferState.state == enums.FirstSessionOfferState.NONE then
		if self.dragonBalloon then
			self:removeBalloon()
		end
		self:endCountdown()
	elseif self.firstSessionOfferState.state == enums.FirstSessionOfferState.WAITING then
		if prevState == nil then
			-- startup it's here? seems weird
			self:ensureBalloonExistsInPlace()
		else
			self:animateBalloonIn()
		end
		self:setWaitingInterface(self.firstSessionOfferState.completeTime)
	elseif self.firstSessionOfferState.state == enums.FirstSessionOfferState.REDEEMABLE then
		if FirstSessionReward.Enabled then
			self:cleanupDialog()
		end
		self:ensureBalloonExistsInPlace()
		self:setRedeemInterface()
		self:endCountdown()
	elseif self.firstSessionOfferState.state == enums.FirstSessionOfferState.COMPLETE then
		if self.dragonBalloon then
			self:flyAwayBalloon()
			screenGuiManager:showSystemMessage("Congratulations! Jump to ride your dragon!")
		end
		self:endCountdown()
	else
		warn("unknown first session offer state", self.firstSessionOfferState.state)
		self:endCountdown()
	end
end

function ClientFirstSessionOfferManager.isFirstSessionOfferActive(self: ClientFirstSessionOfferManager): boolean
	-- as of 2026-august-11 this is guarded: ftueProgress is never assigned on this manager
	-- (copied from ClientFtueManager), so this previously crashed if called
	local ftueProgress = self.ftueProgress
	if not ftueProgress then
		return false
	end
	return ftueProgress.isEnabled
end

function ClientFirstSessionOfferManager.initWorldInterface(self: ClientFirstSessionOfferManager)
	FirstSessionReward:WaitForChild("Main"):WaitForChild("Header"):WaitForChild("ExitButton").Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
end

function ClientFirstSessionOfferManager.init(self: ClientFirstSessionOfferManager)
	self:initWorldInterface()
end

function ClientFirstSessionOfferManager.new(): ClientFirstSessionOfferManager
	local self = setmetatable({} :: ClientFirstSessionOfferManagerFields, ClientFirstSessionOfferManager)

	self.firstSessionOfferState = nil

	self.dragonBalloon = nil

	return self
end


local singleton = ClientFirstSessionOfferManager.new()

return singleton
