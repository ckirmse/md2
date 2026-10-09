--!strict

local ClientDragonRosterManager = {}
ClientDragonRosterManager.__index = ClientDragonRosterManager

local collectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance
local rosterGui: any = playerGui:WaitForChild("DragonRoster")

rosterGui.DisplayOrder = 130

local REFRESH_INTERVAL_SEC = 1

-- one per occupied stable slot: the cloned dragon card plus its element references, captured
-- once at creation so refreshes never re-scan the card's descendant tree (mirrors
-- ClientBuyStore's OfferRecord)
type CardRecord = {
	card: any,
	icon: any,
	name: any,
	income: any,
	fill: any,
	xpText: any,
	levelText: any,
}

type ClientDragonRosterManagerFields = {
	scroll: any,
	cardTemplate: any,
	rosterAmountText: any,
	cardRecords: { [number]: CardRecord }, -- keyed by itemId
	refreshConnect: RBXScriptConnection?,
	timeSinceRefresh: number,
}

export type ClientDragonRosterManager = typeof(setmetatable({} :: ClientDragonRosterManagerFields, ClientDragonRosterManager))

function ClientDragonRosterManager.getGuiRoot(self: ClientDragonRosterManager)
	return rosterGui
end

function ClientDragonRosterManager.getHudElements(self: ClientDragonRosterManager)
	return { }
end

function ClientDragonRosterManager.notifyForceEnd(self: ClientDragonRosterManager)
	self:cleanupRoster()
end

function ClientDragonRosterManager.notifyClickOutside(self: ClientDragonRosterManager)
	self:notifyForceEnd()
end

function ClientDragonRosterManager.doesWantBlur(self: ClientDragonRosterManager): boolean
	return false
end

-- collects the local player's occupied-stable-slot dragons, sorted by slot index (empty slots
-- have no tagged instance, so they never produce a card)
local function getOwnedSlottedDragons(): { any }
	local dragons = {}
	for _, shadow in collectionService:GetTagged(Tags.SHADOW_DRAGON) :: { any } do
		if shadow:GetAttribute(Attributes.USER_ID) ~= player.UserId then
			continue
		end
		if shadow:GetAttribute(Attributes.DRAGON_SLOT_INDEX) == nil then
			continue
		end
		table.insert(dragons, shadow)
	end

	table.sort(dragons, function(a, b)
		return (a:GetAttribute(Attributes.DRAGON_SLOT_INDEX) :: number)
			< (b:GetAttribute(Attributes.DRAGON_SLOT_INDEX) :: number)
	end)

	return dragons
end

-- creates the card for one dragon and captures its element references; static content (icon) is
-- set once here since a dragon's item name never changes after spawn
local function createCardRecord(self: ClientDragonRosterManager, dragon: any): CardRecord
	local card: any = self.cardTemplate:Clone()

	local itemName = dragon:GetAttribute(Attributes.ITEM_NAME) :: string?
	local icon: any = utils.findFirstDescendant(card, "Icon")
	local iconAssetId = itemName and ItemIcons.getItemIconAssetId(itemName)
	icon.Image = iconAssetId or ""
	icon.BackgroundTransparency = iconAssetId and 1 or 0

	local cardRecord: CardRecord = {
		card = card,
		icon = icon,
		name = utils.findFirstDescendant(card, "NameText"),
		income = utils.findFirstDescendant(card, "IncomeText"),
		fill = utils.findFirstDescendant(card, "FillBar"):WaitForChild("Fill"),
		xpText = utils.findFirstDescendant(card, "XpText"),
		levelText = utils.findFirstDescendant(card, "LevelText"),
	}

	card.Visible = true
	card.Parent = self.scroll

	return cardRecord
end

-- applies the per-refresh dynamic state (name, income, xp fraction, level) using the element
-- references captured at creation
local function refreshCardRecord(cardRecord: CardRecord, dragon: any)
	cardRecord.name.Text = (dragon:GetAttribute(Attributes.DISPLAY_NAME) :: string?) or ""

	local incomePerSec = (dragon:GetAttribute(Attributes.DRAGON_INCOME_PER_SEC) :: number?) or 0
	cardRecord.income.Text = string.format("$%s/s", utils.formatLargeInteger(math.floor(incomePerSec)))

	local level = (dragon:GetAttribute(Attributes.DRAGON_LEVEL) :: number?) or 1
	cardRecord.levelText.Text = string.format("Level: %d", level)

	local xp = (dragon:GetAttribute(Attributes.DRAGON_XP) :: number?) or 0
	local nextLevelXp = dragon:GetAttribute(Attributes.DRAGON_NEXT_LEVEL_XP) :: number?

	if nextLevelXp then
		local fillFrac = math.clamp(xp / nextLevelXp, 0, 1)
		cardRecord.fill.Size = UDim2.new(fillFrac, 0, cardRecord.fill.Size.Y.Scale, cardRecord.fill.Size.Y.Offset)
		cardRecord.xpText.Text = string.format("%d/%d", math.floor(xp), math.floor(nextLevelXp))
	else
		cardRecord.fill.Size = UDim2.new(1, 0, cardRecord.fill.Size.Y.Scale, cardRecord.fill.Size.Y.Offset)
		cardRecord.xpText.Text = "MAX"
	end
end

-- destroy-missing/create-new/refresh-existing reconciliation, keyed by item id (mirrors
-- ClientBuyStore.updateStoreInterface)
function ClientDragonRosterManager.refreshList(self: ClientDragonRosterManager)
	local dragons = getOwnedSlottedDragons()

	local currentItemIds: { [number]: boolean } = {}
	for _, dragon in dragons do
		currentItemIds[dragon:GetAttribute(Attributes.ITEM_ID) :: number] = true
	end
	for itemId, cardRecord in self.cardRecords do
		if not currentItemIds[itemId] then
			cardRecord.card:Destroy()
			self.cardRecords[itemId] = nil
		end
	end

	for i, dragon in dragons do
		local itemId = dragon:GetAttribute(Attributes.ITEM_ID) :: number
		local cardRecord = self.cardRecords[itemId]
		if not cardRecord then
			cardRecord = createCardRecord(self, dragon)
			self.cardRecords[itemId] = cardRecord
		end
		cardRecord.card.LayoutOrder = i
		refreshCardRecord(cardRecord, dragon)
	end

	local stableSlotCount = clientPlayerAttributesManager:getDragonSlotCount()
	self.rosterAmountText.Text = string.format("%d/%d", #dragons, stableSlotCount)
end

function ClientDragonRosterManager.beginRoster(self: ClientDragonRosterManager)
	rosterGui.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	self:refreshList()
	self.timeSinceRefresh = 0

	self.refreshConnect = RunService.Heartbeat:Connect(function(deltaTime: number)
		self.timeSinceRefresh += deltaTime
		if self.timeSinceRefresh < REFRESH_INTERVAL_SEC then
			return
		end
		self.timeSinceRefresh = 0
		self:refreshList()
	end)
end

function ClientDragonRosterManager.cleanupRoster(self: ClientDragonRosterManager)
	rosterGui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.refreshConnect then
		self.refreshConnect:Disconnect()
		self.refreshConnect = nil
	end
end

function ClientDragonRosterManager.toggleRoster(self: ClientDragonRosterManager)
	if rosterGui.Enabled then
		self:cleanupRoster()
	else
		self:beginRoster()
	end
end

function ClientDragonRosterManager.init(self: ClientDragonRosterManager)
	local scrollingFrame: any = utils.findFirstDescendant(rosterGui, "ScrollingFrame")
	self.scroll = scrollingFrame
	self.cardTemplate = utils.findFirstDescendant(scrollingFrame, "DragonCardTemplate")
	self.cardTemplate.Visible = false

	self.rosterAmountText = utils.findFirstDescendant(rosterGui, "RosterAmountText")

	local exitButton: any = utils.findFirstDescendant(rosterGui, "ExitButton")
	exitButton.Activated:Connect(function()
		self:cleanupRoster()
	end)
end

function ClientDragonRosterManager.new(): ClientDragonRosterManager
	local self = setmetatable({} :: ClientDragonRosterManagerFields, ClientDragonRosterManager)

	self.cardRecords = {}
	self.refreshConnect = nil
	self.timeSinceRefresh = 0

	return self
end

local singleton = ClientDragonRosterManager.new()

return singleton
