--!strict

local ClientPromptGroupManager = {}
ClientPromptGroupManager.__index = ClientPromptGroupManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local LuckPromptGroup: any = PlayerGui:WaitForChild("LuckPromptGroup")

local GuiRoot: any = LuckPromptGroup

export type ClientPromptGroupManager = typeof(setmetatable({}, ClientPromptGroupManager))

function ClientPromptGroupManager.getGuiRoot(self: ClientPromptGroupManager): Instance
	return GuiRoot
end

function ClientPromptGroupManager.notifyForceEnd(self: ClientPromptGroupManager)
	self:cleanupDialog()
end

function ClientPromptGroupManager.notifyClickOutside(self: ClientPromptGroupManager)
	self:notifyForceEnd()
end

function ClientPromptGroupManager.getHudElements(self: ClientPromptGroupManager): { number }
	return {}
end

function ClientPromptGroupManager.beginDialog(self: ClientPromptGroupManager)
	GuiRoot.Enabled = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientPromptGroupManager.cleanupDialog(self: ClientPromptGroupManager)
	GuiRoot.Enabled = false
	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientPromptGroupManager.notifyPromptGroup(self: ClientPromptGroupManager)
	self:beginDialog()
end

function ClientPromptGroupManager.init(self: ClientPromptGroupManager)
	local Main = GuiRoot:WaitForChild("Main")
	Main:WaitForChild("Dismiss").Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
	Main:WaitForChild("Confirm").Activated:Connect(
		function()
			RemoteEvents.TryCheckGroup:FireServer()

			self:cleanupDialog()
		end
	)
end

function ClientPromptGroupManager.new(): ClientPromptGroupManager
	local self = setmetatable({}, ClientPromptGroupManager)
	return self
end

local singleton = ClientPromptGroupManager.new()

return singleton
