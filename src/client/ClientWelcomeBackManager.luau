--!strict

local ClientWelcomeBackManager = {}
ClientWelcomeBackManager.__index = ClientWelcomeBackManager

local marketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local WelcomeBack = require("@game/ReplicatedStorage/Shared/WelcomeBack")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local DOUBLE_WELCOME_BACK_PRODUCT_ID = WelcomeBack.DOUBLE_WELCOME_BACK_PRODUCT_ID

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("WelcomeBack")

type RobuxProductInfo = {
	robuxPrice: number,
}

type ClientWelcomeBackManagerFields = {
	connections: { RBXScriptConnection },
	robuxProductInfo: { [number]: RobuxProductInfo },
}

export type ClientWelcomeBackManager = typeof(setmetatable({} :: ClientWelcomeBackManagerFields, ClientWelcomeBackManager))

function ClientWelcomeBackManager.getGuiRoot(self: ClientWelcomeBackManager): Instance
	return GuiRoot
end

function ClientWelcomeBackManager.notifyForceEnd(self: ClientWelcomeBackManager)
	RemoteEvents.TryClaimWelcomeBackGift:FireServer()
	self:cleanupDialog()
end

function ClientWelcomeBackManager.notifyClickOutside(self: ClientWelcomeBackManager)
	self:notifyForceEnd()
end

function ClientWelcomeBackManager.getHudElements(self: ClientWelcomeBackManager): { number }
	return {enums.HudElements.COINS}
end

function ClientWelcomeBackManager.queryRobuxProductInfo(self: ClientWelcomeBackManager)
	task.defer(
		function()
			local isSuccess, productInfo = pcall(
				function()
					return marketplaceService:GetProductInfoAsync(DOUBLE_WELCOME_BACK_PRODUCT_ID, Enum.InfoType.Product) :: any
				end
			)
			if isSuccess then
				if productInfo.IsForSale then
					self.robuxProductInfo[DOUBLE_WELCOME_BACK_PRODUCT_ID] = {
						robuxPrice = productInfo.PriceInRobux :: number,
					}
				else
					print("product not for robux sale", DOUBLE_WELCOME_BACK_PRODUCT_ID, productInfo)
				end
			end
		end
	)
end

function ClientWelcomeBackManager.beginDialog(self: ClientWelcomeBackManager, coinCount: number)
	local Main = GuiRoot:WaitForChild("Main")

	Main:WaitForChild("Coins"):WaitForChild("TextLabel").Text = utils.formatLargeInteger(coinCount)

	local productInfo = self.robuxProductInfo[DOUBLE_WELCOME_BACK_PRODUCT_ID]
	if productInfo then
		Main:WaitForChild("RobuxPrice").Text = tostring(productInfo.robuxPrice)
	end

	local doubleButtonConnection: RBXScriptConnection = Main:WaitForChild("DoubleButton").Activated:Connect(
		function()
			local isSuccess, errorMessage = pcall(
				function()
					marketplaceService:PromptProductPurchase(player, DOUBLE_WELCOME_BACK_PRODUCT_ID)
					--xxx need to handle this on backend
				end
			)
			if isSuccess then
				self:cleanupDialog()
			else
				warn("error prompting for robux purchase", errorMessage)
			end
		end
	)
	table.insert(self.connections, doubleButtonConnection)

	GuiRoot.Enabled = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientWelcomeBackManager.cleanupDialog(self: ClientWelcomeBackManager)
	GuiRoot.Enabled = false

	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientWelcomeBackManager.init(self: ClientWelcomeBackManager)
	local Main = GuiRoot:WaitForChild("Main")

	Main:WaitForChild("Collect").Activated:Connect(
		function()
			RemoteEvents.TryClaimWelcomeBackGift:FireServer()
			self:cleanupDialog()
		end
	)

	Main:WaitForChild("HeaderSmall"):WaitForChild("ExitButton").Activated:Connect(
		function()
			RemoteEvents.TryClaimWelcomeBackGift:FireServer()
			self:cleanupDialog()
		end
	)

	task.spawn(
		function()
			self:queryRobuxProductInfo()
		end
	)
end

function ClientWelcomeBackManager.new(): ClientWelcomeBackManager
	local self = setmetatable({} :: ClientWelcomeBackManagerFields, ClientWelcomeBackManager)
	self.connections = {}
	self.robuxProductInfo = {}
	return self
end

local singleton = ClientWelcomeBackManager.new()

return singleton
