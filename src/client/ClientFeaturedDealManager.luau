--!strict

-- HUD "FeaturedDeal" button: a constantly twitching promo for one rotating deal from GameData/Control/FeaturedDeals.
-- Which deal is featured is a pure function of server time (see FeaturedDealCatalog), so every player sees the same
-- one at the same moment. Tapping prompts the deal's Robux product directly; delivery is the Deal Shop's existing
-- receipt path. The config arrives in the init data; the button lives in the HUD ScreenGui, which ScreenGuiManager
-- owns and wires up.
local ClientFeaturedDealManager = {}
ClientFeaturedDealManager.__index = ClientFeaturedDealManager

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local FeaturedDealCatalog = require("@game/ReplicatedStorage/Shared/FeaturedDealCatalog")

local ButtonTwitcher = require("./ButtonTwitcher")
local ClientProductInfo = require("./ClientProductInfo")
local ClientTicker = require("./ClientTicker")
local RainbowSweep = require("./RainbowSweep")

local player = game:GetService("Players").LocalPlayer :: Player

-- the button's shape only exists in Studio, so its instances are untyped here
type ClientFeaturedDealManagerFields = {
	config: FeaturedDealCatalog.FeaturedDealsConfig?,
	button: any?,
	iconLabel: any?,
	nameLabel: any?,
	costLabel: any?,
	twitcher: ButtonTwitcher.ButtonTwitcher?,
	stopRainbow: (() -> ())?,
	currentDealKey: string?,
	currentProductId: number?,
	priceRequestId: number,
}

export type ClientFeaturedDealManager = typeof(setmetatable({} :: ClientFeaturedDealManagerFields, ClientFeaturedDealManager))

local TWITCH_INTERVAL_SEC = 2.5
local SHINE_ROTATE_SEC = 8
local UPDATE_INTERVAL_SEC = 1

function ClientFeaturedDealManager.render(self: ClientFeaturedDealManager, deal: FeaturedDealCatalog.FeaturedDeal?)
	local button = self.button
	if not button then
		return
	end

	local stopRainbow = self.stopRainbow
	if stopRainbow then
		stopRainbow()
		self.stopRainbow = nil
	end
	self.priceRequestId += 1

	if not deal then
		self.currentDealKey = nil
		self.currentProductId = nil
		button.Visible = false
		return
	end

	local tier = deal.tiers[1]
	self.currentDealKey = deal.dealKey
	self.currentProductId = tier.productId

	local iconLabel = self.iconLabel
	if iconLabel then
		iconLabel.Image = deal.icon
	end

	local nameLabel = self.nameLabel
	if nameLabel then
		nameLabel.Text = deal.title
		self.stopRainbow = RainbowSweep.start(nameLabel)
	end

	local costLabel = self.costLabel
	if costLabel then
		costLabel.Text = "..."
	end
	button.Active = false
	button.Visible = true

	-- the rotation can advance while the price lookup is in flight
	local requestId = self.priceRequestId
	ClientProductInfo.getProductInfoAsync(tier.productId, function(info: ClientProductInfo.ProductInfo)
		if requestId ~= self.priceRequestId then
			return
		end

		if not info.isForSale or not info.robuxPrice then
			if costLabel then
				costLabel.Text = "N/A"
			end
			return
		end

		if costLabel then
			costLabel.Text = tostring(info.robuxPrice)
		end
		button.Active = true
	end)
end

function ClientFeaturedDealManager.update(self: ClientFeaturedDealManager)
	local config = self.config
	if not config or not self.button then
		return
	end

	local deal = FeaturedDealCatalog.getFeaturedDeal(config, workspace:GetServerTimeNow())
	local dealKey = if deal then deal.dealKey else nil
	if dealKey ~= self.currentDealKey then
		self:render(deal)
	end

	local twitcher = self.twitcher
	if deal and twitcher then
		twitcher:updateIfNeeded()
	end
end

function ClientFeaturedDealManager.onActivated(self: ClientFeaturedDealManager)
	local button = self.button
	local productId = self.currentProductId
	if not button or not button.Active or not productId then
		return
	end

	-- a gift selection abandoned in the shop must not turn this purchase into a gift
	RemoteEvents.TryClearGift:FireServer()

	local isSuccess, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not isSuccess then
		warn("ClientFeaturedDealManager: error prompting for robux purchase", errorMessage)
	end
end

-- the featured deals from the server: in the init data
function ClientFeaturedDealManager.setConfig(self: ClientFeaturedDealManager, config: any)
	if type(config) == "table" and type(config.rotationSec) == "number" and type(config.deals) == "table" then
		self.config = config :: FeaturedDealCatalog.FeaturedDealsConfig
	else
		self.config = nil
		warn("ClientFeaturedDealManager: featured deals config missing or malformed; no featured deal button")
	end

	self:update()
end

-- the HUD button lives in the main HUD ScreenGui, which ScreenGuiManager owns and wires up
function ClientFeaturedDealManager.setHudButton(self: ClientFeaturedDealManager, button: any)
	self.button = button
	self.iconLabel = button:FindFirstChild("Icon")
	self.nameLabel = button:FindFirstChild("Title")
	local priceFrame: any = button:FindFirstChild("Price")
	self.costLabel = if priceFrame then priceFrame:FindFirstChild("Cost") else nil
	if not self.costLabel then
		warn("ClientFeaturedDealManager: the FeaturedDeal button has no Price/Cost label; the price is not shown")
	end

	if self.iconLabel then
		self.twitcher = ButtonTwitcher.new(self.iconLabel, TWITCH_INTERVAL_SEC)
	end
	button.Visible = false

	local shine: any = button:FindFirstChild("Shine")
	if shine and shine:IsA("GuiObject") then
		shine.Rotation = 0
		TweenService:Create(shine, TweenInfo.new(SHINE_ROTATE_SEC, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
	end

	button.Activated:Connect(function()
		self:onActivated()
	end)

	self:update()
end

function ClientFeaturedDealManager.init(self: ClientFeaturedDealManager)
	-- the 1 s poll picks up rotation, expiry and start windows with no timers
	ClientTicker.every(UPDATE_INTERVAL_SEC, function()
		self:update()
	end)
end

function ClientFeaturedDealManager.new(): ClientFeaturedDealManager
	local self = setmetatable({} :: ClientFeaturedDealManagerFields, ClientFeaturedDealManager)

	self.config = nil
	self.button = nil
	self.iconLabel = nil
	self.nameLabel = nil
	self.costLabel = nil
	self.twitcher = nil
	self.stopRainbow = nil
	self.currentDealKey = nil
	self.currentProductId = nil
	self.priceRequestId = 0

	return self
end

local singleton = ClientFeaturedDealManager.new()

return singleton
