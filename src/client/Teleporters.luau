--!strict

local Teleporters = {}
Teleporters.__index = Teleporters

local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the audio template's shape only exists in Studio, so it is untyped here
local TeleportAudioParent: any = Effects:WaitForChild("TeleportAudioParent")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local cameraManager = require("./CameraManager")
local clientRideController = require("./ClientRideController")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance
local screenGui = playerGui:WaitForChild("ScreenGui")

-- the gui's shape only exists in Studio, so these are untyped here
local teleportButtonGrid: any = utils.findFirstDescendant(screenGui, "TeleportButtons")
local buyButton: any = utils.findFirstDescendant(screenGui, "TeleportBuyButton")
local homeButton: any = utils.findFirstDescendant(screenGui, "TeleportHomeButton")
-- legacy/dormant (2026-august-20): gem-selling removed; button hidden in Studio, kept unwired.
-- see abilitiesButton below for the new dedicated Abilities teleport button.
local sellButton: any = utils.findFirstDescendant(screenGui, "TeleportSellButton")
local abilitiesButton: any = utils.findFirstDescendant(screenGui, "TeleportAbilitiesButton")

local BUY_TELEPORT_POSITION = Vector3.new(-7, 7, 34.5)
-- local SELL_TELEPORT_POSITION = Vector3.new(5.5, 7, 34.5)
local ABILITIES_TELEPORT_POSITION = Vector3.new(4.8, 5.3, 34.3)

type TeleportersFields = {
	homeCFrame: CFrame?,
	overlayCount: number,
	plotIndex: number?,
	teleportButtonGridBasePosition: UDim2,
	teleportButtonGridOffscreenPosition: UDim2,
	audioTeleport: any, -- AudioPlayer authored in Studio
}

export type Teleporters = typeof(setmetatable({} :: TeleportersFields, Teleporters))

function Teleporters.getGuiRoot(self: Teleporters): Instance
	return teleportButtonGrid
end

function Teleporters.cleanupPreTeleport(self: Teleporters)
	if clientRideController:isRiding() then
		clientRideController:tryEndRiding()
		-- lingering client updates can trigger server assignment of player location, so try to let that finish up)
		task.wait(0.1)
	end
end

function Teleporters.notifyBeginOverlay(self: Teleporters, overlay: Types.Overlay, hudElements: { number })
	self.overlayCount += 1
	self:animateOutTeleporters()
end

function Teleporters.notifyEndOverlay(self: Teleporters, overlay: Types.Overlay, hudElements: { number })
	self.overlayCount -= 1
	self:animateInTeleporters()
end

function Teleporters.hideTeleporters(self: Teleporters)
	teleportButtonGrid.Position = self.teleportButtonGridOffscreenPosition
end

function Teleporters.showTeleporters(self: Teleporters)
	if self.overlayCount > 0 then
		return
	end

	teleportButtonGrid.Position = self.teleportButtonGridBasePosition
end

function Teleporters.animateOutTeleporters(self: Teleporters)
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
	local goal = {}
	goal.Position = self.teleportButtonGridOffscreenPosition

	local tween = tweenService:Create(teleportButtonGrid, tweenInfo, goal)
	tween:Play()
end

function Teleporters.animateInTeleporters(self: Teleporters)
	self:hideTeleporters()

	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
	local goal = {}
	goal.Position = self.teleportButtonGridBasePosition

	local tween = tweenService:Create(teleportButtonGrid, tweenInfo, goal)
	tween:Play()
end

function Teleporters.initWorldInterface(self: Teleporters)
	buyButton.Activated:Connect(function()
		--print("buy activated")

		-- the character rig's children only exist at runtime, so it is untyped here
		local character: any = player.Character
		if not character or not character.HumanoidRootPart then
			return
		end

		self:cleanupPreTeleport()

		character.HumanoidRootPart:PivotTo(
			CFrame.new(
				utils.getGroundPositionForLocation(BUY_TELEPORT_POSITION)
					+ Vector3.new(0, character.Humanoid.HipHeight + character.HumanoidRootPart.Size.Y / 2, 0)
			)
		)

		cameraManager:moveCameraBehindPlayer()

		self.audioTeleport:Play()
	end)

	homeButton.Activated:Connect(function()
		--print("home activated")
		local homeCFrame = self.homeCFrame
		if not homeCFrame then
			print("cannot teleport to home, don't have position yet")
			return
		end

		local character: any = player.Character
		if not character or not character.HumanoidRootPart then
			return
		end

		self:cleanupPreTeleport()

		--player.Character.HumanoidRootPart:PivotTo(self.homeCFrame.Rotation + (utils.getGroundPositionForLocation(self.homeCFrame.Position) + Vector3.new(0, player.Character.Humanoid.HipHeight, 0)))
		local position = homeCFrame.Position

		character.HumanoidRootPart:PivotTo(
			homeCFrame.Rotation
				+ utils.getGroundPositionForLocation(position)
				+ Vector3.new(0, character.Humanoid.HipHeight + character.HumanoidRootPart.Size.Y / 2, 0)
		)

		cameraManager:moveCameraBehindPlayer()

		self.audioTeleport:Play()
	end)

	-- legacy/dormant (2026-august-20): TeleportSellButton is now hidden in Studio (gem-selling
	-- removed); left unwired rather than reusing it for Abilities now that a dedicated
	-- TeleportAbilitiesButton exists below. Kept only as a reference for what it used to do.
	-- sellButton.Activated:Connect(
	-- 	function()
	-- 		--print("sell activated")
	--
	-- 		local character: any = player.Character
	-- 		if not character or not character.HumanoidRootPart then
	-- 			return
	-- 		end
	--
	-- 		self:cleanupPreTeleport()
	--
	-- 		-- should look up an object in the world, not hard code this xxx
	-- 		local position = Vector3.new(5.5, 7, 34.5)
	-- 		character.HumanoidRootPart:PivotTo(CFrame.new(utils.getGroundPositionForLocation(position) + Vector3.new(0, character.Humanoid.HipHeight + character.HumanoidRootPart.Size.Y / 2, 0)))
	--
	-- 		cameraManager:moveCameraBehindPlayer()
	--
	-- 		self.audioTeleport:Play()
	-- 	end
	-- )

	abilitiesButton.Activated:Connect(function()
		local character: any = player.Character
		if not character or not character.HumanoidRootPart then
			return
		end

		self:cleanupPreTeleport()

		character.HumanoidRootPart:PivotTo(
			CFrame.new(
				utils.getGroundPositionForLocation(ABILITIES_TELEPORT_POSITION)
					+ Vector3.new(0, character.Humanoid.HipHeight + character.HumanoidRootPart.Size.Y / 2, 0)
			)
		)

		cameraManager:moveCameraBehindPlayer()

		self.audioTeleport:Play()
	end)

	overlayTracker:addOverlayNotifier((self :: any) :: Types.OverlayNotifier)
end

function Teleporters.setPlotCFrame(self: Teleporters, cframe: CFrame)
	self.homeCFrame = cframe
end

function Teleporters.getPlotCFrame(self: Teleporters): CFrame?
	return self.homeCFrame
end

function Teleporters.setPlotIndex(self: Teleporters, plotIndex: number)
	self.plotIndex = plotIndex
end

function Teleporters.getPlotIndex(self: Teleporters): number?
	return self.plotIndex
end

function Teleporters.init(self: Teleporters)
	self:initWorldInterface()
end

function Teleporters.new(): Teleporters
	local self = setmetatable({} :: TeleportersFields, Teleporters)

	self.homeCFrame = nil
	self.overlayCount = 0

	self.teleportButtonGridBasePosition = teleportButtonGrid.Position
	self.teleportButtonGridOffscreenPosition = UDim2.new(self.teleportButtonGridBasePosition.X, UDim.new(-0.4, 0))
	local teleportAudioParent = TeleportAudioParent:Clone()
	teleportAudioParent.Parent = workspace

	self.audioTeleport = teleportAudioParent:FindFirstChild("AudioTeleport")

	return self
end

local singleton = Teleporters.new()

return singleton
