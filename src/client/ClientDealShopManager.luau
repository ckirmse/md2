--!strict

local ClientDealShopManager = {}
ClientDealShopManager.__index = ClientDealShopManager

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local DealShopCatalog = require("@game/ReplicatedStorage/Shared/DealShopCatalog")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientGiftingManager = require("./ClientGiftingManager")
local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local DISPLAY_ORDER = 130
local ROBUX_SYMBOL = "\u{E002}"
local UNAFFORDABLE_COLOR = Color3.fromRGB(255, 90, 90)
-- the server answers every coin purchase it accepts; this only unlocks a button whose request was dropped
local PENDING_TIMEOUT_SEC = 5

type TierRecord = {
	deal: DealShopCatalog.Deal,
	tier: DealShopCatalog.Tier,
	tierIndex: number,
	button: any,
	priceText: any,
	giftButton: any?,
	hasCurrencyIcon: boolean, -- an icon sits next to the price, so the text is only the number
	baseTextColor: Color3,
	pendingToken: number?,
}

type CardRecord = {
	card: any,
	sectionKey: string,
	deal: DealShopCatalog.Deal,
	timeLimitText: any?,
	isAvailable: boolean,
}

type ClientDealShopManagerFields = {
	gui: any?,
	scroll: any,
	mainFrame: any,
	toolTipFrame: any?,
	toolTipLabel: any?,
	sectionTabsFrame: any?,
	sectionTabTemplate: any?,
	bundleTemplate: any,
	singleItemTemplate: any,
	config: DealShopCatalog.DealShopConfig?,
	cardRecords: { CardRecord },
	tierRecords: { [string]: TierRecord }, -- keyed by dealKey and tier index
	tabButtons: { [string]: any }, -- keyed by sectionKey
	activeSectionKey: string?,
	robuxPrices: { [number]: number },
	unavailableProductIds: { [number]: boolean },
	refreshConnect: RBXScriptConnection?,
	lastCoins: number?,
	nextPendingToken: number,
	purchasedDealKeys: { [string]: boolean },
	panelOpen: boolean,
	isReady: boolean,
	hasAttemptedBuild: boolean,
}

export type ClientDealShopManager = typeof(setmetatable({} :: ClientDealShopManagerFields, ClientDealShopManager))

local function formatNumber(value: number): string
	local reversed = string.gsub(string.reverse(tostring(math.floor(value))), "(%d%d%d)", "%1,")
	local withCommas = string.reverse(reversed)
	return (string.gsub(withCommas, "^,", ""))
end

local function getTierKey(dealKey: string, tierIndex: number): string
	return `{dealKey}:{tierIndex}`
end

local function getCoins(): number
	return (clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS) :: number?) or 0
end

local function getContentName(content: DealShopCatalog.DealContent): string
	if content.kind == enums.ShopContentKind.COINS then
		return "Coins"
	end
	return (content.displayName or content.objectName) :: string
end

local function getContentCount(content: DealShopCatalog.DealContent): number
	if content.kind == enums.ShopContentKind.COINS then
		return content.amount :: number
	end
	return content.count :: number
end

-- a single item sold two ways can come in different quantities, so each button states its own count
local function doTierCountsDiffer(deal: DealShopCatalog.Deal): boolean
	local secondTier = deal.tiers[2]
	return secondTier ~= nil and getContentCount(deal.tiers[1].contents[1]) ~= getContentCount(secondTier.contents[1])
end

local function describeContent(content: DealShopCatalog.DealContent): string
	local name = getContentName(content)
	local count = getContentCount(content)
	if count > 1 then
		return `{formatNumber(count)}x {name}`
	end
	return name
end

local function setTabActive(tabButton: any, isActive: boolean)
	for _, child in tabButton:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Transparency = isActive and 0 or 1
		end
	end
end

function ClientDealShopManager.getGuiRoot(self: ClientDealShopManager): any
	return self.gui
end

function ClientDealShopManager.getHudElements(self: ClientDealShopManager)
	return {}
end

function ClientDealShopManager.notifyForceEnd(self: ClientDealShopManager)
	self:cleanupPanel()
end

function ClientDealShopManager.notifyClickOutside(self: ClientDealShopManager)
	self:notifyForceEnd()
end

function ClientDealShopManager.doesWantBlur(self: ClientDealShopManager): boolean
	return false
end

function ClientDealShopManager.refreshTierRecord(self: ClientDealShopManager, tierRecord: TierRecord)
	local tier = tierRecord.tier
	local canBuy: boolean
	local textColor = tierRecord.baseTextColor

	if tier.coinCost then
		local isAffordable = getCoins() >= tier.coinCost
		tierRecord.priceText.Text = if tierRecord.hasCurrencyIcon then formatNumber(tier.coinCost) else `{formatNumber(tier.coinCost)} Coins`
		if not isAffordable then
			textColor = UNAFFORDABLE_COLOR
		end
		canBuy = isAffordable and tierRecord.pendingToken == nil
	else
		local productId = tier.productId :: number
		local price = self.robuxPrices[productId]
		if price then
			tierRecord.priceText.Text = if tierRecord.hasCurrencyIcon then formatNumber(price) else `{ROBUX_SYMBOL}{formatNumber(price)}`
			canBuy = true
		elseif self.unavailableProductIds[productId] then
			tierRecord.priceText.Text = "Unavailable"
			canBuy = false
		else
			tierRecord.priceText.Text = "..."
			canBuy = false
		end
	end

	tierRecord.priceText.TextColor3 = textColor
	tierRecord.button.Active = canBuy
	if tierRecord.giftButton then
		tierRecord.giftButton.Active = canBuy
	end
end

function ClientDealShopManager.refreshAllTierRecords(self: ClientDealShopManager)
	for _, tierRecord in self.tierRecords do
		self:refreshTierRecord(tierRecord)
	end
end

function ClientDealShopManager.refreshCoinTierRecords(self: ClientDealShopManager)
	for _, tierRecord in self.tierRecords do
		if tierRecord.tier.coinCost then
			self:refreshTierRecord(tierRecord)
		end
	end
end

function ClientDealShopManager.onTierActivated(self: ClientDealShopManager, tierRecord: TierRecord)
	local tier = tierRecord.tier

	if tier.coinCost then
		if tierRecord.pendingToken ~= nil or getCoins() < tier.coinCost then
			return
		end

		self.nextPendingToken += 1
		local token = self.nextPendingToken
		tierRecord.pendingToken = token
		self:refreshTierRecord(tierRecord)

		RemoteEvents.TryBuyDeal:FireServer(tierRecord.deal.dealKey, tierRecord.tierIndex)

		task.delay(PENDING_TIMEOUT_SEC, function()
			if tierRecord.pendingToken == token then
				tierRecord.pendingToken = nil
				self:refreshTierRecord(tierRecord)
			end
		end)
		return
	end

	local productId = tier.productId :: number

	-- a gift selection abandoned earlier must not turn this into a gift
	RemoteEvents.TryClearGift:FireServer()

	local isSuccess, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not isSuccess then
		warn("ClientDealShopManager: error prompting for robux purchase", errorMessage)
	end
end

function ClientDealShopManager.notifyDealPurchaseResult(self: ClientDealShopManager, dealKey: string, tierIndex: number, isSuccess: boolean)
	local tierRecord = self.tierRecords[getTierKey(dealKey, tierIndex)]
	if not tierRecord then
		return
	end

	tierRecord.pendingToken = nil
	self:refreshTierRecord(tierRecord)

	if isSuccess and tierRecord.deal.oneTimeOnly then
		self.purchasedDealKeys[dealKey] = true
		self:updateTimeLimits()
	end
end

function ClientDealShopManager.setPurchasedDealKeys(self: ClientDealShopManager, purchasedDealKeys: any)
	if type(purchasedDealKeys) ~= "table" then
		return
	end

	self.purchasedDealKeys = purchasedDealKeys
	self:updateTimeLimits()
end

function ClientDealShopManager.wireTier(self: ClientDealShopManager, card: any, deal: DealShopCatalog.Deal, tierIndex: number)
	local tier = deal.tiers[tierIndex]

	-- the price label and its frame are both named Cost, so these are direct paths
	local tierFrame: any = card:FindFirstChild(`BuyTier{tierIndex}`)
	local button: any = tierFrame and tierFrame:FindFirstChild("Purchase")
	local costFrame: any = button and button:FindFirstChild("Cost")
	local priceText: any = costFrame and costFrame:FindFirstChild("Cost")
	if not priceText then
		warn(`ClientDealShopManager: card for deal {deal.dealKey} needs BuyTier{tierIndex}/Purchase/Cost/Cost`)
		return
	end

	local robuxIcon: any = costFrame:FindFirstChild("RBX")
	local coinIcon: any = costFrame:FindFirstChild("Coin")
	local currencyIcon: any = if tier.coinCost then coinIcon else robuxIcon
	if robuxIcon then
		robuxIcon.Visible = tier.coinCost == nil
	end
	if coinIcon then
		coinIcon.Visible = tier.coinCost ~= nil
	end

	local amountText: any = button:FindFirstChild("Amount")
	if amountText then
		local count = tier.contents[1].count or 1
		local statesCount = count > 1 or doTierCountsDiffer(deal)
		amountText.Text = if deal.cardStyle == enums.ShopCardStyle.SINGLE_ITEM and statesCount then `Buy {count}` else "Buy"
	elseif doTierCountsDiffer(deal) then
		warn(`ClientDealShopManager: deal {deal.dealKey} sells different counts, so BuyTier{tierIndex}/Purchase needs an Amount label`)
	end

	local priceSlashText: any = costFrame:FindFirstChild("PriceSlash")
	if priceSlashText then
		priceSlashText.Visible = tier.slashRobux ~= nil
		if tier.slashRobux then
			priceSlashText.Text = formatNumber(tier.slashRobux)
		end
	end

	-- only Robux tiers can be gifted
	local authoredGiftButton: any = tierFrame:FindFirstChild("Gift")
	local isGiftable = tier.productId ~= nil and deal.giftable ~= false and not deal.oneTimeOnly
	local giftButton: any = if isGiftable and clientGiftingManager:isGiftingEnabled() then authoredGiftButton else nil
	if authoredGiftButton then
		authoredGiftButton.Visible = giftButton ~= nil
	end

	tierFrame.Visible = true

	local tierRecord: TierRecord = {
		deal = deal,
		tier = tier,
		tierIndex = tierIndex,
		button = button,
		priceText = priceText,
		giftButton = giftButton,
		hasCurrencyIcon = currencyIcon ~= nil,
		baseTextColor = priceText.TextColor3,
		pendingToken = nil,
	}
	self.tierRecords[getTierKey(deal.dealKey, tierIndex)] = tierRecord

	button.Activated:Connect(function()
		self:onTierActivated(tierRecord)
	end)

	if giftButton then
		giftButton.Activated:Connect(function()
			if giftButton.Active then
				clientGiftingManager:open(tier.productId :: number)
			end
		end)
	end
end

function ClientDealShopManager.refreshCardVisibility(self: ClientDealShopManager, cardRecord: CardRecord)
	local isInActiveSection = self.activeSectionKey == nil or cardRecord.sectionKey == self.activeSectionKey
	cardRecord.card.Visible = isInActiveSection and cardRecord.isAvailable
end

function ClientDealShopManager.isDealAvailable(self: ClientDealShopManager, deal: DealShopCatalog.Deal): boolean
	local now = workspace:GetServerTimeNow()
	if deal.startTime and now < deal.startTime then
		return false
	end
	if deal.endTime and now >= deal.endTime then
		return false
	end

	return not (deal.oneTimeOnly and self.purchasedDealKeys[deal.dealKey])
end

function ClientDealShopManager.setActiveSection(self: ClientDealShopManager, sectionKey: string)
	self.activeSectionKey = sectionKey
	self:hideToolTip()

	for tabSectionKey, tabButton in self.tabButtons do
		setTabActive(tabButton, tabSectionKey == sectionKey)
	end
	for _, cardRecord in self.cardRecords do
		self:refreshCardVisibility(cardRecord)
	end

	self.scroll.CanvasPosition = Vector2.zero
end

function ClientDealShopManager.buildCard(self: ClientDealShopManager, section: DealShopCatalog.Section, deal: DealShopCatalog.Deal, layoutOrder: number)
	local template: any = if deal.cardStyle == enums.ShopCardStyle.SINGLE_ITEM then self.singleItemTemplate else self.bundleTemplate
	local card: any = template:Clone()
	card.Name = `Deal_{deal.dealKey}`
	card.LayoutOrder = layoutOrder

	local titleTimer: any = card:FindFirstChild("TitleTimer")
	local dealTitle: any = titleTimer and titleTimer:FindFirstChild("DealTitle")
	if dealTitle then
		dealTitle.Text = deal.title
	else
		warn(`ClientDealShopManager: card for deal {deal.dealKey} needs TitleTimer/DealTitle`)
	end

	local timeLimitText: any = titleTimer and titleTimer:FindFirstChild("TimeLimit")
	if timeLimitText then
		timeLimitText.Visible = deal.endTime ~= nil
	end

	self:fillContents(card, deal)
	self:wireCardToolTip(card, deal)

	for tierIndex = 1, 2 do
		if tierIndex <= #deal.tiers then
			self:wireTier(card, deal, tierIndex)
		else
			local unusedTierFrame: any = card:FindFirstChild(`BuyTier{tierIndex}`)
			if unusedTierFrame then
				unusedTierFrame.Visible = false
			end
		end
	end

	local cardRecord: CardRecord = {
		card = card,
		sectionKey = section.sectionKey,
		deal = deal,
		timeLimitText = if deal.endTime then timeLimitText else nil,
		isAvailable = true,
	}
	table.insert(self.cardRecords, cardRecord)

	card.Parent = self.scroll
end

-- no item art yet, so each content gets a tile cloned from the authored Icon tile, with its NameText
-- (and optional CountText) standing in for the icon
function ClientDealShopManager.fillContents(self: ClientDealShopManager, card: any, deal: DealShopCatalog.Deal)
	local contentsFrame: any = card:FindFirstChild("Contents")
	if not contentsFrame then
		warn(`ClientDealShopManager: card for deal {deal.dealKey} needs a Contents frame`)
		return
	end

	local hideCounts = doTierCountsDiffer(deal)
	local tileTemplate: any = contentsFrame:FindFirstChild("Icon")
	if not tileTemplate or not tileTemplate:FindFirstChild("NameText") then
		warn(`ClientDealShopManager: card for deal {deal.dealKey} needs Contents/Icon with a NameText label`)
	else
		for contentIndex, content in deal.tiers[1].contents do
			local tile: any = tileTemplate:Clone()
			tile.Name = `Content_{contentIndex}`
			tile.LayoutOrder = contentIndex
			tile.Visible = true
			if tile:IsA("ImageLabel") then
				tile.Image = ""
			end

			tile.NameText.Visible = true

			local count = getContentCount(content)
			local countText: any = tile:FindFirstChild("CountText", true)
			if hideCounts then
				tile.NameText.Text = getContentName(content)
				if countText then
					countText.Visible = false
				end
			elseif countText then
				tile.NameText.Text = getContentName(content)
				countText.Visible = count > 1
				countText.Text = `x{formatNumber(count)}`
			else
				tile.NameText.Text = describeContent(content)
			end

			tile.Parent = contentsFrame
		end
	end

	for _, child in contentsFrame:GetChildren() do
		if child.Name == "Icon" or child.Name == "TimeSkipTemplate" or child.Name == "BenefitDetails" then
			child:Destroy()
		end
	end
end

function ClientDealShopManager.hideToolTip(self: ClientDealShopManager)
	if self.toolTipFrame then
		self.toolTipFrame.Visible = false
	end
end

function ClientDealShopManager.wireCardToolTip(self: ClientDealShopManager, card: any, deal: DealShopCatalog.Deal)
	if not deal.tooltip then
		return
	end

	local lines: { string } = { deal.tooltip }
	for _, content in deal.tiers[1].contents do
		table.insert(lines, `• {describeContent(content)}`)
	end
	local toolTipText = table.concat(lines, "\n")

	card.MouseEnter:Connect(function()
		local toolTipFrame: any = self.toolTipFrame
		local toolTipLabel: any = self.toolTipLabel
		if not toolTipFrame or not toolTipLabel then
			return
		end

		toolTipLabel.Text = toolTipText
		local offset = card.AbsolutePosition - self.mainFrame.AbsolutePosition
		toolTipFrame.Position = UDim2.fromOffset(offset.X, offset.Y - toolTipFrame.AbsoluteSize.Y)
		toolTipFrame.Visible = true
	end)

	card.MouseLeave:Connect(function()
		self:hideToolTip()
	end)
end

function ClientDealShopManager.buildSectionTab(self: ClientDealShopManager, section: DealShopCatalog.Section, layoutOrder: number)
	local tabTemplate: any = self.sectionTabTemplate
	local tab: any = tabTemplate:Clone()
	tab.Name = `SectionTab_{section.sectionKey}`
	tab.LayoutOrder = layoutOrder
	tab.Text = section.title
	tab.Visible = true
	tab.Parent = self.sectionTabsFrame

	tab.Activated:Connect(function()
		self:setActiveSection(section.sectionKey)
	end)

	self.tabButtons[section.sectionKey] = tab
end

function ClientDealShopManager.buildInterface(self: ClientDealShopManager, config: DealShopCatalog.DealShopConfig)
	local hasTabs = self.sectionTabsFrame ~= nil and self.sectionTabTemplate ~= nil

	local layoutOrder = 0
	for sectionIndex, section in config.SECTIONS do
		if hasTabs then
			self:buildSectionTab(section, sectionIndex)
		end

		for _, deal in section.deals do
			layoutOrder += 1
			self:buildCard(section, deal, layoutOrder)
		end
	end

	if hasTabs and #config.SECTIONS > 0 then
		self:setActiveSection(config.SECTIONS[1].sectionKey)
	end

	-- covers the no-tabs case, where setActiveSection never runs
	for _, cardRecord in self.cardRecords do
		self:refreshCardVisibility(cardRecord)
	end

	self:updateTimeLimits()
	self:refreshAllTierRecords()
end

function ClientDealShopManager.updateTimeLimits(self: ClientDealShopManager)
	local now = workspace:GetServerTimeNow()

	for _, cardRecord in self.cardRecords do
		local endTime = cardRecord.deal.endTime
		if endTime and cardRecord.timeLimitText then
			cardRecord.timeLimitText.Text = utils.convertDurationSecToString(math.max(0, endTime - now))
		end

		local isAvailable = self:isDealAvailable(cardRecord.deal)
		if isAvailable ~= cardRecord.isAvailable then
			cardRecord.isAvailable = isAvailable
			self:refreshCardVisibility(cardRecord)
		end
	end
end

function ClientDealShopManager.fetchRobuxPrices(self: ClientDealShopManager)
	local requestedProductIds: { [number]: boolean } = {}

	for _, tierRecord in self.tierRecords do
		local productId = tierRecord.tier.productId
		if not productId or requestedProductIds[productId] then
			continue
		end
		requestedProductIds[productId] = true

		task.defer(function()
			local isSuccess, productInfo = pcall(function()
				return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product) :: any
			end)

			if isSuccess and productInfo.IsForSale then
				self.robuxPrices[productId] = productInfo.PriceInRobux
			else
				warn("ClientDealShopManager: no robux price for product", productId, productInfo)
				self.unavailableProductIds[productId] = true
			end

			for _, productTierRecord in self.tierRecords do
				if productTierRecord.tier.productId == productId then
					self:refreshTierRecord(productTierRecord)
				end
			end
		end)
	end
end

-- runs once both the gui and the server's config exist; it can run inside the NotifyInit handler, so a
-- gui mistake is warned about here instead of aborting the rest of init
function ClientDealShopManager.tryBuild(self: ClientDealShopManager)
	local config = self.config
	if self.hasAttemptedBuild or not self.gui or not config then
		return
	end
	self.hasAttemptedBuild = true

	local isSuccess, errorMessage = pcall(function()
		self:buildInterface(config)
		self:fetchRobuxPrices()
	end)
	if not isSuccess then
		warn("ClientDealShopManager: building the deal shop interface failed:", errorMessage)
		return
	end

	self.isReady = true
end

function ClientDealShopManager.setConfig(self: ClientDealShopManager, config: any)
	if type(config) ~= "table" or type(config.SECTIONS) ~= "table" then
		warn("ClientDealShopManager: deal shop config missing or malformed in the init data", config)
		return
	end

	self.config = config :: DealShopCatalog.DealShopConfig
	self:tryBuild()
end

function ClientDealShopManager.beginPanel(self: ClientDealShopManager)
	local gui: any = self.gui
	if not self.isReady or not gui then
		if not self.gui then
			warn("ClientDealShopManager: the DealShop gui was not set up at startup, see the startup warning")
		elseif not self.config then
			warn("ClientDealShopManager: no deal shop config has arrived from the server")
		else
			warn("ClientDealShopManager: the deal shop interface failed to build, see the earlier warning")
		end
		return
	end

	self.panelOpen = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	self:updateTimeLimits()
	self.lastCoins = getCoins()
	self:refreshAllTierRecords()

	self.refreshConnect = RunService.Heartbeat:Connect(function()
		self:updateTimeLimits()

		local coins = getCoins()
		if coins ~= self.lastCoins then
			self.lastCoins = coins
			self:refreshCoinTierRecords()
		end
	end)

	gui.Enabled = true
end

function ClientDealShopManager.cleanupPanel(self: ClientDealShopManager)
	if not self.panelOpen then
		return
	end
	self.panelOpen = false

	local gui: any = self.gui
	gui.Enabled = false
	self:hideToolTip()

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.refreshConnect then
		self.refreshConnect:Disconnect()
		self.refreshConnect = nil
	end
end

function ClientDealShopManager.togglePanel(self: ClientDealShopManager)
	if self.panelOpen then
		self:cleanupPanel()
	else
		self:beginPanel()
	end
end

function ClientDealShopManager.init(self: ClientDealShopManager)
	-- authored in Studio, so a missing one must not hang client startup
	local playerGui = player:FindFirstChild("PlayerGui") :: Instance
	local gui: any = playerGui:FindFirstChild("DealShop")
	if not gui then
		warn("ClientDealShopManager: DealShop gui missing from PlayerGui; the deal shop is disabled")
		return
	end

	local main: any = gui:FindFirstChild("Main")
	local scroll: any = main and main:FindFirstChild("Scroll")
	local bundleTemplate: any = scroll and scroll:FindFirstChild("BundleDealCardTemplate")
	local singleItemTemplate: any = scroll and scroll:FindFirstChild("SingleItemDealCardTemplate")
	if not scroll or not bundleTemplate or not singleItemTemplate then
		local missingNames: { string } = {}
		if not main then
			table.insert(missingNames, "Main")
		elseif not scroll then
			table.insert(missingNames, "Main/Scroll")
		end
		if scroll and not bundleTemplate then
			table.insert(missingNames, "BundleDealCardTemplate")
		end
		if scroll and not singleItemTemplate then
			table.insert(missingNames, "SingleItemDealCardTemplate")
		end

		local foundNames: { string } = {}
		for _, child in (scroll or main or gui):GetChildren() do
			table.insert(foundNames, child.Name)
		end
		warn(`ClientDealShopManager: DealShop is missing {table.concat(missingNames, ", ")}; found [{table.concat(foundNames, ", ")}]; the deal shop is disabled`)
		return
	end

	-- the cards are built once at startup, so a respawn must not recreate the gui from StarterGui
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DISPLAY_ORDER
	self.gui = gui
	self.scroll = scroll

	bundleTemplate.Visible = false
	singleItemTemplate.Visible = false
	self.bundleTemplate = bundleTemplate
	self.singleItemTemplate = singleItemTemplate

	-- for future gacha deals; keep it out of the list
	local gachaTemplate: any = scroll:FindFirstChild("GachaDealCardTemplate")
	if gachaTemplate then
		gachaTemplate.Visible = false
	end

	self.mainFrame = main
	local toolTip: any = main:FindFirstChild("ToolTip")
	local toolTipLabel: any = toolTip and toolTip:FindFirstChild("ToolTipInfo")
	if toolTipLabel then
		-- the buy buttons must draw over the popup's background, and the contents list is rich text
		toolTip.ZIndex = 10
		toolTipLabel.ZIndex = 11
		toolTipLabel.RichText = true
		toolTip.Visible = false
		self.toolTipFrame = toolTip
		self.toolTipLabel = toolTipLabel
	elseif toolTip then
		toolTip.Visible = false
	end

	local sectionTabsFrame: any = utils.findFirstDescendant(gui, "SectionTabs")
	local sectionTabTemplate: any = sectionTabsFrame and utils.findFirstDescendant(sectionTabsFrame, "SectionTabTemplate")
	if sectionTabTemplate then
		sectionTabTemplate.Visible = false
		self.sectionTabsFrame = sectionTabsFrame
		self.sectionTabTemplate = sectionTabTemplate
	else
		warn("ClientDealShopManager: DealShop has no SectionTabs/SectionTabTemplate; every section is shown at once")
	end

	local title: any = main:FindFirstChild("Title")
	local exitButton: any = title and title:FindFirstChild("Exit")
	if exitButton then
		exitButton.Activated:Connect(function()
			self:cleanupPanel()
		end)
	end

	self:tryBuild()
end

function ClientDealShopManager.new(): ClientDealShopManager
	local self = setmetatable({} :: ClientDealShopManagerFields, ClientDealShopManager)

	self.gui = nil
	self.toolTipFrame = nil
	self.toolTipLabel = nil
	self.config = nil
	self.cardRecords = {}
	self.tierRecords = {}
	self.tabButtons = {}
	self.activeSectionKey = nil
	self.robuxPrices = {}
	self.unavailableProductIds = {}
	self.refreshConnect = nil
	self.lastCoins = nil
	self.nextPendingToken = 0
	self.purchasedDealKeys = {}
	self.panelOpen = false
	self.isReady = false
	self.hasAttemptedBuild = false

	return self
end

local singleton = ClientDealShopManager.new()

return singleton
