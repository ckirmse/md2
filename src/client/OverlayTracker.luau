--!strict

local OverlayTracker = {}
OverlayTracker.__index = OverlayTracker

local gamepadService = game:GetService("GamepadService")
local guiService = game:GetService("GuiService")
local lightingService = game:GetService("Lighting")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

local Types = require("./Types")
local teleporters: Types.Teleporters -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local player = game:GetService("Players").LocalPlayer :: Player

type OverlayTrackerFields = {
	overlay: Types.Overlay?,
	overlayNotifiers: { Types.OverlayNotifier },
	doAllowPlayerWorldActions: boolean,
	doZoomCamera: boolean,
}

export type OverlayTracker = typeof(setmetatable({} :: OverlayTrackerFields, OverlayTracker))

function OverlayTracker.notifyBeginOverlay(self: OverlayTracker, overlay: Types.Overlay)
	local previousOverlay = self.overlay
	if previousOverlay then
		--print("forcing overlay closed", self.overlay)
		previousOverlay:notifyForceEnd()
	end

	--print("begin overlay", overlay)

	self.overlay = overlay

	-- the Blur post effect is authored in Studio, so it is untyped here
	local blur: any = (lightingService :: any).Blur
	local doesWantBlur = overlay.doesWantBlur
	if doesWantBlur then
		blur.Enabled = doesWantBlur(overlay)
	else
		blur.Enabled = true
	end

	local doAllowPlayerWorldActions = overlay.doAllowPlayerWorldActions
	if doAllowPlayerWorldActions then
		self.doAllowPlayerWorldActions = doAllowPlayerWorldActions(overlay)
	else
		self.doAllowPlayerWorldActions = true
	end

	if not self.doAllowPlayerWorldActions then
		-- the character rig's children only exist at runtime, so they are untyped here
		(player.Character :: any).HumanoidRootPart.Anchored = true
		-- probably lock camera too? xxx
	end

	local doZoomCamera = overlay.doZoomCamera
	if doZoomCamera then
		self.doZoomCamera = doZoomCamera(overlay)
	else
		self.doZoomCamera = true
	end

	if self.doZoomCamera then
		local camera = 	workspace.CurrentCamera
		local duration = 0.15
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.InOut
		)
		local goal = {}
		goal.FieldOfView = 65

		local tween = tweenService:Create(camera, tweenInfo, goal)
		tween:Play()
	end

	local hudElements = overlay:getHudElements()
	for _, overlayNotifier in self.overlayNotifiers do
		overlayNotifier:notifyBeginOverlay(overlay, hudElements)
	end

	local lastInput = userInputService:GetLastInputType()
	if lastInput == Enum.UserInputType.Gamepad1 or lastInput == Enum.UserInputType.Gamepad2 then
		--print("selecting gui root", self.overlay:getGuiRoot())
		guiService:Select(overlay:getGuiRoot())
	end
end

function OverlayTracker.notifyEndOverlay(self: OverlayTracker, overlay: Types.Overlay)
	local currentOverlay = self.overlay
	if not currentOverlay then
		print("overlay ending when none occurring", overlay)
		return
	end

	if overlay ~= currentOverlay then
		print("mismatch overlay ending", overlay, "that was not the most recently started", currentOverlay)
	end

	--print("end overlay", self.overlay)

	if not self.doAllowPlayerWorldActions then
		-- the character rig's children only exist at runtime, so they are untyped here
		(player.Character :: any).HumanoidRootPart.Anchored = false
	end

	-- the Blur post effect is authored in Studio, so it is untyped here
	local blur: any = (lightingService :: any).Blur
	blur.Enabled = false

	if self.doZoomCamera then
		local camera = 	workspace.CurrentCamera
		local duration = 0.15
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Linear
		)
		local goal = {}
		goal.FieldOfView = 70

		local tween = tweenService:Create(camera, tweenInfo, goal)
		tween:Play()
	end

	local hudElements = overlay:getHudElements()
	for _, overlayNotifier in self.overlayNotifiers do
		overlayNotifier:notifyEndOverlay(currentOverlay, hudElements)
	end

	self.overlay = nil
end

function OverlayTracker.addOverlayNotifier(self: OverlayTracker, overlayNotifier: Types.OverlayNotifier)
	--print("adding notifier", overlayNotifier)
	table.insert(self.overlayNotifiers, overlayNotifier)
end

-- whether a store's proximity auto-open may begin right now: yes with no overlay up, and yes over
-- an overlay that opts in via the doAllowStoreAutoOpen hook (the stores themselves, so walking
-- from one vendor to the other hands off); any other overlay (trade, offers, ...) blocks it
function OverlayTracker.canStoreAutoOpen(self: OverlayTracker): boolean
	local overlay = self.overlay
	if not overlay then
		return true
	end

	local doAllowStoreAutoOpen = overlay.doAllowStoreAutoOpen
	if doAllowStoreAutoOpen then
		return doAllowStoreAutoOpen(overlay)
	end

	return false
end

function OverlayTracker.closeOverlayIfExists(self: OverlayTracker)
	local overlay = self.overlay
	if not overlay then
		return
	end

	overlay:notifyForceEnd()
end

function OverlayTracker.init(self: OverlayTracker)
	--guiService.GuiNavigationEnabled = true

	local mouse = player:GetMouse()

	userInputService.InputBegan:Connect(
		function(input, gameProcessed)
			-- Ignore if the player is typing in chat or using a GUI
			--print("overlay tracker sees inputinput", input, gameProcessed)
			if gameProcessed then
				return
			end


			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local overlay = self.overlay
				if not overlay then
					return
				end

				local guiObjects = (player:WaitForChild("PlayerGui") :: PlayerGui):GetGuiObjectsAtPosition(mouse.X, mouse.Y)

				local guiRoot = overlay:getGuiRoot()
				local clickedOnOverlay = false
				for _, obj in guiObjects do
					if not obj:IsDescendantOf(guiRoot) then
						continue
					end

					clickedOnOverlay = true
				end
				--print("got a click--was it on frame?", clickedOnFrame)
				if not clickedOnOverlay then
					overlay:notifyClickOutside()
				end
			end

			if input.KeyCode == Enum.KeyCode.DPadUp then
				print("D-Pad Up pressed")
				-- hack to not let it get into the virtual mouse mode; learned from TopBarPlus
				if gamepadService.GamepadCursorEnabled then
					task.wait(0.1)
					gamepadService:DisableGamepadCursor()
				end
				local overlay = self.overlay
				if overlay then
					guiService:Select(overlay:getGuiRoot())
				else
					guiService:Select(teleporters:getGuiRoot())
				end
			elseif input.KeyCode == Enum.KeyCode.DPadDown then
				print("D-Pad Down pressed")
			elseif input.KeyCode == Enum.KeyCode.DPadLeft then
				print("D-Pad Left pressed")
			elseif input.KeyCode == Enum.KeyCode.DPadRight then
				print("D-Pad Right pressed")
			end
		end
	)

end

function OverlayTracker.new(): OverlayTracker
	local self = setmetatable({} :: OverlayTrackerFields, OverlayTracker)

	self.overlay = nil

	self.overlayNotifiers = {}

	self.doAllowPlayerWorldActions = true
	self.doZoomCamera = true

	return self
end

function OverlayTracker.initClass(deps: any)
	teleporters = deps.teleporters
end

local singleton = OverlayTracker.new()

return singleton
