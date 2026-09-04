--!strict

local ClientLuckInfoManager = {}
ClientLuckInfoManager.__index = ClientLuckInfoManager

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local LuckInfo: any = PlayerGui:WaitForChild("LuckInfo")

local GuiRoot: any = LuckInfo

type ClientLuckInfoManagerFields = {
	attributeChangedConnect: RBXScriptConnection?,
}

export type ClientLuckInfoManager = typeof(setmetatable({} :: ClientLuckInfoManagerFields, ClientLuckInfoManager))

function ClientLuckInfoManager.getGuiRoot(self: ClientLuckInfoManager): Instance
	return GuiRoot
end

function ClientLuckInfoManager.notifyForceEnd(self: ClientLuckInfoManager)
	self:cleanupDialog()
end

function ClientLuckInfoManager.notifyClickOutside(self: ClientLuckInfoManager)
	self:notifyForceEnd()
end

function ClientLuckInfoManager.getHudElements(self: ClientLuckInfoManager): { number }
	return {}
end

function ClientLuckInfoManager.updateInfo(self: ClientLuckInfoManager)
	local luckState = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData"):WaitForChild("Luck"):WaitForChild("State")

	local timeLuckPercent = luckState:GetAttribute(Attributes.TIME_LUCK_PERCENT) :: number
	local friendLuckPercent = luckState:GetAttribute(Attributes.FRIEND_LUCK_PERCENT) :: number
	local groupLuckPercent = luckState:GetAttribute(Attributes.GROUP_LUCK_PERCENT) :: number
	local indexLuckPercent = luckState:GetAttribute(Attributes.INDEX_LUCK_PERCENT) :: number;
	(utils.findFirstDescendant(GuiRoot, "Time") :: any):FindFirstChild("Current").Text = string.format("+%i%%", timeLuckPercent);
	(utils.findFirstDescendant(GuiRoot, "Friend") :: any):FindFirstChild("Current").Text = string.format("+%i%%", friendLuckPercent);
	(utils.findFirstDescendant(GuiRoot, "Group") :: any):FindFirstChild("Current").Text = string.format("+%i%%", groupLuckPercent);
	(utils.findFirstDescendant(GuiRoot, "Index") :: any):FindFirstChild("Current").Text = string.format("+%i%%", indexLuckPercent)
end

function ClientLuckInfoManager.beginDialog(self: ClientLuckInfoManager)
	local luckState = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData"):WaitForChild("Luck"):WaitForChild("State")
	self.attributeChangedConnect = luckState.AttributeChanged:Connect(
		function()
			self:updateInfo()
		end
	)

	self:updateInfo()

	GuiRoot.Enabled = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientLuckInfoManager.cleanupDialog(self: ClientLuckInfoManager)
	local attributeChangedConnect = self.attributeChangedConnect
	if attributeChangedConnect then
		attributeChangedConnect:Disconnect()
		self.attributeChangedConnect = nil
	end

	GuiRoot.Enabled = false
	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientLuckInfoManager.init(self: ClientLuckInfoManager)
	local Main = GuiRoot:WaitForChild("Main")
	Main:WaitForChild("HeaderSmall"):WaitForChild("ExitButton").Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
	Main:WaitForChild("PlayButton").Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
end

function ClientLuckInfoManager.new(): ClientLuckInfoManager
	local self = setmetatable({} :: ClientLuckInfoManagerFields, ClientLuckInfoManager)
	return self
end

local singleton = ClientLuckInfoManager.new()

return singleton
