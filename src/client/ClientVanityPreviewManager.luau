--!strict

local ClientVanityPreviewManager = {}
ClientVanityPreviewManager.__index = ClientVanityPreviewManager

local tweenService = game:GetService("TweenService")

local Level = workspace:WaitForChild("Level")
local MergePlot = Level:WaitForChild("MergePlot")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
-- the effect template's shape only exists in Studio, so it is untyped here
local VanityUnlockParent: any = ParticleEffects:WaitForChild("VanityUnlockParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local teleporters = require("./Teleporters")
local Types = require("./Types")

local UNLOCK_ANIMATION_SEC = 2.5

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("VanityPreview")

type ClientVanityPreviewManagerFields = {
	realVanityInst: any?, -- world vanity instance; its shape only exists at runtime
	previewVanityInst: any?,
	previewHighlight: Highlight?,
	unlockButtonConnect: RBXScriptConnection?,
	completionFunc: (() -> ())?,
}

export type ClientVanityPreviewManager = typeof(setmetatable({} :: ClientVanityPreviewManagerFields, ClientVanityPreviewManager))

function ClientVanityPreviewManager.getGuiRoot(self: ClientVanityPreviewManager): Instance
	return GuiRoot
end

function ClientVanityPreviewManager.notifyForceEnd(self: ClientVanityPreviewManager)
	self:cleanupPreview()
end

function ClientVanityPreviewManager.notifyClickOutside(self: ClientVanityPreviewManager)
	self:notifyForceEnd()
end

function ClientVanityPreviewManager.doZoomCamera(self: ClientVanityPreviewManager): boolean
	return false
end

function ClientVanityPreviewManager.getHudElements(self: ClientVanityPreviewManager): { number }
	return {}
end

function ClientVanityPreviewManager.doesWantBlur(self: ClientVanityPreviewManager): boolean
	return false
end

function ClientVanityPreviewManager.doAllowPlayerWorldActions(self: ClientVanityPreviewManager): boolean
	return false
end

function ClientVanityPreviewManager.setupWorldPreview(self: ClientVanityPreviewManager, vanityPlacementName: string, templatePath: string, highlightColor: Color3)
	local plotIndex = teleporters:getPlotIndex()

	local existingVanityInst: any = utils.findFirstDescendantWithNameAndAttribute(MergePlot, vanityPlacementName, Attributes.INDEX, plotIndex)
	if existingVanityInst then
		self.realVanityInst = existingVanityInst
		existingVanityInst.Parent = ReplicatedStorage
		existingVanityInst.Destroying:Connect(
			function()
				self.realVanityInst = nil
			end
		)
	end

	-- create instance from path and put it in place

	local template: any = utils.getPathReference(GameAssets, templatePath)
	local previewVanityInst = template:Clone()
	previewVanityInst.Name = vanityPlacementName
	local plotCFrame = PlotHelpers.translateCFrameWorldToPlot(previewVanityInst:GetPivot(), 1)
	local cframe = PlotHelpers.translateCFramePlotToWorld(plotCFrame, teleporters:getPlotIndex() :: number)
	previewVanityInst:PivotTo(cframe)
	previewVanityInst:SetAttribute(Attributes.INDEX, plotIndex)

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineColor = highlightColor
	highlight.OutlineTransparency = 0
	self.previewHighlight = highlight
	highlight.Parent = previewVanityInst

	previewVanityInst.Parent = MergePlot

	self.previewVanityInst = previewVanityInst
end

function ClientVanityPreviewManager.cleanupWorldPreview(self: ClientVanityPreviewManager)

	local realVanityInst = self.realVanityInst
	if realVanityInst then
		realVanityInst.Parent = MergePlot
		self.realVanityInst = nil
	end

	-- as of 2026-august-11 this clears previewHighlight; it previously checked a
	-- never-assigned previewVanityHighlight field, so the highlight was only cleaned up
	-- indirectly by destroying the preview instance
	local previewHighlight = self.previewHighlight
	if previewHighlight then
		previewHighlight:Destroy()
		self.previewHighlight = nil
	end

	local previewVanityInst = self.previewVanityInst
	if previewVanityInst then
		previewVanityInst:Destroy()
		self.previewVanityInst = nil
	end
end

function ClientVanityPreviewManager.beginPreview(self: ClientVanityPreviewManager, completionFunc: () -> (), vanityPlacement: number, vanityComponentName: string, vanityPlacementName: string, rarity: number, canUnlock: boolean)
	self.completionFunc = completionFunc

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")
	local inst: any = utils.findFirstDescendant(vanityDataFolder, vanityComponentName)

	local vanityComponentDisplayName = inst:GetAttribute(Attributes.DISPLAY_NAME) or inst.Name
	local blueprintDisplayName = inst:GetAttribute(Attributes.BLUEPRINT_DISPLAY_NAME)
	local blueprintTemplatePath = inst:GetAttribute(Attributes.BLUEPRINT_TEMPLATE_PATH)
	local templatePaths = inst:GetAttribute(Attributes.TEMPLATE_PATHS)
	-- need to parse this templatePath--it alternates vanityPlacement and templatePath
	local templatePath
	local iterFunc = string.gmatch(templatePaths, "%S+")
	while true do
		local vanityPlacementStr = iterFunc()
		if not vanityPlacementStr then
			warn("cannot find matching template path", templatePaths, vanityPlacement)
			return
		end

		templatePath = iterFunc()
		if tonumber(vanityPlacementStr) == vanityPlacement then
			break
		end
	end
	self:setupWorldPreview(vanityPlacementName, templatePath :: string, utils.getColorForRarity(rarity))

	local Main = GuiRoot:FindFirstChild("Main")
	local Detail = Main:FindFirstChild("Detail")
	local Title: any = utils.findFirstDescendant(Detail, "Title")
	Title.Text = vanityComponentDisplayName

	local ContentLocked: any = utils.findFirstDescendant(Detail, "ContentLocked")
	local ContentUnlocked: any = utils.findFirstDescendant(Detail, "ContentUnlocked")

	if canUnlock then
		ContentLocked.Visible = false
		ContentUnlocked.Visible = true

		local UnlockWithBlueprintButton: any = utils.findFirstDescendant(ContentUnlocked, "UnlockWithBlueprintButton")
		local BlueprintViewportFrame: any = utils.findFirstDescendant(UnlockWithBlueprintButton, "BlueprintViewportFrame")
		if blueprintTemplatePath then
			local blueprintTemplate: any = utils.getPathReference(GameAssets, blueprintTemplatePath)
			if blueprintTemplate then
				local blueprint = blueprintTemplate:Clone()
				-- as of 2026-august-11 this calls GetPivot; it previously called getPivot
				-- (lowercase), which is not a member and would have thrown here
				blueprint:PivotTo(blueprint:GetPivot().Rotation + Vector3.zero) -- maintain rotation but move to origin
				blueprint.Parent = BlueprintViewportFrame

				local viewportCamera = Instance.new("Camera")
				BlueprintViewportFrame.CurrentCamera = viewportCamera
				viewportCamera.Parent = BlueprintViewportFrame

				local cameraPosition = Vector3.new(-3, 1, 3)

				BlueprintViewportFrame.CurrentCamera.CFrame = CFrame.new(cameraPosition, blueprint:GetPivot().Position)
			end
		end

		self.unlockButtonConnect = UnlockWithBlueprintButton.Activated:Connect(
			function()
				RemoteEvents.TryUnlockVanityComponent:FireServer(vanityPlacement, vanityComponentName)

				local gnome: any = utils.findFirstDescendant(workspace, "Gnome")
				local audioUnlockVanity = gnome:FindFirstChild("AudioUnlockVanity")
				audioUnlockVanity:Play()

				local vanityUnlockParent = VanityUnlockParent:Clone()
				vanityUnlockParent:PivotTo((self.previewVanityInst :: any):GetPivot())
				vanityUnlockParent.Parent = workspace

				local burst = vanityUnlockParent:FindFirstChild("Burst")
				burst:Emit(250)

				utils.safelyDisposeOfParticleParent(vanityUnlockParent, UNLOCK_ANIMATION_SEC)

				local previewHighlight = self.previewHighlight
				if previewHighlight then
					previewHighlight.OutlineTransparency = 1
					previewHighlight.FillTransparency = 0
					local tween = tweenService:Create(previewHighlight, TweenInfo.new(UNLOCK_ANIMATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1})
					tween:Play()
					tween.Completed:Wait()
				end

				if GuiRoot.Enabled then
					-- if player exits the preview while waiting on an unlock, then GuiRoot is already gone
					self:cleanupPreview()
				end

			end
		)

	else
		ContentLocked.Visible = true
		ContentUnlocked.Visible = false

		if blueprintDisplayName then
			ContentLocked:FindFirstChild("TextLabel").Text = string.format("Unlock with %s", blueprintDisplayName)
		else
			ContentLocked:FindFirstChild("TextLabel").Text = "Customization Removed"
		end

		local BlueprintViewportFrame: any = utils.findFirstDescendant(ContentLocked, "BlueprintViewportFrame")
		if blueprintTemplatePath then
			local blueprintTemplate: any = utils.getPathReference(GameAssets, blueprintTemplatePath)
			if blueprintTemplate then
				local blueprint = blueprintTemplate:Clone()
				-- as of 2026-august-11 this calls GetPivot; it previously called getPivot
				-- (lowercase), which is not a member and would have thrown here
				blueprint:PivotTo(blueprint:GetPivot().Rotation + Vector3.zero) -- maintain rotation but move to origin
				blueprint.Parent = BlueprintViewportFrame

				local viewportCamera = Instance.new("Camera")
				BlueprintViewportFrame.CurrentCamera = viewportCamera
				viewportCamera.Parent = BlueprintViewportFrame

				local cameraPosition = Vector3.new(-3, 1, 3)

				BlueprintViewportFrame.CurrentCamera.CFrame = CFrame.new(cameraPosition, blueprint:GetPivot().Position)
			end
		end
	end

	-- slide up the preview dialog from the bottom
	local baseMainPosition = Main.Position
	Main.Position = UDim2.new(Main.Position.X.Scale, Main.Position.X.Offset, 1.1, 0)
	local tweenInfo = TweenInfo.new(
		0.2,
		Enum.EasingStyle.Quad
	)
	local goal = {}
	goal.Position = baseMainPosition

	local tween = tweenService:Create(Main, tweenInfo, goal)
	tween:Play()


	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	local gnome: any = utils.findFirstDescendant(workspace, "Gnome")
	local audioBeginPreview = gnome:FindFirstChild("AudioBeginPreview")
	audioBeginPreview:Play()

	local audioPreviewIdle = gnome:FindFirstChild("AudioPreviewIdle")
	audioPreviewIdle.Looping = true
	audioPreviewIdle:Play()

end

function ClientVanityPreviewManager.cleanupPreview(self: ClientVanityPreviewManager)
	local unlockButtonConnect = self.unlockButtonConnect
	if unlockButtonConnect then
		unlockButtonConnect:Disconnect()
		self.unlockButtonConnect = nil
	end

	self:cleanupWorldPreview()

	GuiRoot.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	local gnome: any = utils.findFirstDescendant(workspace, "Gnome")
	local audioPreviewIdle = gnome:FindFirstChild("AudioPreviewIdle")
	audioPreviewIdle:Stop()

	local completionFunc = self.completionFunc
	if completionFunc then
		completionFunc()
	end
end

function ClientVanityPreviewManager.init(self: ClientVanityPreviewManager)

	local exitButton: any = utils.findFirstDescendant(GuiRoot, "ExitButton")
	exitButton.Activated:Connect(
		function()
			self:cleanupPreview()
		end
	)
end

function ClientVanityPreviewManager.new(): ClientVanityPreviewManager
	local self = setmetatable({} :: ClientVanityPreviewManagerFields, ClientVanityPreviewManager)

	return self
end


local singleton = ClientVanityPreviewManager.new()

return singleton
