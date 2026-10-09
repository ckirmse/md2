--!strict

local ClientEggWorldCountsManager = {}
ClientEggWorldCountsManager.__index = ClientEggWorldCountsManager

local RunService = game:GetService("RunService")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance
local eggWorldCountsGui: any = playerGui:WaitForChild("EggsInWorld")

eggWorldCountsGui.DisplayOrder = 130

local REFRESH_INTERVAL_SEC = 1

type EggWorldCountData = {
	itemName: string,
	count: number,
	eggBaseLuck: number,
}

type CardRecord = {
	card: any,
	nameText: any,
	countText: any,
	luckText: any,
}

type ClientEggWorldCountsManagerFields = {
	scroll: any,
	cardTemplate: any,
	timerText: any,
	cardRecords: { [string]: CardRecord }, -- keyed by itemName
	eggWorldCountDatas: { EggWorldCountData },
	refreshConnect: RBXScriptConnection?,
	timeSinceRefresh: number,
	nextRefreshTime: number, -- server time of the next egg refresh, sent with every reply
	shownTimerSec: number?, -- the whole seconds the label currently shows
	panelOpen: boolean,
	awaitingInitialData: boolean,
}

export type ClientEggWorldCountsManager = typeof(setmetatable({} :: ClientEggWorldCountsManagerFields, ClientEggWorldCountsManager))

function ClientEggWorldCountsManager.getGuiRoot(self: ClientEggWorldCountsManager)
	return eggWorldCountsGui
end

function ClientEggWorldCountsManager.getHudElements(self: ClientEggWorldCountsManager)
	return {}
end

function ClientEggWorldCountsManager.notifyForceEnd(self: ClientEggWorldCountsManager)
	self:cleanupPanel()
end

function ClientEggWorldCountsManager.notifyClickOutside(self: ClientEggWorldCountsManager)
	self:notifyForceEnd()
end

function ClientEggWorldCountsManager.doesWantBlur(self: ClientEggWorldCountsManager): boolean
	return false
end

function ClientEggWorldCountsManager.setEggWorldCountDatas(
	self: ClientEggWorldCountsManager,
	eggWorldCountDatas: { EggWorldCountData },
	nextRefreshTime: number
)
	self.eggWorldCountDatas = eggWorldCountDatas
	self.nextRefreshTime = nextRefreshTime
	self:refreshCards()
	self:updateTimerText()

	if self.awaitingInitialData then
		self.awaitingInitialData = false
		eggWorldCountsGui.Enabled = true
	end
end

local function createCardRecord(self: ClientEggWorldCountsManager): CardRecord
	local card: any = self.cardTemplate:Clone()

	local cardRecord: CardRecord = {
		card = card,
		nameText = utils.findFirstDescendant(card, "NameText"),
		countText = utils.findFirstDescendant(card, "CountText"),
		luckText = utils.findFirstDescendant(card, "LuckText"),
	}

	card.Visible = true
	card.Parent = self.scroll

	return cardRecord
end

local function refreshCardRecord(cardRecord: CardRecord, eggWorldCountData: EggWorldCountData)
	cardRecord.nameText.Text = eggWorldCountData.itemName
	cardRecord.countText.Text = string.format("x%d", eggWorldCountData.count)
	cardRecord.luckText.Text = tostring(eggWorldCountData.eggBaseLuck)
end

function ClientEggWorldCountsManager.refreshCards(self: ClientEggWorldCountsManager)
	local currentItemNames: { [string]: boolean } = {}
	for _, eggWorldCountData in self.eggWorldCountDatas do
		currentItemNames[eggWorldCountData.itemName] = true
	end
	for itemName, cardRecord in self.cardRecords do
		if not currentItemNames[itemName] then
			cardRecord.card:Destroy()
			self.cardRecords[itemName] = nil
		end
	end

	for i, eggWorldCountData in self.eggWorldCountDatas do
		local cardRecord = self.cardRecords[eggWorldCountData.itemName]
		if not cardRecord then
			cardRecord = createCardRecord(self)
			self.cardRecords[eggWorldCountData.itemName] = cardRecord
		end
		cardRecord.card.LayoutOrder = i
		refreshCardRecord(cardRecord, eggWorldCountData)
	end
end

function ClientEggWorldCountsManager.updateTimerText(self: ClientEggWorldCountsManager)
	if self.nextRefreshTime == 0 then
		return
	end

	local remainingSec = math.max(0, math.ceil(self.nextRefreshTime - workspace:GetServerTimeNow()))
	if remainingSec == self.shownTimerSec then
		return
	end

	self.shownTimerSec = remainingSec
	self.timerText.Text = string.format("Egg resets in %s", utils.convertDurationSecToString(remainingSec))
end

function ClientEggWorldCountsManager.beginPanel(self: ClientEggWorldCountsManager)
	self.panelOpen = true
	self.awaitingInitialData = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	RemoteEvents.TryGetEggWorldCounts:FireServer()
	self.shownTimerSec = nil
	self.timeSinceRefresh = 0

	self.refreshConnect = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:updateTimerText()

		self.timeSinceRefresh += deltaTime
		if self.timeSinceRefresh < REFRESH_INTERVAL_SEC then
			return
		end
		self.timeSinceRefresh = 0
		RemoteEvents.TryGetEggWorldCounts:FireServer()
	end)
end

function ClientEggWorldCountsManager.cleanupPanel(self: ClientEggWorldCountsManager)
	self.panelOpen = false
	self.awaitingInitialData = false
	eggWorldCountsGui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.refreshConnect then
		self.refreshConnect:Disconnect()
		self.refreshConnect = nil
	end
end

function ClientEggWorldCountsManager.togglePanel(self: ClientEggWorldCountsManager)
	if self.panelOpen then
		self:cleanupPanel()
	else
		self:beginPanel()
	end
end

function ClientEggWorldCountsManager.init(self: ClientEggWorldCountsManager)
	local scrollingFrame: any = utils.findFirstDescendant(eggWorldCountsGui, "ScrollingFrame")
	self.scroll = scrollingFrame
	self.cardTemplate = utils.findFirstDescendant(scrollingFrame, "EggCardTemplate")
	self.cardTemplate.Visible = false

	self.timerText = utils.findFirstDescendant(eggWorldCountsGui, "TimerText")

	local dialogFit: any = eggWorldCountsGui:WaitForChild("DialogFit")
	dialogFit:WaitForChild("HeaderSmall"):WaitForChild("ExitButton").Activated:Connect(function()
		self:cleanupPanel()
	end)
end

function ClientEggWorldCountsManager.new(): ClientEggWorldCountsManager
	local self = setmetatable({} :: ClientEggWorldCountsManagerFields, ClientEggWorldCountsManager)

	self.cardRecords = {}
	self.eggWorldCountDatas = {}
	self.refreshConnect = nil
	self.timeSinceRefresh = 0
	self.nextRefreshTime = 0
	self.shownTimerSec = nil
	self.panelOpen = false
	self.awaitingInitialData = false

	return self
end

local singleton = ClientEggWorldCountsManager.new()

return singleton
