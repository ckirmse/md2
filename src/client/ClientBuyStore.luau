--!strict

local runService = game:GetService("RunService")

local ClientBuyStore = {}
ClientBuyStore.__index = ClientBuyStore

local guiService = game:GetService("GuiService")
local marketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Animations = GameAssets:WaitForChild("Animations")
local MainElements = GameAssets:WaitForChild("MainElements")
local BuyStore = MainElements:WaitForChild("BuyStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientAnalyticsManager = require("./ClientAnalyticsManager")
local Types = require("./Types")
local clientFtueManager = require("./ClientFtueManager")
local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local screenGuiManager = require("./ScreenGuiManager")

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GrayboxStore: any = PlayerGui:WaitForChild("BuyStore")

-- must stay above Satchel's BackpackGui.DisplayOrder (120, ClientLibs/Satchel/init.luau) so the shop renders in front of the backpack hotbar
GrayboxStore.DisplayOrder = 130

local GREETING_DISTANCE = 10
local GREETING_TIME_COOLDOWN = 5

-- the store auto-opens when the player gets this close to the vendor; deliberately smaller than
-- GREETING_DISTANCE (whose leave event closes the store) so the open/close thresholds have
-- hysteresis instead of flickering at one boundary
local AUTO_OPEN_DISTANCE = 8

-- If a button is renamed in Studio, update its key here too.
local CATEGORY_TAB_NAME_TO_SHOP_CATEGORY = {
	["Dragons"] = enums.ShopCategory.DRAGONS,
	["Plants"] = enums.ShopCategory.PLANTS,
}

-- element filter buttons are named after their color rather than the element itself
local COLOR_NAME_TO_PRIMARY_ELEMENT = {
	["Green"] = enums.PrimaryElements.NATURE,
	["Red"] = enums.PrimaryElements.FIRE,
	["Blue"] = enums.PrimaryElements.WATER,
}

-- This is to bypass shop filters. For testing purpose.
local DEBUG_SHOW_ALL_SHOP_ITEMS = false

-- how many offer cards the background pre-build creates before yielding a frame
local PREBUILD_OFFERS_PER_FRAME = 10

-- one per item in the store: the cloned offer card plus its element references, captured once at
-- creation so refreshes never re-scan the card's descendant tree. The gui elements are
-- Studio-authored, so they are untyped here. buttons are wired once at creation; their handlers
-- read inventoryData/buyContext, which refreshOfferRecord overwrites on every rebuild
type OfferRecord = {
	offer: any,
	numberAvailable: any,
	buy: any,
	buyPrice: any,
	buyMax: any,
	buyMaxPrice: any,
	buyDisabled: any,
	buyDisabledPrice: any,
	buyDisabledMessage: any,
	buyMaxDisabled: any,
	buyMaxDisabledPrice: any,
	buyMaxDisabledMessage: any,
	buyRobux: any,
	buyRobuxAmount: any,
	buyRobuxPrice: any,
	levelLocked: any,
	lockedMessage: any,
	inventoryData: any,
	buyContext: any,
}

type ClientBuyStoreFields = {
	proximityThresholdTracker: any,
	autoOpenTracker: any,
	rigHighlight: any,
	activeCategories: { [any]: any },
	activeElements: { [any]: any },
	activeRarities: { [any]: any },
	approachAnimationTrack: any,
	buyStore: any,
	buyStoreData: any,
	dialogFit: any,
	ftueCalloutTemplate: any,
	filterContainers: any,
	heartbeatConnect: any,
	idleAnimationTrack: any,
	isEnabled: boolean,
	isPrebuilding: boolean,
	offerRecords: { [string]: OfferRecord },
	offerTemplate: any,
	pendingPurchaseCount: number,
	prevGreetTime: any,
	restockLabel: any,
	robuxProductInfo: { [any]: any },
	scroll: any,
	singleItemMode: any,
}

export type ClientBuyStore = typeof(setmetatable({} :: ClientBuyStoreFields, ClientBuyStore))

function ClientBuyStore.getGuiRoot(self: ClientBuyStore)
	return GrayboxStore
end

function ClientBuyStore.notifyForceEnd(self: ClientBuyStore)
	self:cleanupStore()
end

function ClientBuyStore.notifyClickOutside(self: ClientBuyStore)
	self:notifyForceEnd()
end

function ClientBuyStore.getHudElements(self: ClientBuyStore)
	return { enums.HudElements.COINS, enums.HudElements.BACKPACK }
end

-- overlay protocol hook: walking into a vendor's auto-open zone is allowed to replace a store
-- overlay (so walking from one vendor to the other hands off), but never any other overlay
function ClientBuyStore.doAllowStoreAutoOpen(self: ClientBuyStore): boolean
	return true
end

-- opens the store as if the player had used the old proximity prompt; called from the auto-open
-- tracker's enter event and from setEnabled when the player is already standing in the zone
local function tryAutoOpenStore(self: ClientBuyStore)
	if not self.isEnabled then
		return
	end
	if GrayboxStore.Enabled then
		-- already open
		return
	end
	if not self.buyStoreData then
		-- no inventory from the server yet; the player can re-enter the zone once it arrives
		return
	end
	if not overlayTracker:canStoreAutoOpen() then
		return
	end

	self:updateStoreInterface()
	self:beginStore()
end

function ClientBuyStore.beginStore(self: ClientBuyStore)
	if self.heartbeatConnect then
		self.heartbeatConnect:Disconnect()
		self.heartbeatConnect = nil
	end

	if not self.buyStoreData then
		print("no buy store data yet")
		return
	end

	local restock = self.restockLabel

	self.heartbeatConnect = runService.PostSimulation:Connect(function(deltaTime)
		local nextEra = self.buyStoreData.nextEra

		local timeToNextEraSec = math.ceil(math.max(0, nextEra - workspace:GetServerTimeNow()))
		restock.Text = utils.convertDurationSecToString(timeToNextEraSec)
	end)

	local rig = self.buyStore:FindFirstChild("Rig")

	local audioBeginStore = rig:FindFirstChild("AudioBeginStore")
	audioBeginStore:Play()

	GrayboxStore.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	if self.singleItemMode then
		clientAnalyticsManager:logEvent(clientAnalyticsManager.Events.FtueOpenBuyStore, {})
	end
end

function ClientBuyStore.cleanupStore(self: ClientBuyStore)
	GrayboxStore.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.heartbeatConnect then
		self.heartbeatConnect:Disconnect()
		self.heartbeatConnect = nil
	end

	self:resetFilters()
end

function ClientBuyStore.initWorldInterface(self: ClientBuyStore)
	local buyStore: any = BuyStore:Clone()
	buyStore.Parent = workspace

	self.buyStore = buyStore

	-- the store now auto-opens on proximity; the prompt instance stays in the Studio-authored
	-- model but is permanently disabled
	local objProximityPrompt: any = utils.findFirstDescendant(buyStore, "ProximityPrompt")
	objProximityPrompt.Enabled = false

	local animation = Animations:FindFirstChild("StoreIdle")
	local rig = self.buyStore:FindFirstChild("Rig")
	local animator = rig:FindFirstChild("Humanoid"):WaitForChild("Animator")
	self.idleAnimationTrack = animator:LoadAnimation(animation)
	self.idleAnimationTrack:Play()

	-- cache the static Studio-authored elements once; the dialog's descendant tree grows large as
	-- offer cards are added, so repeated findFirstDescendant scans of it get expensive
	local DialogFit = GrayboxStore:WaitForChild("DialogFit")
	self.dialogFit = DialogFit
	self.scroll = utils.findFirstDescendant(DialogFit, "Scroll")
	self.restockLabel = utils.findFirstDescendant(DialogFit, "Restock")
	self.offerTemplate = utils.findFirstDescendant(DialogFit, "OfferTemplate")
	self.offerTemplate.Visible = false
	self.ftueCalloutTemplate = GrayboxStore:WaitForChild("FtueCalloutTemplate")

	self.rigHighlight = rig:FindFirstChild("Highlight")

	local rigPosition = rig:WaitForChild("HumanoidRootPart").Position

	self.proximityThresholdTracker = ProximityThresholdTracker.new(rigPosition, GREETING_DISTANCE)

	-- the highlight and greet/idle animation swaps used to ride on the prompt's
	-- PromptShown/PromptHidden; with the prompt gone they follow the greet threshold instead
	self.proximityThresholdTracker:getEnterEvent():Connect(function()
		if not self.isEnabled then
			return
		end

		self.rigHighlight.Enabled = true

		if (workspace:GetServerTimeNow() - self.prevGreetTime) < GREETING_TIME_COOLDOWN then
			return
		end

		self.prevGreetTime = workspace:GetServerTimeNow()

		if not self.approachAnimationTrack then
			local animation = Animations:FindFirstChild("StoreApproach")
			local animator = rig:WaitForChild("Humanoid"):WaitForChild("Animator")
			self.approachAnimationTrack = animator:LoadAnimation(animation)
		end

		local fadeTime = 0.2
		self.idleAnimationTrack:Stop(fadeTime)
		task.wait(fadeTime)
		self.approachAnimationTrack:Play()

		local audioHello = rig:FindFirstChild("AudioHello")
		audioHello:Play()
	end)

	self.proximityThresholdTracker:getLeaveEvent():Connect(function()
		self.rigHighlight.Enabled = false

		if GrayboxStore.Enabled then
			self:cleanupStore()
		end

		if self.approachAnimationTrack then
			local fadeTime = 0.2
			self.approachAnimationTrack:Stop(fadeTime)
			task.wait(fadeTime)
			self.idleAnimationTrack:Play()
		end
	end)

	self.autoOpenTracker = ProximityThresholdTracker.new(rigPosition, AUTO_OPEN_DISTANCE)

	self.autoOpenTracker:getEnterEvent():Connect(function()
		tryAutoOpenStore(self)
	end)

	local activatedButton: any = utils.findFirstDescendant(DialogFit, "ExitButton")
	activatedButton.Activated:Connect(function()
		local audioClick = rig:FindFirstChild("AudioClick")
		audioClick:Play()

		self:cleanupStore()
	end)

	self:initFilterButtons(DialogFit)
end

function ClientBuyStore.calculateIsLevelLocked(self: ClientBuyStore, inventoryData: any)
	local isLevelLocked
	if inventoryData.playerAttributeKeyIsUnlocked == "" then
		isLevelLocked = false
	else
		isLevelLocked = not clientPlayerAttributesManager:get(inventoryData.playerAttributeKeyIsUnlocked)
	end

	if not isLevelLocked then
		if inventoryData.playerAttributeKeyLevel ~= "" then
			isLevelLocked = clientPlayerAttributesManager:get(inventoryData.playerAttributeKeyLevel)
				< inventoryData.minElementLevel
		end
	end
	return isLevelLocked
end

function ClientBuyStore.tryBuy(self: ClientBuyStore, inventoryData: any)
	local rig = self.buyStore:FindFirstChild("Rig")

	-- clone the sound so multiple could happen in parallel
	local audioBuyEvent = rig:FindFirstChild("AudioBuyEvent"):Clone()
	audioBuyEvent.Parent = rig
	audioBuyEvent.Ended:Connect(function()
		audioBuyEvent:Destroy()
	end)
	audioBuyEvent:Play()

	self.pendingPurchaseCount += 1

	local purchases = self.buyStoreData.purchases

	-- optimistically assume purchase will succeed; if it fails, we reset all purchase counts then
	if not purchases[inventoryData.itemName] then
		purchases[inventoryData.itemName] = 0
	end
	purchases[inventoryData.itemName] += 1

	RemoteEvents.TryBuyItemName:FireServer(inventoryData.itemName)

	self:updateStoreInterface()
end

function ClientBuyStore.tryBuyMax(self: ClientBuyStore, inventoryData: any)
	local rig = self.buyStore:FindFirstChild("Rig")

	local audioBuyEvent = rig:FindFirstChild("AudioBuyEvent"):Clone()
	audioBuyEvent.Parent = rig
	audioBuyEvent.Ended:Connect(function()
		audioBuyEvent:Destroy()
	end)
	audioBuyEvent:Play()

	self.pendingPurchaseCount += 1

	local purchases = self.buyStoreData.purchases
	local coins = clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS)
	local purchasedCount = purchases[inventoryData.itemName] or 0
	local remainingCount = math.max(0, inventoryData.count - purchasedCount)
	local maxAffordable = math.floor(coins / inventoryData.coins)
	local optimisticQuantity = math.min(remainingCount, maxAffordable)

	-- optimistically assume purchase will succeed; server corrects us via notifyBuyMaxStatus if not
	purchases[inventoryData.itemName] = purchasedCount + optimisticQuantity

	RemoteEvents.TryBuyMaxItemName:FireServer(inventoryData.itemName)

	self:updateStoreInterface()
end

function ClientBuyStore.tryBuyWithRobux(self: ClientBuyStore, inventoryData: any)
	local isSuccess, errorMessage = pcall(function()
		marketplaceService:PromptProductPurchase(player, inventoryData.robuxProductId)
	end)

	if isSuccess then
		--print("yes prompted")
	else
		warn("error prompting for robux purchase", errorMessage)
	end

	self:updateStoreInterface()
end

function ClientBuyStore.tryBuyDisabled(self: ClientBuyStore, inventoryData: any, isLevelLocked: any, hasInventory: any, hasEnoughMoney: any)
	local rig = self.buyStore:FindFirstChild("Rig")

	-- clone the sound so multiple could happen in parallel
	local audioInvalidClick = rig:FindFirstChild("AudioInvalidClick"):Clone()
	audioInvalidClick.Parent = rig
	audioInvalidClick.Ended:Connect(function()
		audioInvalidClick:Destroy()
	end)
	audioInvalidClick:Play()

	if isLevelLocked then
		screenGuiManager:showSystemMessage("Your elemental level is not high enough to buy this")
	elseif not hasInventory then
		screenGuiManager:showSystemMessage("The store is out of inventory of this")
	elseif not hasEnoughMoney then
		screenGuiManager:showSystemMessage("You need more coins to buy this")
	else
		screenGuiManager:showSystemMessage("You cannot buy this right now")
	end
end

-- shared active-state visual for all filter buttons (rarity, category, element)
local function setFilterButtonActive(button, isActive)
	local stroke = button:FindFirstChildOfClass("UIStroke")

	if stroke then
		stroke.Transparency = isActive and 0 or 1
	end
end

-- clears filter state and visuals; called when the store closes so each new visit starts unfiltered
function ClientBuyStore.resetFilters(self: ClientBuyStore)
	self.activeRarities = {}
	self.activeCategories = {}
	self.activeElements = {}

	if not self.filterContainers then
		return
	end

	for _, container in self.filterContainers do
		for _, button in container:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			setFilterButtonActive(button, false)
		end
	end
end

function ClientBuyStore.applyStoreFilters(self: ClientBuyStore)
	local hasRarityFilter = next(self.activeRarities) ~= nil
	local hasCategoryFilter = next(self.activeCategories) ~= nil
	local hasElementFilter = next(self.activeElements) ~= nil

	for _, offerRecord in self.offerRecords do
		local offer = offerRecord.offer

		if DEBUG_SHOW_ALL_SHOP_ITEMS or clientFtueManager:isFtueActive() then
			offer.Visible = true
			continue
		end

		-- rarity, category, and element are all multi-select: with none toggled on, everything passes
		local passesRarity = true
		if hasRarityFilter then
			local rarity = offer:GetAttribute(Attributes.RARITY)
			passesRarity = rarity ~= nil and self.activeRarities[rarity] == true
		end

		local passesCategory = true
		if hasCategoryFilter then
			local category = offer:GetAttribute(Attributes.SHOP_CATEGORY)
			passesCategory = category ~= nil and self.activeCategories[category] == true
		end

		local passesElement = true
		if hasElementFilter then
			local primaryElement = offer:GetAttribute(Attributes.PRIMARY_ELEMENT)
			passesElement = primaryElement ~= nil and self.activeElements[primaryElement] == true
		end

		offer.Visible = passesRarity and passesCategory and passesElement
	end
end

function ClientBuyStore.onRarityFilterButtonClicked(self: ClientBuyStore, rarityValue: any, button: any)
	if self.activeRarities[rarityValue] then
		self.activeRarities[rarityValue] = nil
	else
		self.activeRarities[rarityValue] = true
	end

	setFilterButtonActive(button, self.activeRarities[rarityValue] == true)
	self:applyStoreFilters()
end

function ClientBuyStore.onCategoryFilterButtonClicked(self: ClientBuyStore, categoryValue: any, button: any)
	if self.activeCategories[categoryValue] then
		self.activeCategories[categoryValue] = nil
	else
		self.activeCategories[categoryValue] = true
	end

	setFilterButtonActive(button, self.activeCategories[categoryValue] == true)
	self:applyStoreFilters()
end

function ClientBuyStore.onElementFilterButtonClicked(self: ClientBuyStore, elementValue: any, button: any)
	if self.activeElements[elementValue] then
		self.activeElements[elementValue] = nil
	else
		self.activeElements[elementValue] = true
	end

	setFilterButtonActive(button, self.activeElements[elementValue] == true)
	self:applyStoreFilters()
end

-- wires up the rarity/category/element filter buttons authored in Studio; button Name is the source of truth for which enum value each one represents
function ClientBuyStore.initFilterButtons(self: ClientBuyStore, DialogFit: any)
	local rarityFilters: any = utils.findFirstDescendant(DialogFit, "RarityFilters")
	if rarityFilters then
		for _, button in rarityFilters:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			local rarityValue = (enums.Rarity :: { [string]: any })[string.upper(button.Name)]
			if not rarityValue then
				warn("rarity filter button name doesn't match a Rarity enum key", button.Name)
				continue
			end

			setFilterButtonActive(button, false)

			button.Activated:Connect(function()
				self:onRarityFilterButtonClicked(rarityValue, button)
			end)
		end
	end

	local categoryFilters: any = utils.findFirstDescendant(DialogFit, "CategoryFilters")
	if categoryFilters then
		for _, button in categoryFilters:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			local categoryValue = CATEGORY_TAB_NAME_TO_SHOP_CATEGORY[button.Name]
			if not categoryValue then
				warn("category button name doesn't match a known ShopCategory", button.Name)
				continue
			end

			setFilterButtonActive(button, false)

			button.Activated:Connect(function()
				self:onCategoryFilterButtonClicked(categoryValue, button)
			end)
		end
	end

	local colorFilters: any = utils.findFirstDescendant(DialogFit, "ColorFilters")
	if colorFilters then
		for _, button in colorFilters:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			local elementValue = COLOR_NAME_TO_PRIMARY_ELEMENT[button.Name]
			if not elementValue then
				warn("element filter button name doesn't match a known color", button.Name)
				continue
			end

			setFilterButtonActive(button, false)

			button.Activated:Connect(function()
				self:onElementFilterButtonClicked(elementValue, button)
			end)
		end
	end

	-- cached so setFilterUIVisible doesn't need to re-scan DialogFit's (large, offer-clone-heavy) descendant tree on every refresh
	self.filterContainers = { rarityFilters, categoryFilters, colorFilters }
end

-- hides the filter UI and blocks input on it (all input methods, not just mouse) so it can't affect what's shown during FTUE
function ClientBuyStore.setFilterUIVisible(self: ClientBuyStore, isVisible: any)
	for _, container in self.filterContainers do
		container.Visible = isVisible

		for _, button in container:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			button.Active = isVisible
		end
	end
end

-- creates the offer card for one store item and captures its element references. Static content
-- (icon, name, description, rarity, filter attributes) and button handlers are set exactly once
-- here; the handlers read the record's inventoryData/buyContext at click time, which
-- refreshOfferRecord overwrites on every rebuild, so nothing is ever reconnected. The card is
-- created invisible; refreshOfferRecord shows it.
-- (these three helpers are local functions, not methods, so OfferRecord stays out of the
-- generated cross-module interface in Types.luau)
local function createOfferRecord(self: ClientBuyStore, inventoryData: any): OfferRecord
	local offer: any = self.offerTemplate:Clone()
	offer.Name = inventoryData.itemName

	local icon: any = utils.findFirstDescendant(offer, "Icon")
	if not icon then
		warn("ClientBuyStore: offer template has no Icon ImageLabel", inventoryData.itemName)
	else
		icon.Visible = true
		local iconAssetId = ItemIcons.getItemIconAssetId(inventoryData.itemName)
		icon.Image = iconAssetId or ""
		icon.BackgroundTransparency = iconAssetId and 1 or 0
	end

	local name: any = utils.findFirstDescendant(offer, "Name")
	name.Text = inventoryData.buyName
	local description: any = utils.findFirstDescendant(offer, "Description")
	description.Text = inventoryData.description
	local rarity: any = utils.findFirstDescendant(offer, "Rarity")
	rarity.Text = enums.getPublicName(enums.Rarity, inventoryData.rarity)
	rarity.TextColor3 = utils.getColorForRarity(inventoryData.rarity)
	local rarityStroke: any = utils.findFirstDescendant(offer, "RarityStroke")
	rarityStroke.Color = utils.getColorForRarity(inventoryData.rarity)

	offer:SetAttribute(Attributes.RARITY, inventoryData.rarity)
	offer:SetAttribute(Attributes.SHOP_CATEGORY, inventoryData.category)
	offer:SetAttribute(Attributes.PRIMARY_ELEMENT, inventoryData.primaryElement)
	offer:SetAttribute(Attributes.ITEM_NAME, inventoryData.itemName)

	local buy: any = utils.findFirstDescendant(offer, "Buy")
	local buyMax: any = utils.findFirstDescendant(offer, "BuyMax")
	local buyDisabled: any = utils.findFirstDescendant(offer, "BuyDisabled")
	local buyMaxDisabled: any = utils.findFirstDescendant(offer, "BuyMaxDisabled")
	local buyRobux: any = utils.findFirstDescendant(offer, "BuyRobux")
	local levelLocked: any = utils.findFirstDescendant(offer, "LevelLocked")

	local offerRecord: OfferRecord = {
		offer = offer,
		numberAvailable = utils.findFirstDescendant(offer, "NumberAvailable"),
		buy = buy,
		buyPrice = utils.findFirstDescendant(buy, "Price"),
		buyMax = buyMax,
		buyMaxPrice = utils.findFirstDescendant(buyMax, "Price"),
		buyDisabled = buyDisabled,
		buyDisabledPrice = utils.findFirstDescendant(buyDisabled, "Price"),
		buyDisabledMessage = buyDisabled:FindFirstChild("DisabledMessage"),
		buyMaxDisabled = buyMaxDisabled,
		buyMaxDisabledPrice = utils.findFirstDescendant(buyMaxDisabled, "Price"),
		buyMaxDisabledMessage = buyMaxDisabled:FindFirstChild("DisabledMessage"),
		buyRobux = buyRobux,
		buyRobuxAmount = utils.findFirstDescendant(buyRobux, "Amount"),
		buyRobuxPrice = utils.findFirstDescendant(buyRobux, "Price"),
		levelLocked = levelLocked,
		lockedMessage = levelLocked:FindFirstChild("LockedMessage"),
		inventoryData = inventoryData,
		buyContext = nil,
	}

	-- each button is only visible in the state where its action is legal, so the buyContext
	-- checks below are just insurance against a click racing a refresh
	offer.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if not buyContext then
			return
		end
		if buyContext.canBuy then
			self:tryBuy(offerRecord.inventoryData)
		else
			self:tryBuyDisabled(offerRecord.inventoryData, buyContext.isLevelLocked, buyContext.hasInventory, buyContext.hasEnoughMoney)
		end
	end)

	buy.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if buyContext and buyContext.canBuy then
			self:tryBuy(offerRecord.inventoryData)
		end
	end)

	buyMax.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if buyContext and buyContext.canBuy then
			self:tryBuyMax(offerRecord.inventoryData)
		end
	end)

	buyDisabled.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if buyContext and not buyContext.canBuy then
			self:tryBuyDisabled(offerRecord.inventoryData, buyContext.isLevelLocked, buyContext.hasInventory, buyContext.hasEnoughMoney)
		end
	end)

	buyMaxDisabled.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if buyContext and not buyContext.canBuy then
			self:tryBuyDisabled(offerRecord.inventoryData, buyContext.isLevelLocked, buyContext.hasInventory, buyContext.hasEnoughMoney)
		end
	end)

	buyRobux.Activated:Connect(function()
		local buyContext = offerRecord.buyContext
		if not buyContext then
			return
		end
		if buyContext.isLevelLocked then
			self:tryBuyDisabled(offerRecord.inventoryData, buyContext.isLevelLocked, buyContext.hasInventory, buyContext.hasEnoughMoney)
		else
			self:tryBuyWithRobux(offerRecord.inventoryData)
		end
	end)

	offer.Parent = self.scroll
	self.offerRecords[inventoryData.itemName] = offerRecord

	return offerRecord
end

-- applies the per-rebuild dynamic state (stock, prices, lock state, button visibility, FTUE
-- callout) to an existing offer card, using the element references captured at creation
local function refreshOfferRecord(self: ClientBuyStore, offerRecord: OfferRecord, inventoryData: any, layoutOrder: number, purchases: any, selectedItemName: any)
	local offer = offerRecord.offer

	offerRecord.inventoryData = inventoryData

	local ftueChild = offer:FindFirstChild("FtueCallout")
	if ftueChild then
		ftueChild:Destroy()
	end

	offer.Visible = true
	offer.LayoutOrder = layoutOrder

	local purchasedCount = purchases[inventoryData.itemName] or 0
	local remainingCount = math.max(0, inventoryData.count - purchasedCount)
	offerRecord.numberAvailable.Text = tostring(remainingCount)

	local coins = clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS)
	local hasEnoughMoney = coins >= inventoryData.coins

	-- later we can allow restocking for Robux, but we don't have it for now
	local hasInventory = (remainingCount > 0)

	local isLevelLocked = self:calculateIsLevelLocked(inventoryData)

	local isFtueLocked = false
	if self.singleItemMode then
		if inventoryData.itemName ~= self.singleItemMode.itemName then
			isFtueLocked = true
		end
	end

	local canBuy = hasEnoughMoney and hasInventory and not isLevelLocked and not isFtueLocked
	offerRecord.buyContext = {
		canBuy = canBuy,
		isLevelLocked = isLevelLocked,
		hasInventory = hasInventory,
		hasEnoughMoney = hasEnoughMoney,
	}

	if isLevelLocked then
		offerRecord.lockedMessage.Text = string.format("Requires Elemental Level %i", inventoryData.minElementLevel)
		if inventoryData.unlockElement and inventoryData.unlockElement ~= enums.PrimaryElements.NONE then
			offerRecord.lockedMessage.TextColor3 = utils.get2DColorForPrimaryElement(inventoryData.unlockElement)
			offerRecord.lockedMessage.BorderColor3 =
				utils.getContrastingColor(utils.get2DColorForPrimaryElement(inventoryData.unlockElement))
		end

		offerRecord.levelLocked.Visible = true
	else
		offerRecord.levelLocked.Visible = false
	end

	local isFtueActive = clientFtueManager:isFtueActive()

	local robuxPrice
	local robuxCount
	if self.robuxProductInfo[inventoryData.itemName] and inventoryData.robuxCount then
		robuxPrice = self.robuxProductInfo[inventoryData.itemName].robuxPrice
		robuxCount = inventoryData.robuxCount
	end

	if robuxPrice and not isFtueActive then
		offerRecord.buyRobux.Visible = true
		offerRecord.buyRobuxAmount.Text = string.format("%ix", robuxCount)
		offerRecord.buyRobuxPrice.Text = tostring(robuxPrice)
	else
		offerRecord.buyRobux.Visible = false
	end

	if canBuy then
		offerRecord.buy.Visible = true
		offerRecord.buyMax.Visible = not isFtueActive
		offerRecord.buyDisabled.Visible = false
		offerRecord.buyMaxDisabled.Visible = false
		offerRecord.buyPrice.Text = tostring(inventoryData.coins)
		local maxAffordable = math.floor(coins / inventoryData.coins)
		local maxQuantity = math.min(remainingCount, maxAffordable)
		offerRecord.buyMaxPrice.Text = tostring(inventoryData.coins * maxQuantity)
	else
		offerRecord.buy.Visible = false
		offerRecord.buyMax.Visible = false
		offerRecord.buyDisabled.Visible = true
		offerRecord.buyMaxDisabled.Visible = not isFtueActive
		offerRecord.buyDisabledPrice.Text = tostring(inventoryData.coins)
		offerRecord.buyMaxDisabledPrice.Text = tostring(inventoryData.coins)

		if not hasEnoughMoney or not hasInventory then
			if not hasInventory then
				offerRecord.buyDisabledMessage.Text = "OUT OF STOCK"
				offerRecord.buyMaxDisabledMessage.Text = "OUT OF STOCK"
			else
				offerRecord.buyDisabledMessage.Text = "NOT ENOUGH COINS"
				offerRecord.buyMaxDisabledMessage.Text = "NOT ENOUGH COINS"
			end
			offerRecord.buyDisabledMessage.Visible = true
			offerRecord.buyMaxDisabledMessage.Visible = true
		else
			offerRecord.buyDisabledMessage.Visible = false
			offerRecord.buyMaxDisabledMessage.Visible = false
		end
	end

	if inventoryData.itemName == selectedItemName then
		-- this tries to maintain selection (gamepad thing) when we rebuild the list here
		offer.Selected = true
		guiService:Select(offer)
	end

	if self.singleItemMode then
		if inventoryData.itemName == self.singleItemMode.itemName then
			local ftueCallout: any = self.ftueCalloutTemplate:Clone()
			ftueCallout.Name = "FtueCallout"
			ftueCallout.Visible = true

			-- by parenting this ftue callout to the offer, we can put it just to the side and it'll always be laid out right
			ftueCallout.Position = UDim2.new(1, 0, 0, 0)
			ftueCallout.Size = UDim2.new(0, 180, 0, 108)
			ftueCallout.Parent = offer

			local textLabel = ftueCallout:FindFirstChild("TextLabel")
			textLabel.Text = self.singleItemMode.text
		end
	end
end

-- builds the offer cards a few per frame in the background so the first shop open finds them
-- already cached instead of cloning all of them in a single frame
local function prebuildOfferRecords(self: ClientBuyStore)
	if self.isPrebuilding then
		return
	end
	self.isPrebuilding = true

	task.spawn(function()
		-- capture the array; a restock swapping buyStoreData mid-build is fine because records
		-- are keyed by item name and updateStoreInterface reconciles against the latest data
		local inventoryDatas = self.buyStoreData.inventoryDatas
		local createdSinceWait = 0
		for _, inventoryData in inventoryDatas do
			if GrayboxStore.Enabled then
				-- the store opened mid-build; updateStoreInterface creates anything still missing
				break
			end
			if not self.offerRecords[inventoryData.itemName] then
				createOfferRecord(self, inventoryData)
				createdSinceWait += 1
				if createdSinceWait >= PREBUILD_OFFERS_PER_FRAME then
					createdSinceWait = 0
					task.wait()
				end
			end
		end
		self.isPrebuilding = false
	end)
end

function ClientBuyStore.updateStoreInterface(self: ClientBuyStore)
	local selectedObject = guiService.SelectedObject
	local selectedItemName
	if selectedObject then
		--print("what's currently selected is", selectedObject, selectedObject.Name)
		selectedItemName = selectedObject:GetAttribute(Attributes.ITEM_NAME)
	end
	--print("have selected item name, should maintain this", selectedItemName)

	if not self.buyStoreData then
		warn("ClientBuyStore: buyStoreData not yet received from server")
		return
	end

	local inventoryDatas = self.buyStoreData.inventoryDatas
	if not inventoryDatas then
		warn("cannot update store interface with no inventory datas")
		return
	end

	local purchases = self.buyStoreData.purchases

	self:setFilterUIVisible(not clientFtueManager:isFtueActive())

	if self.singleItemMode then
		self.scroll.ScrollingEnabled = false
	else
		self.scroll.ScrollingEnabled = true
	end

	-- drop cards for items no longer sold (destroying the card also disconnects its handlers)
	local currentItemNames = {}
	for _, inventoryData in inventoryDatas do
		currentItemNames[inventoryData.itemName] = true
	end
	for itemName, offerRecord in self.offerRecords do
		if not currentItemNames[itemName] then
			offerRecord.offer:Destroy()
			self.offerRecords[itemName] = nil
		end
	end

	for i, inventoryData in inventoryDatas do
		local offerRecord = self.offerRecords[inventoryData.itemName]
		if not offerRecord then
			offerRecord = createOfferRecord(self, inventoryData)
		end
		refreshOfferRecord(self, offerRecord, inventoryData, i, purchases, selectedItemName)
	end

	self:applyStoreFilters()
end

function ClientBuyStore.notifyBuyStatus(self: ClientBuyStore, isSuccess: any, purchases: any)
	self.pendingPurchaseCount -= 1

	if isSuccess then
		--print("buy status success, no need to update anything because we optimistically updated our purchases already")
		clientFtueManager:notifyBuySuccessful()
		return
	end

	self.buyStoreData.purchases = purchases
end

function ClientBuyStore.notifyBuyMaxStatus(self: ClientBuyStore, successCount: any, purchases: any)
	self.pendingPurchaseCount -= 1

	-- always sync to authoritative server purchases since actual quantity may differ from optimistic estimate
	self.buyStoreData.purchases = purchases

	if successCount > 0 then
		clientFtueManager:notifyBuySuccessful()
	end

	self:updateStoreInterface()
end

function ClientBuyStore.queryRobuxProductInfo(self: ClientBuyStore)
	--print("querying robux product info")

	local inventoryDatas = self.buyStoreData.inventoryDatas
	if not inventoryDatas then
		warn("cannot get robux info with no inventory data")
		return
	end

	for _, inventoryData in inventoryDatas do
		--print("querying robux product info", inventoryData.itemName)
		if inventoryData.robuxProductId and inventoryData.robuxCount then
			task.defer(function()
				local isSuccess, productInfo = pcall(function()
					return marketplaceService:GetProductInfoAsync(inventoryData.robuxProductId, Enum.InfoType.Product)
				end)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						self.robuxProductInfo[inventoryData.itemName] = {
							robuxPrice = productInfo.PriceInRobux,
						}
					else
						print("product not for robux sale", inventoryData.itemName, productInfo)
					end
				end
			end)
		end
	end

	--print("querying robux product info kicked off")
end

function ClientBuyStore.setBuyStoreData(self: ClientBuyStore, buyStoreData: any)
	self.buyStoreData = buyStoreData

	-- sort the inventoryDatas by whether or not they are level locked for us; use the order the server gave us as tie breaker

	local inventoryDatas = utils.shallowCopy(self.buyStoreData.inventoryDatas)
	table.sort(inventoryDatas, function(a, b)
		local aIsLevelLocked = self:calculateIsLevelLocked(a)
		local bIsLevelLocked = self:calculateIsLevelLocked(b)
		if not aIsLevelLocked and bIsLevelLocked then
			return true
		end
		if aIsLevelLocked and not bIsLevelLocked then
			return false
		end

		-- use existing order otherwise
		local aIndex: number?
		for i, inventoryData in self.buyStoreData.inventoryDatas do
			if a.itemName == inventoryData.itemName then
				aIndex = i
				break
			end
		end
		local bIndex: number?
		for i, inventoryData in self.buyStoreData.inventoryDatas do
			if b.itemName == inventoryData.itemName then
				bIndex = i
				break
			end
		end

		--print("a", a.itemName, aIndex, "b", b.itemName, bIndex)
		return (aIndex :: number) < (bIndex :: number)
	end)

	self.buyStoreData.inventoryDatas = inventoryDatas

	task.spawn(function()
		-- we could wipe the old info, but it's probably still valid--we just let it stay for now
		-- restocking should just affect inventory, not list of what's actually in the store
		--self.robuxProductInfo = {}
		self:queryRobuxProductInfo()
	end)
	if GrayboxStore.Enabled then
		--print("updating buy store with", buyStoreData)
		self:updateStoreInterface()
	else
		-- build the offer cards ahead of time, spread over frames, so the first open doesn't
		-- pay for cloning all of them in the prompt handler's single frame
		prebuildOfferRecords(self)
	end
end

function ClientBuyStore.notifyPlayerCoinsChanged(self: ClientBuyStore)
	if GrayboxStore.Enabled then
		--print("updating store interface coins changed")
		self:updateStoreInterface()
	end
end

function ClientBuyStore.notifyPlayerLevelChanged(self: ClientBuyStore)
	-- not sure how you could gain a level while the store is up, but this will enable anything now unlocked if it happens
	if GrayboxStore.Enabled then
		--print("updating store interface level")
		self:updateStoreInterface()
	end
end

function ClientBuyStore.setFtueSingleItemMode(self: ClientBuyStore, itemName: any, text: any)
	self.singleItemMode = {
		itemName = itemName,
		text = text,
	}

	if GrayboxStore.Enabled then
		self:updateStoreInterface()
	end
end

function ClientBuyStore.clearFtueSingleItemMode(self: ClientBuyStore)
	self.singleItemMode = nil

	if GrayboxStore.Enabled then
		self:updateStoreInterface()
	end
end

function ClientBuyStore.setEnabled(self: ClientBuyStore)
	self.isEnabled = true

	-- if the player is already standing in the auto-open zone when the store becomes enabled
	-- (e.g. an FTUE step change), no enter edge will fire, so open it here
	if self.autoOpenTracker and self.autoOpenTracker:isInProximity() then
		tryAutoOpenStore(self)
	end
end

function ClientBuyStore.setDisabled(self: ClientBuyStore)
	self.isEnabled = false

	if self.rigHighlight then
		self.rigHighlight.Enabled = false
	end
end

function ClientBuyStore.init(self: ClientBuyStore)

	self:initWorldInterface()
end

function ClientBuyStore.new(): ClientBuyStore
	local self = setmetatable({} :: ClientBuyStoreFields, ClientBuyStore)

	self.isEnabled = true

	self.buyStoreData = nil

	self.robuxProductInfo = {}

	self.singleItemMode = nil

	self.heartbeatConnect = nil

	self.pendingPurchaseCount = 0

	self.prevGreetTime = 0

	self.autoOpenTracker = nil
	self.rigHighlight = nil

	-- map from itemName to its offer card and cached element references
	self.offerRecords = {}
	self.isPrebuilding = false

	self.activeRarities = {}
	self.activeCategories = {}
	self.activeElements = {}

	return self
end

local singleton = ClientBuyStore.new()

return singleton
