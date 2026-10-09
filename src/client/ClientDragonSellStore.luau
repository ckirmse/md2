--!strict

local runService = game:GetService("RunService")

local ClientDragonSellStore = {}
ClientDragonSellStore.__index = ClientDragonSellStore

local collectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
local DragonSellStoreTemplate = MainElements:WaitForChild("DragonSellStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local clientRideController = require("./ClientRideController")
local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local DragonSellStoreGui: any = PlayerGui:WaitForChild("DragonSellStore")

-- must stay above Satchel's BackpackGui.DisplayOrder (120)
DragonSellStoreGui.DisplayOrder = 130

local GREETING_DISTANCE = 10
local AUTO_OPEN_DISTANCE = 8
local REFRESH_INTERVAL_SEC = 1

type SellSectionRecord = {
	sellButton: any,
	confirmButton: any,
	cancelButton: any,
	label: any,
	pendingConfirm: boolean,
}

type ClientDragonSellStoreFields = {
	proximityThresholdTracker: any,
	autoOpenTracker: any,
	rigHighlight: any,
	dragonSellStore: any,
	dialogFit: any,
	riddenSection: SellSectionRecord?,
	backpackSection: SellSectionRecord?,
	refreshConnect: RBXScriptConnection?,
	timeSinceRefresh: number,
	isEnabled: boolean,
}

export type ClientDragonSellStore = typeof(setmetatable({} :: ClientDragonSellStoreFields, ClientDragonSellStore))

function ClientDragonSellStore.getGuiRoot(self: ClientDragonSellStore)
	return DragonSellStoreGui
end

function ClientDragonSellStore.notifyForceEnd(self: ClientDragonSellStore)
	self:cleanupStore()
end

function ClientDragonSellStore.notifyClickOutside(self: ClientDragonSellStore)
	self:notifyForceEnd()
end

function ClientDragonSellStore.getHudElements(self: ClientDragonSellStore)
	return { enums.HudElements.COINS, enums.HudElements.BACKPACK }
end

function ClientDragonSellStore.doAllowStoreAutoOpen(self: ClientDragonSellStore): boolean
	return true
end

-- the local player's own dragons
local function getOwnedDragons(): { any }
	local dragons = {}
	for _, shadow in collectionService:GetTagged(Tags.SHADOW_DRAGON) :: { any } do
		if shadow:GetAttribute(Attributes.USER_ID) ~= player.UserId then
			continue
		end
		table.insert(dragons, shadow)
	end
	return dragons
end

-- mirrors the server's sell-all selection so the preview matches what actually happens
local function getBackpackSellPreview(ownedDragons: { any }, ridingObj: any): (number, number, number)
	local ridingShadow = ridingObj
	local occupiedSlotCount = 0
	local backpackDragons = {}

	for _, shadow in ownedDragons do
		if shadow:GetAttribute(Attributes.DRAGON_SLOT_INDEX) ~= nil then
			occupiedSlotCount += 1
			continue
		end
		if shadow == ridingShadow then
			continue
		end
		table.insert(backpackDragons, shadow)
	end

	table.sort(backpackDragons, function(a, b)
		return (a:GetAttribute(Attributes.DRAGON_INCOME_PER_SEC) :: number? or 0)
			> (b:GetAttribute(Attributes.DRAGON_INCOME_PER_SEC) :: number? or 0)
	end)

	local stableSlotCount = clientPlayerAttributesManager:getDragonSlotCount()
	local freeSlotCount = stableSlotCount - occupiedSlotCount
	local spareCount = math.clamp(freeSlotCount, 0, #backpackDragons)

	local sellCount = 0
	local totalValue = 0
	for i = spareCount + 1, #backpackDragons do
		sellCount += 1
		totalValue += (backpackDragons[i]:GetAttribute(Attributes.DRAGON_SELL_VALUE) :: number? or 0)
	end

	return sellCount, totalValue, spareCount
end

function ClientDragonSellStore.updateStoreInterface(self: ClientDragonSellStore)
	local riddenSection = self.riddenSection :: SellSectionRecord
	local backpackSection = self.backpackSection :: SellSectionRecord

	local isRiding = clientRideController:isRiding()

	if not riddenSection.pendingConfirm then
		riddenSection.sellButton.Visible = isRiding
		riddenSection.cancelButton.Visible = false
		riddenSection.confirmButton.Visible = false

		if isRiding then
			local ridingObj = clientRideController:getRidingObj()
			local sellValue = (ridingObj:GetAttribute(Attributes.DRAGON_SELL_VALUE) :: number?) or 0
			riddenSection.label.Text = string.format("Sell Ridden Dragon (~%d coins)", sellValue)
		else
			riddenSection.label.Text = "Not riding a dragon"
		end
	end

	if not backpackSection.pendingConfirm then
		local ownedDragons = getOwnedDragons()
		local ridingObj = isRiding and clientRideController:getRidingObj() or nil
		local sellCount, totalValue, spareCount = getBackpackSellPreview(ownedDragons, ridingObj)

		backpackSection.cancelButton.Visible = false
		backpackSection.confirmButton.Visible = false

		if sellCount > 0 then
			backpackSection.sellButton.Visible = true
			backpackSection.label.Text = string.format(
				"Sell All Backpack Dragons (%d dragons, ~%d coins, %d spared)",
				sellCount,
				totalValue,
				spareCount
			)
		else
			backpackSection.sellButton.Visible = false
			backpackSection.label.Text = "No backpack dragons to sell"
		end
	end
end

local function setupSellSection(self: ClientDragonSellStore, sectionName: string, sellType: string): SellSectionRecord
	local section = utils.findFirstDescendant(self.dialogFit, sectionName)

	local record: SellSectionRecord = {
		sellButton = utils.findFirstDescendant(section, "SellButton"),
		confirmButton = utils.findFirstDescendant(section, "ConfirmButton"),
		cancelButton = utils.findFirstDescendant(section, "CancelButton"),
		label = utils.findFirstDescendant(section, "Label"),
		pendingConfirm = false,
	}

	record.confirmButton.Visible = false
	record.cancelButton.Visible = false

	record.sellButton.Activated:Connect(function()
		record.pendingConfirm = true
		record.sellButton.Visible = false
		record.confirmButton.Visible = true
		record.cancelButton.Visible = true
	end)

	record.cancelButton.Activated:Connect(function()
		record.pendingConfirm = false
		self:updateStoreInterface()
	end)

	record.confirmButton.Activated:Connect(function()
		record.pendingConfirm = false
		RemoteEvents.TrySellDragons:FireServer(sellType)
		self:updateStoreInterface()
	end)

	return record
end

function ClientDragonSellStore.beginStore(self: ClientDragonSellStore)
	self:updateStoreInterface()

	DragonSellStoreGui.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	self.timeSinceRefresh = 0
	self.refreshConnect = runService.Heartbeat:Connect(function(deltaTime: number)
		self.timeSinceRefresh += deltaTime
		if self.timeSinceRefresh < REFRESH_INTERVAL_SEC then
			return
		end
		self.timeSinceRefresh = 0
		self:updateStoreInterface()
	end)
end

function ClientDragonSellStore.cleanupStore(self: ClientDragonSellStore)
	DragonSellStoreGui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.refreshConnect then
		self.refreshConnect:Disconnect()
		self.refreshConnect = nil
	end
end

-- opens the store as if the player had used a proximity prompt
local function tryAutoOpenStore(self: ClientDragonSellStore)
	if not self.isEnabled then
		return
	end
	if DragonSellStoreGui.Enabled then
		return
	end
	if not overlayTracker:canStoreAutoOpen() then
		return
	end

	self:beginStore()
end

function ClientDragonSellStore.initWorldInterface(self: ClientDragonSellStore)
	local dragonSellStore: any = DragonSellStoreTemplate:Clone()
	dragonSellStore.Parent = workspace

	self.dragonSellStore = dragonSellStore

	local objProximityPrompt: any = utils.findFirstDescendant(dragonSellStore, "ProximityPrompt")
	if objProximityPrompt then
		objProximityPrompt.Enabled = false
	end

	self.rigHighlight = dragonSellStore:FindFirstChild("Highlight", true)

	local DialogFit = DragonSellStoreGui:WaitForChild("DialogFit")
	self.dialogFit = DialogFit

	local anchor = dragonSellStore.PrimaryPart or dragonSellStore:FindFirstChildWhichIsA("BasePart", true)
	local rigPosition = (anchor :: BasePart).Position

	self.proximityThresholdTracker = ProximityThresholdTracker.new(rigPosition, GREETING_DISTANCE)
	self.proximityThresholdTracker:getEnterEvent():Connect(function()
		if not self.isEnabled or not self.rigHighlight then
			return
		end
		self.rigHighlight.Enabled = true
	end)
	self.proximityThresholdTracker:getLeaveEvent():Connect(function()
		if self.rigHighlight then
			self.rigHighlight.Enabled = false
		end
		if DragonSellStoreGui.Enabled then
			self:cleanupStore()
		end
	end)

	self.autoOpenTracker = ProximityThresholdTracker.new(rigPosition, AUTO_OPEN_DISTANCE)
	self.autoOpenTracker:getEnterEvent():Connect(function()
		tryAutoOpenStore(self)
	end)

	self.riddenSection = setupSellSection(self, "RiddenDragonSection", "ridden")
	self.backpackSection = setupSellSection(self, "BackpackDragonsSection", "backpack")

	local exitButton: any = utils.findFirstDescendant(DialogFit, "ExitButton")
	exitButton.Activated:Connect(function()
		self:cleanupStore()
	end)
end

function ClientDragonSellStore.setEnabled(self: ClientDragonSellStore)
	self.isEnabled = true

	if self.autoOpenTracker and self.autoOpenTracker:isInProximity() then
		tryAutoOpenStore(self)
	end
end

function ClientDragonSellStore.setDisabled(self: ClientDragonSellStore)
	self.isEnabled = false

	if self.rigHighlight then
		self.rigHighlight.Enabled = false
	end
end

function ClientDragonSellStore.init(self: ClientDragonSellStore)
	self:initWorldInterface()
end

function ClientDragonSellStore.new(): ClientDragonSellStore
	local self = setmetatable({} :: ClientDragonSellStoreFields, ClientDragonSellStore)

	self.isEnabled = true
	self.rigHighlight = nil
	self.autoOpenTracker = nil
	self.refreshConnect = nil
	self.timeSinceRefresh = 0

	return self
end

local singleton = ClientDragonSellStore.new()

return singleton
