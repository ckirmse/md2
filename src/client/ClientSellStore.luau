--!strict

local ClientSellStore = {}
ClientSellStore.__index = ClientSellStore

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Animations = GameAssets:WaitForChild("Animations")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local MainElements = GameAssets:WaitForChild("MainElements")
-- the store template's shape only exists in Studio, so it is untyped here
local SellStore: any = MainElements:WaitForChild("SellStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")


local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")

local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local Sell: any = PlayerGui:WaitForChild("Sell")

local SellStatus = {
	NONE = 1,
	IN_PROGRESS = 2,
}

type SellData = {
	total: { [number]: number },
	current: { [number]: number },
}

type ClientSellStoreFields = {
	sellStore: any?, -- SellStore clone
	idleAnimationTrack: any?,
	approachAnimationTrack: any?,
	proximityThresholdTracker: any?,
	autoOpenTracker: any?,
	rigHighlight: any?,
	sellData: SellData,
	sellStatus: number,
	prevGreetTime: number,
	isEnabled: boolean,
}

export type ClientSellStore = typeof(setmetatable({} :: ClientSellStoreFields, ClientSellStore))

local GREETING_DISTANCE = 10
local GREETING_TIME_COOLDOWN = 5

-- the store auto-opens when the player gets this close to the vendor; deliberately smaller than
-- GREETING_DISTANCE (whose leave event closes the store) so the open/close thresholds have
-- hysteresis instead of flickering at one boundary
local AUTO_OPEN_DISTANCE = 8

function ClientSellStore.getGuiRoot(self: ClientSellStore): Instance
	return Sell
end

function ClientSellStore.notifyForceEnd(self: ClientSellStore)
	self:cleanupStore()
end

function ClientSellStore.notifyClickOutside(self: ClientSellStore)
	self:notifyForceEnd()
end

function ClientSellStore.getHudElements(self: ClientSellStore): { number }
	return {enums.HudElements.COINS, enums.HudElements.GEMS}
end

-- overlay protocol hook: walking into a vendor's auto-open zone is allowed to replace a store
-- overlay (so walking from one vendor to the other hands off), but never any other overlay
function ClientSellStore.doAllowStoreAutoOpen(self: ClientSellStore): boolean
	return true
end

-- opens the store as if the player had used the old proximity prompt; called from the auto-open
-- tracker's enter event and from setEnabled when the player is already standing in the zone
local function tryAutoOpenStore(self: ClientSellStore)
	if not self.isEnabled then
		return
	end
	if Sell.Enabled then
		-- already open
		return
	end
	if not overlayTracker:canStoreAutoOpen() then
		return
	end

	self:beginStore()
end

function ClientSellStore.beginStore(self: ClientSellStore)
	self:calculateSellCounts()
	self:initSellList()
	self:updateSellListDataView()

	local rig: any = (self.sellStore :: any):FindFirstChild("Rig")

	local audioBeginStore = rig:FindFirstChild("AudioBeginStore")
	audioBeginStore:Play()

	Sell.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientSellStore.cleanupStore(self: ClientSellStore)
	Sell.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientSellStore.updateSellListDataView(self: ClientSellStore)

	local DialogFit = Sell:WaitForChild("DialogFit")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local sellStoreDataFolder = splendidDataFolder:WaitForChild("SellStore")

	local scroll: any = utils.findFirstDescendant(DialogFit, "Scroll")

	for _, inst in sellStoreDataFolder:GetChildren() :: { any } do
		local itemName = inst.Name
		local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

		local offer: any = utils.findFirstDescendant(scroll, itemName)
		if not offer then
			warn("weird, cannot find sell row for", itemName)
			continue
		end

		local item: any = utils.findFirstDescendant(offer, "Item")
		item.BackgroundColor3 = inst:GetAttribute(Attributes.COLOR)

		local imageLabel: any = utils.findFirstDescendant(offer, "ImageLabel")
		imageLabel.Image = "rbxassetid://" .. inst:GetAttribute(Attributes.ASSET_ID)

		local amount: any = utils.findFirstDescendant(offer, "GemAmount")
		amount.Text = tostring(self.sellData.current[primaryElement]) .. "/" .. tostring(self.sellData.total[primaryElement])

		local canIncrease = (self.sellData.current[primaryElement] < self.sellData.total[primaryElement])
		local canDecrease = (self.sellData.current[primaryElement] > 0)
		local isSellingAny = (self.sellData.current[primaryElement] > 0)
		local isSellingAll = (self.sellData.current[primaryElement] == self.sellData.total[primaryElement])
		local haveAny = (self.sellData.total[primaryElement] > 0)

		local isBusy = (self.sellStatus ~= SellStatus.NONE)

		local arrowUp: any = utils.findFirstDescendant(offer, "ArrowUp")
		arrowUp.Active = canIncrease and not isBusy
		arrowUp.AutoButtonColor = canIncrease and not isBusy

		local arrowDown: any = utils.findFirstDescendant(offer, "ArrowDown")
		arrowDown.Active = canDecrease and not isBusy
		arrowDown.AutoButtonColor = canDecrease and not isBusy

		local sellButton: any = utils.findFirstDescendant(offer, "SellButton")
		sellButton.Active = isSellingAny and not isBusy
		sellButton.AutoButtonColor = isSellingAny and not isBusy

		local label: any = utils.findFirstDescendant(offer, "Label")
		if isSellingAll then
			label.Text = "Sell all"
		else
			label.Text = "Sell " .. self.sellData.current[primaryElement]
		end

		local disabled: any = utils.findFirstDescendant(offer, "Disabled")
		disabled.Visible = not haveAny

		local value = self.sellData.current[primaryElement] * inst:GetAttribute(Attributes.COINS)
		local price: any = utils.findFirstDescendant(offer, "Price")
		price.Text = utils.formatLargeInteger(value)
	end

end

function ClientSellStore.getStoreDataInstances(self: ClientSellStore): { any }
	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local sellStoreDataFolder = splendidDataFolder:WaitForChild("SellStore")

	local insts: { any } = {}
	for _, inst in sellStoreDataFolder:GetChildren() :: { any } do
		table.insert(insts, inst)
	end
	table.sort(insts,
		function (a, b)
			local primaryElementA = a:GetAttribute(Attributes.PRIMARY_ELEMENT)
			local primaryElementB = b:GetAttribute(Attributes.PRIMARY_ELEMENT)
			if self.sellData.total[primaryElementA] > self.sellData.total[primaryElementB] then
				return true
			end
			if self.sellData.total[primaryElementA] < self.sellData.total[primaryElementB] then
				return false
			end

			--print("sorting based on primary element", itemNameA, primaryElementA, Elements.getSortIndexForPrimaryElement(primaryElementA), "and", itemNameB, primaryElementB, Elements.getSortIndexForPrimaryElement(primaryElementB))
			if Elements.getSortIndexForPrimaryElement(primaryElementA) < Elements.getSortIndexForPrimaryElement(primaryElementB) then
				return true
			end
			if Elements.getSortIndexForPrimaryElement(primaryElementA) > Elements.getSortIndexForPrimaryElement(primaryElementB) then
				return false
			end

			-- last gasp to distinguish them
			return primaryElementA < primaryElementB
		end
	)

	return insts
end

function ClientSellStore.initSellList(self: ClientSellStore)

	local DialogFit = Sell:WaitForChild("DialogFit")

	local scroll: any = utils.findFirstDescendant(DialogFit, "Scroll")

	for _, inst in (scroll :: Instance):GetChildren() do
		if inst.Name == "OfferTemplate" then
			continue
		end
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst:Destroy()
	end

	-- for each item for sale, clone the 'StoreOffer' item, replacing template data

	local storeOfferTemplate: any = utils.findFirstDescendant(DialogFit, "OfferTemplate")
	storeOfferTemplate.Visible = false

	local rig: any = (self.sellStore :: any):FindFirstChild("Rig")

	for _, inst in self:getStoreDataInstances() do
		local itemName = inst.Name
		local sellName = inst:GetAttribute(Attributes.SELL_NAME)
		local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

		local offer = storeOfferTemplate:Clone()
		offer.Name = itemName

		offer.Visible = true
		local name: any = utils.findFirstDescendant(offer, "GemName")
		name.Text = sellName

		offer:SetAttribute(Attributes.ITEM_NAME, itemName)

		local offerArrowUp: any = utils.findFirstDescendant(offer, "ArrowUp")
		offerArrowUp.Activated:Connect(
			function ()
				--print("got an arrow up")
				if self.sellData.current[primaryElement] < self.sellData.total[primaryElement] then
					self.sellData.current[primaryElement] = math.clamp(self.sellData.current[primaryElement] + math.ceil(self.sellData.total[primaryElement] / 10), 0, self.sellData.total[primaryElement])

					local audioClick = rig:FindFirstChild("AudioClick")
					audioClick:Play()
				else
					local audioInvalidClick = rig:FindFirstChild("AudioInvalidClick")
					audioInvalidClick:Play()
				end
				self:updateSellListDataView()
			end
		)

		local offerArrowDown: any = utils.findFirstDescendant(offer, "ArrowDown")
		offerArrowDown.Activated:Connect(
			function ()
				--print("got an arrow down")
				if self.sellData.current[primaryElement] > 0 then
					self.sellData.current[primaryElement] = math.clamp(self.sellData.current[primaryElement] - math.ceil(self.sellData.total[primaryElement] / 10), 0, self.sellData.total[primaryElement])

					local audioClick = rig:FindFirstChild("AudioClick")
					audioClick:Play()
				else
					local audioInvalidClick = rig:FindFirstChild("AudioInvalidClick")
					audioInvalidClick:Play()
				end

				self:updateSellListDataView()
			end
		)

		local function trySell()
			--print("store sell activated")

			if self.sellStatus ~= SellStatus.NONE then
				return
			end

			if self.sellData.current[primaryElement] > 0 then
				self.sellStatus = SellStatus.IN_PROGRESS
				self:updateSellListDataView()

				local sellOffer = {
					primaryElement = primaryElement,
					count = self.sellData.current[primaryElement]
				}
				RemoteEvents.TrySellGems:FireServer(sellOffer)

				local audioSellEvent = rig:FindFirstChild("AudioSellEvent")
				audioSellEvent:Play()
			else
				local audioInvalidClick = rig:FindFirstChild("AudioInvalidClick")
				audioInvalidClick:Play()
			end
		end

		offer.Activated:Connect(trySell)
		local offerSellButton: any = utils.findFirstDescendant(offer, "SellButton")
		offerSellButton.Activated:Connect(trySell)

		offer.Parent = scroll
	end
end

function ClientSellStore.calculateSellCounts(self: ClientSellStore): number
	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local sellStoreDataFolder = splendidDataFolder:WaitForChild("SellStore")

	local total = 0

	self.sellData = {
		total = {},
		current = {},
	}

	for _, inst in sellStoreDataFolder:GetChildren() :: { any } do
		local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

		local gemsCount = clientPlayerAttributesManager:get(Elements.getGemsKeyForPrimaryElement(primaryElement))

		self.sellData.total[primaryElement] = gemsCount
		self.sellData.current[primaryElement] = gemsCount

		total += gemsCount
		--print("adding entry", primaryElement, self.sellData.total[primaryElement])
	end

	return total
end

function ClientSellStore.initWorldInterface(self: ClientSellStore)
	local sellStore = SellStore:Clone()
	sellStore.Parent = workspace

	self.sellStore = sellStore

	-- the store now auto-opens on proximity; the prompt instance stays in the Studio-authored
	-- model but is permanently disabled
	local objProximityPrompt: any = utils.findFirstDescendant(sellStore, "ProximityPrompt")
	objProximityPrompt.Enabled = false

	local rig: any = (self.sellStore :: any):FindFirstChild("Rig")

	local animation = Animations:FindFirstChild("StoreIdle")
	local animator = rig:WaitForChild("Humanoid"):WaitForChild("Animator")
	local idleAnimationTrack = animator:LoadAnimation(animation)
	self.idleAnimationTrack = idleAnimationTrack
	idleAnimationTrack:Play()

	local DialogFit = Sell:WaitForChild("DialogFit")

	local rigHighlight: any = rig:FindFirstChild("Highlight")
	self.rigHighlight = rigHighlight

	local rigPosition = rig:WaitForChild("HumanoidRootPart").Position

	local proximityThresholdTracker = ProximityThresholdTracker.new(rigPosition, GREETING_DISTANCE)
	self.proximityThresholdTracker = proximityThresholdTracker

	-- the highlight and greet/idle animation swaps used to ride on the prompt's
	-- PromptShown/PromptHidden; with the prompt gone they follow the greet threshold instead
	proximityThresholdTracker:getEnterEvent():Connect(
		function()
			if not self.isEnabled then
				return
			end

			rigHighlight.Enabled = true

			if (workspace:GetServerTimeNow() - self.prevGreetTime) < GREETING_TIME_COOLDOWN then
				return
			end

			self.prevGreetTime = workspace:GetServerTimeNow()

			if not self.approachAnimationTrack then
				local approachAnimation = Animations:FindFirstChild("StoreApproach")
				local approachAnimator = rig:WaitForChild("Humanoid"):WaitForChild("Animator")
				self.approachAnimationTrack = approachAnimator:LoadAnimation(approachAnimation)
			end

			local fadeTime = 0.2
			idleAnimationTrack:Stop(fadeTime)
			task.wait(fadeTime)
			-- make it slightly different than default speed so the two npcs won't be in sync
			local approachTrack: any = self.approachAnimationTrack
			approachTrack:Play(0.09)

			local audioHello = rig:FindFirstChild("AudioHello")
			audioHello:Play()
		end
	)

	proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			rigHighlight.Enabled = false

			if Sell.Enabled then
				self:cleanupStore()
			end

			local approachAnimationTrack = self.approachAnimationTrack
			if approachAnimationTrack then
				local fadeTime = 0.2
				approachAnimationTrack:Stop(fadeTime)
				task.wait(fadeTime)
				idleAnimationTrack:Play()
			end
		end
	)

	local autoOpenTracker = ProximityThresholdTracker.new(rigPosition, AUTO_OPEN_DISTANCE)
	self.autoOpenTracker = autoOpenTracker

	autoOpenTracker:getEnterEvent():Connect(
		function()
			tryAutoOpenStore(self)
		end
	)

	DialogFit:WaitForChild("Header"):WaitForChild("ExitButton").Activated:Connect(
		function()
			local audioClick = rig:FindFirstChild("AudioClick")
			audioClick:Play()

			self:cleanupStore()
		end
	)
end

function ClientSellStore.notifySellStatus(self: ClientSellStore, isSuccess: boolean)
	--print("selling finished")

	self.sellStatus = SellStatus.NONE

	local totalAvailableToSell = self:calculateSellCounts()
	if totalAvailableToSell == 0 then
		-- player just sold their last thing, so close the dialog
		self:cleanupStore()
	end

	self:updateSellListDataView()

end

function ClientSellStore.setEnabled(self: ClientSellStore)
	self.isEnabled = true

	-- if the player is already standing in the auto-open zone when the store becomes enabled
	-- (e.g. an FTUE step change), no enter edge will fire, so open it here
	if self.autoOpenTracker and self.autoOpenTracker:isInProximity() then
		tryAutoOpenStore(self)
	end
end

function ClientSellStore.setDisabled(self: ClientSellStore)
	self.isEnabled = false

	local rigHighlight = self.rigHighlight
	if rigHighlight then
		rigHighlight.Enabled = false
	end
end

function ClientSellStore.init(self: ClientSellStore)
	self:initWorldInterface()
end

function ClientSellStore.new(): ClientSellStore
	local self = setmetatable({} :: ClientSellStoreFields, ClientSellStore)

	self.sellData = {
		total = {},
		current = {},
	}

	self.prevGreetTime = 0
	self.isEnabled = true

	self.sellStatus = SellStatus.NONE

	return self
end

local singleton = ClientSellStore.new()

return singleton
