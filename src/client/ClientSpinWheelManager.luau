--!strict

-- Daily spin wheel. The HUD LuckySpin button opens the SpinWheel overlay dialog; there is no world presence. The
-- dialog's wheel face is segmented from the catalog the server sends in the init data (one entry per loot-table row,
-- with 1x and 2x odds), the buy buttons use the Robux product ids from the same data, and spin counts and discount
-- availability arrive in the init data and again in NotifySpinWheelState. The server rolls and grants; the client
-- animates the wheel landing on the announced segment, then celebrates with confetti and asks the server to release
-- the prize it is holding.
local ClientSpinWheelManager = {}
ClientSpinWheelManager.__index = ClientSpinWheelManager

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local ButtonTwitcher = require("./ButtonTwitcher")
local clientOptionsManager = require("./ClientOptionsManager")
local ClientTicker = require("./ClientTicker")
local ClientUiStyle = require("./ClientUiStyle")
local Confetti = require("./Confetti")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

type AuthoredButtonStyle = {
	color: Color3,
	gradientColor: ColorSequence?,
}

-- the part of the server's catalog entry the wheel draws (see SpinWheelManager.getCatalog)
export type Segment = {
	kind: number,
	fraction: number,
	paidFraction: number,
	coinAmount: number?,
	diamondAmount: number?,
	skipSec: number?,
	itemName: string?,
	itemType: number?,
	displayName: string?,
	rarity: number?,
	iconAssetId: string?,
}

export type SpinWheelState = {
	freeSpins: number,
	paidSpins: number,
	isDiscountAvailable: boolean,
}

-- the gui's shape only exists in Studio, so its instances are untyped here
type ClientSpinWheelManagerFields = {
	gui: any?,
	dialog: any?,
	wheelFace: any?,
	fallbackPrizeTemplate: any?,
	timeSkipPrizeTemplate: any?,
	dragonPrizeTemplatesByRarity: { [number]: any },
	eggPrizeTemplate: any?,
	oddsList: any?,
	oddsRowTemplate: any?,
	oddsToggle: any?,
	fastToggle: any?,
	spinButton: any?,
	spinLabel: any?,
	buy1Button: any?,
	buy5Button: any?,
	authoredButtonStyles: { [any]: AuthoredButtonStyle },
	resultLabel: any?,
	segments: { Segment },
	spinState: SpinWheelState,
	robuxProductIds: { [string]: number },
	robuxPrices: { [number]: number },
	pricesRequested: { [number]: boolean },
	activeSpinToken: {}?,
	isOverlayOpen: boolean,
	isSpinning: boolean,
	hudButton: any?,
	hudAlertLabel: any?,
	hudTwitcher: ButtonTwitcher.ButtonTwitcher?,
	showOdds: boolean,
	fastSpin: boolean,
	wheelRotation: number,
	wheelLoopSound: Sound?,
	random: Random,
}

export type ClientSpinWheelManager = typeof(setmetatable({} :: ClientSpinWheelManagerFields, ClientSpinWheelManager))

local DISPLAY_ORDER = 130
-- the authored dragon faces by rarity; other rarities use the plain face
local DRAGON_PRIZE_TEMPLATE_NAMES = {
	[Enums.Rarity.RARE] = "PetPrizeRareTemplate",
	[Enums.Rarity.EPIC] = "PetPrizeEpicTemplate",
}
local EGG_PRIZE_TEMPLATE_NAME = "BoxPetPrizeTemplate"
local ROBUX_GLYPH = utf8.char(0xE002)
-- looped while the wheel turns
local WHEEL_LOOP_SOUND_ID = "rbxassetid://1846470940"
local SPIN_DURATION_SEC = 4
local FAST_SPIN_DURATION_SEC = 1.2
local SPIN_REVOLUTIONS = 5
-- the server answers every spin; this only unlocks a Spin button whose request was dropped
local PENDING_SPIN_TIMEOUT_SEC = 5

local function formatSkipTitle(skipSec: number): string
	if skipSec >= 3600 then
		return string.format("%dh Time Skip", skipSec // 3600)
	end
	return string.format("%dm Time Skip", skipSec // 60)
end

local function formatSkipShort(skipSec: number): string
	if skipSec >= 3600 then
		return string.format("%dh", skipSec // 3600)
	end
	return string.format("%dm", skipSec // 60)
end

local function getSegmentTitle(segment: Segment): string
	if segment.kind == Enums.PlaytimeRewardKind.COINS then
		return if segment.coinAmount then `{utils.formatLargePositiveInteger(segment.coinAmount)} Coins` else "Coins"
	elseif segment.kind == Enums.PlaytimeRewardKind.DIAMONDS then
		return if segment.diamondAmount then `{utils.formatLargePositiveInteger(segment.diamondAmount)} Diamonds` else "Diamonds"
	elseif segment.kind == Enums.PlaytimeRewardKind.TIME_SKIP then
		return formatSkipTitle(segment.skipSec or 0)
	end

	local name = segment.displayName or segment.itemName or "???"
	if segment.rarity then
		return utils.getColoredTextForRarity(name, segment.rarity)
	end
	return name
end

-- a fixed item shows its own picture; a segment that rolls its item later may carry an authored one
local function getSegmentIconAssetId(segment: Segment): string?
	if segment.itemName then
		local itemIcon = ItemIcons.getItemIconAssetId(segment.itemName)
		if itemIcon then
			return itemIcon
		end
	end

	return segment.iconAssetId
end

function ClientSpinWheelManager.getFreeSpins(self: ClientSpinWheelManager): number
	return self.spinState.freeSpins
end

function ClientSpinWheelManager.getPaidSpins(self: ClientSpinWheelManager): number
	return self.spinState.paidSpins
end

function ClientSpinWheelManager.getProductId(self: ClientSpinWheelManager, name: string): number?
	local productId = self.robuxProductIds[name]
	if productId == nil or productId == 0 then
		return nil
	end

	return productId
end

function ClientSpinWheelManager.isDiscountAvailable(self: ClientSpinWheelManager): boolean
	return self.spinState.isDiscountAvailable
end

-- the next spin runs at 2x luck when there are no free spins left but paid spins remain; the odds list mirrors that
function ClientSpinWheelManager.isNextSpinPaid(self: ClientSpinWheelManager): boolean
	return self:getFreeSpins() == 0 and self:getPaidSpins() > 0
end

function ClientSpinWheelManager.updateHudButton(self: ClientSpinWheelManager)
	local hasSpin = self:getFreeSpins() + self:getPaidSpins() > 0
	local alertLabel = self.hudAlertLabel
	if alertLabel then
		alertLabel.Visible = hasSpin
	end

	local twitcher = self.hudTwitcher
	if hasSpin and twitcher then
		twitcher:updateIfNeeded()
	end
end

function ClientSpinWheelManager.getSegmentTemplate(self: ClientSpinWheelManager, segment: Segment): any?
	if segment.kind == Enums.PlaytimeRewardKind.TIME_SKIP then
		return self.timeSkipPrizeTemplate or self.fallbackPrizeTemplate
	elseif segment.itemType == Enums.ItemType.DRAGON and segment.rarity then
		return self.dragonPrizeTemplatesByRarity[segment.rarity] or self.fallbackPrizeTemplate
	elseif segment.itemType == Enums.ItemType.DRAGON_EGG then
		return self.eggPrizeTemplate or self.fallbackPrizeTemplate
	end

	return self.fallbackPrizeTemplate
end

-- the authored dragon/egg faces carry the prize colors themselves, so only the name and icon are filled in; the
-- plain face gets the rarity-tagged title
function ClientSpinWheelManager.fillSegmentFace(self: ClientSpinWheelManager, prize: any, template: any, segment: Segment)
	if template == self.fallbackPrizeTemplate then
		local prizeTitle = prize:FindFirstChild("PetTitle") :: TextLabel?
		if prizeTitle then
			prizeTitle.RichText = true
			prizeTitle.Text = getSegmentTitle(segment)
		end
		return
	end

	if segment.kind == Enums.PlaytimeRewardKind.TIME_SKIP then
		local timeLabel = prize:FindFirstChild("Time") :: TextLabel?
		if timeLabel then
			timeLabel.Text = formatSkipShort(segment.skipSec or 0)
		end
		return
	end

	local name = segment.displayName or segment.itemName or "???"
	local titleName = if segment.itemType == Enums.ItemType.DRAGON_EGG then "BoxTitle" else "PetTitle"
	local titleLabel = prize:FindFirstChild(titleName) :: TextLabel?
	if titleLabel then
		titleLabel.Text = name
	end

	local icon = prize:FindFirstChild("Icon") :: ImageLabel?
	if icon then
		local iconAssetId = getSegmentIconAssetId(segment)
		if iconAssetId then
			icon.Image = iconAssetId
		end
		icon.Visible = iconAssetId ~= nil
	end
end

function ClientSpinWheelManager.rebuildWheelFace(self: ClientSpinWheelManager)
	local face = self.wheelFace
	if not face then
		return
	end

	for _, child in face:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local count = #self.segments
	if count == 0 then
		return
	end

	local anglePerSegment = 360 / count
	for index, segment in self.segments do
		-- one radial label per segment; the label sits along the segment's center angle, rotated so it reads outward
		-- from the hub
		local angle = (index - 1) * anglePerSegment
		local holder = Instance.new("Frame")
		holder.Name = `Segment{index}`
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.Rotation = angle

		local template = self:getSegmentTemplate(segment)
		if not template then
			continue
		end

		local prize = template:Clone()
		self:fillSegmentFace(prize, template, segment)
		prize.Name = "Title"
		prize.Visible = true
		prize.AnchorPoint = Vector2.new(0.5, 0.5)
		prize.Position = UDim2.fromScale(0.5, 0.14)
		prize.Parent = holder

		holder.Parent = face
	end

	face.Rotation = self.wheelRotation
end

function ClientSpinWheelManager.rebuildOddsList(self: ClientSpinWheelManager)
	local oddsList = self.oddsList
	local template = self.oddsRowTemplate
	if not oddsList or not template then
		return
	end

	for _, child in oddsList:GetChildren() do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
		end
	end
	oddsList.Visible = self.showOdds

	local isPaid = self:isNextSpinPaid()
	local sortedSegments = table.clone(self.segments)
	table.sort(sortedSegments, function(a: Segment, b: Segment)
		local fractionA = if isPaid then a.paidFraction else a.fraction
		local fractionB = if isPaid then b.paidFraction else b.fraction
		return fractionA > fractionB
	end)

	for index, segment in sortedSegments do
		local row = template:Clone()
		row.Name = `Odds{index}`
		row.LayoutOrder = index
		row.Visible = true

		local rowLabel = row:FindFirstChild("Label") :: TextLabel?
		if rowLabel then
			rowLabel.RichText = true
			local fraction = if isPaid then segment.paidFraction else segment.fraction
			rowLabel.Text = string.format("%s — %.1f%%", getSegmentTitle(segment), fraction * 100)
		end

		row.Parent = oddsList
	end
end

-- the live Robux price of a product, fetched once and remembered; the callback runs when it is known
function ClientSpinWheelManager.getRobuxPrice(self: ClientSpinWheelManager, productId: number, callback: (number) -> ())
	local cached = self.robuxPrices[productId]
	if cached then
		callback(cached)
		return
	end
	if self.pricesRequested[productId] then
		return
	end
	self.pricesRequested[productId] = true

	task.spawn(function()
		local isSuccess, info = pcall(function()
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product) :: any
		end)
		if not isSuccess or type(info) ~= "table" or type((info :: any).PriceInRobux) ~= "number" then
			warn("ClientSpinWheelManager: could not load the price of product", productId)
			self.pricesRequested[productId] = nil
			return
		end

		self.robuxPrices[productId] = (info :: any).PriceInRobux
		callback((info :: any).PriceInRobux)
		-- a price can arrive after the labels were last drawn
		self:refreshButtons()
	end)
end

function ClientSpinWheelManager.refreshButtons(self: ClientSpinWheelManager)
	local freeSpins = self:getFreeSpins()
	local paidSpins = self:getPaidSpins()
	local discountAvailable = self:isDiscountAvailable()

	local spinButton = self.spinButton
	local spinLabel = self.spinLabel
	if spinButton and spinLabel then
		if freeSpins > 0 then
			spinLabel.Text = `Spin ({freeSpins})`
		elseif paidSpins > 0 then
			spinLabel.Text = `Spin ({paidSpins}) 2x Luck`
		else
			spinLabel.Text = "No Free Spins"
		end
	end

	for _, button in { self.spinButton, self.buy1Button, self.buy5Button } do
		if not button then
			continue
		end

		button.Active = not self.isSpinning
		button.AutoButtonColor = not self.isSpinning
		local authored = self.authoredButtonStyles[button]
		if not authored then
			continue
		end

		button.BackgroundColor3 = if self.isSpinning then ClientUiStyle.DISABLED_BUTTON_COLOR else authored.color
		local gradient = button:FindFirstChildOfClass("UIGradient")
		if gradient and authored.gradientColor then
			gradient.Color = if self.isSpinning then ClientUiStyle.DISABLED_BUTTON_GRADIENT else authored.gradientColor
		end
	end

	local buy1Button = self.buy1Button
	if buy1Button then
		local fullPriceLabel = buy1Button:FindFirstChild("FullPrice") :: TextLabel?
		local priceLabel = buy1Button:FindFirstChild("Price") :: TextLabel?
		local discountLabel = buy1Button:FindFirstChild("DiscountLabel") :: TextLabel?
		if discountLabel then
			discountLabel.Visible = discountAvailable
		end

		local fullProductId = self:getProductId("single")
		local discountProductId = self:getProductId("singleDiscount")
		if fullProductId and priceLabel then
			self:getRobuxPrice(fullProductId, function(fullPrice: number)
				if not discountAvailable or not discountProductId then
					if fullPriceLabel then
						fullPriceLabel.Visible = false
					end
					priceLabel.Text = `{ROBUX_GLYPH} {fullPrice}`
					return
				end

				-- strike through the full price beside the discounted one
				if fullPriceLabel then
					fullPriceLabel.Visible = true
					fullPriceLabel.Text = `<s>{ROBUX_GLYPH} {fullPrice}</s>`
				end
				self:getRobuxPrice(discountProductId, function(discountPrice: number)
					priceLabel.Text = `{ROBUX_GLYPH} {discountPrice}`
				end)
			end)
		end
	end

	local buy5Button = self.buy5Button
	if buy5Button then
		local priceLabel = buy5Button:FindFirstChild("Price") :: TextLabel?
		local fiveProductId = self:getProductId("five")
		if fiveProductId and priceLabel then
			self:getRobuxPrice(fiveProductId, function(price: number)
				priceLabel.Text = `{ROBUX_GLYPH} {price}`
			end)
		end
	end
end

function ClientSpinWheelManager.promptBuyOne(self: ClientSpinWheelManager)
	local productId = self:getProductId(if self:isDiscountAvailable() then "singleDiscount" else "single")
	if productId then
		MarketplaceService:PromptProductPurchase(player, productId)
	end
end

function ClientSpinWheelManager.onSpinPressed(self: ClientSpinWheelManager)
	if self.isSpinning then
		return
	end

	if self:getFreeSpins() > 0 or self:getPaidSpins() > 0 then
		self.isSpinning = true
		self:refreshButtons()
		RemoteEvents.TrySpinWheel:FireServer()

		-- safety valve: if the server declines (no result arrives), unlock
		task.delay(PENDING_SPIN_TIMEOUT_SEC, function()
			if self.isSpinning and not self.activeSpinToken then
				self.isSpinning = false
				self:refreshButtons()
			end
		end)
	else
		self:promptBuyOne()
	end
end

function ClientSpinWheelManager.playConfetti(self: ClientSpinWheelManager)
	local gui = self.gui
	if gui then
		Confetti.play(gui, self.random)
	end
end

-- the server answers a spin with the winning segment's position in the catalog
function ClientSpinWheelManager.onSpinResult(self: ClientSpinWheelManager, segmentIndex: any)
	if type(segmentIndex) ~= "number" or not self.segments[segmentIndex] then
		self.isSpinning = false
		self:refreshButtons()
		return
	end

	if not self.isOverlayOpen then
		self.isSpinning = false
		-- no animation to wait for, so ask for the prize right away
		self:claimPrize()
		return
	end

	self:animateToSegment(segmentIndex)
end

-- the server holds the prize until the wheel has visibly stopped
function ClientSpinWheelManager.claimPrize(self: ClientSpinWheelManager)
	RemoteEvents.TryClaimSpinWheelPrize:FireServer()
end

function ClientSpinWheelManager.startWheelLoop(self: ClientSpinWheelManager)
	self:stopWheelLoop()
	if not clientOptionsManager:getOption(PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED) then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "SpinWheelLoop"
	sound.SoundId = WHEEL_LOOP_SOUND_ID
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	self.wheelLoopSound = sound
end

function ClientSpinWheelManager.stopWheelLoop(self: ClientSpinWheelManager)
	local sound = self.wheelLoopSound
	if sound then
		sound:Stop()
		sound:Destroy()
		self.wheelLoopSound = nil
	end
end

function ClientSpinWheelManager.animateToSegment(self: ClientSpinWheelManager, segmentIndex: number)
	local face = self.wheelFace
	local count = #self.segments
	if not face or count == 0 then
		self.isSpinning = false
		self:refreshButtons()
		return
	end

	self.isSpinning = true
	local token = {}
	self.activeSpinToken = token

	self:startWheelLoop()

	local resultLabel = self.resultLabel
	if resultLabel then
		resultLabel.Text = ""
	end

	-- the pointer sits at the top; segment centers are painted at (index-1) * anglePerSegment, so rotate the face by
	-- the negative of the winning segment's angle (plus whole revolutions) to bring it up top
	local anglePerSegment = 360 / count
	local startRotation = self.wheelRotation % 360
	local targetRotation = -(segmentIndex - 1) * anglePerSegment - SPIN_REVOLUTIONS * 360
	local totalDelta = targetRotation - startRotation
	local duration = if self.fastSpin then FAST_SPIN_DURATION_SEC else SPIN_DURATION_SEC

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if self.activeSpinToken ~= token then
			connection:Disconnect()
			self:stopWheelLoop()
			return
		end

		elapsed += dt
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local eased = 1 - (1 - alpha) ^ 3
		self.wheelRotation = startRotation + totalDelta * eased
		face.Rotation = self.wheelRotation
		if alpha < 1 then
			return
		end

		connection:Disconnect()
		self:stopWheelLoop()
		self.activeSpinToken = nil
		self.isSpinning = false

		local segment = self.segments[segmentIndex]
		if resultLabel and segment then
			resultLabel.Text = `You won {getSegmentTitle(segment)}!`
		end
		self:playConfetti()
		self:claimPrize()
		self:refreshButtons()
		self:rebuildOddsList()
	end)
end

function ClientSpinWheelManager.openDialog(self: ClientSpinWheelManager)
	local gui = self.gui
	if self.isOverlayOpen then
		return
	end
	if not gui then
		warn("ClientSpinWheelManager: the SpinWheel gui was not set up at startup, see the startup warning")
		return
	end

	self:rebuildWheelFace()
	self:rebuildOddsList()
	self:refreshButtons()

	local resultLabel = self.resultLabel
	if resultLabel then
		resultLabel.Text = ""
	end

	gui.Enabled = true
	self.isOverlayOpen = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientSpinWheelManager.closeDialogGui(self: ClientSpinWheelManager)
	local gui = self.gui
	if gui then
		gui.Enabled = false
	end

	self:stopWheelLoop()
	if self.activeSpinToken then
		-- a force-closed mid-spin dialog still owes the player their prize
		self:claimPrize()
	end
	self.activeSpinToken = nil
	self.isSpinning = false
end

function ClientSpinWheelManager.closeDialog(self: ClientSpinWheelManager)
	if not self.isOverlayOpen then
		return
	end

	self.isOverlayOpen = false
	self:closeDialogGui()
	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientSpinWheelManager.getGuiRoot(self: ClientSpinWheelManager): any
	return self.dialog
end

function ClientSpinWheelManager.getHudElements(self: ClientSpinWheelManager): { number }
	return {}
end

function ClientSpinWheelManager.doesWantBlur(self: ClientSpinWheelManager): boolean
	return false
end

-- called by the overlay tracker when another overlay takes over
function ClientSpinWheelManager.notifyForceEnd(self: ClientSpinWheelManager)
	self.isOverlayOpen = false
	self:closeDialogGui()
end

function ClientSpinWheelManager.notifyClickOutside(self: ClientSpinWheelManager)
	-- keep the dialog up while the wheel is mid-spin so the result isn't missed
	if self.isSpinning then
		return
	end

	self:closeDialog()
end

-- the spin counts and discount flag: in the init data, and again after every spin, purchase or day change
function ClientSpinWheelManager.setSpinState(self: ClientSpinWheelManager, state: any)
	if type(state) ~= "table" or type(state.freeSpins) ~= "number" or type(state.paidSpins) ~= "number" then
		return
	end

	self.spinState = {
		freeSpins = state.freeSpins,
		paidSpins = state.paidSpins,
		isDiscountAvailable = state.isDiscountAvailable == true,
	}
	self:updateHudButton()

	-- mid-animation the counts already reflect the consumed spin; the animation completion re-refreshes anyway
	if self.isOverlayOpen and not self.isSpinning then
		self:refreshButtons()
		self:rebuildOddsList()
	end
end

-- the init data: the state plus the wheel's catalog and the Robux product ids
function ClientSpinWheelManager.setSpinWheelData(self: ClientSpinWheelManager, data: any)
	if type(data) ~= "table" then
		return
	end

	self.segments = if type(data.catalog) == "table" then data.catalog :: { Segment } else {}
	self.robuxProductIds = if type(data.robuxProductIds) == "table" then data.robuxProductIds else {}
	self:setSpinState(data)

	if self.isOverlayOpen then
		self:rebuildWheelFace()
		self:rebuildOddsList()
	end
end

-- the HUD button lives in the main HUD ScreenGui, which ScreenGuiManager owns and wires up
function ClientSpinWheelManager.setHudButton(self: ClientSpinWheelManager, button: any)
	self.hudButton = button
	self.hudAlertLabel = button:FindFirstChild("Alert")
	if not self.hudAlertLabel then
		warn("ClientSpinWheelManager: the LuckySpin button has no Alert label; no spin badge")
	end
	self.hudTwitcher = ButtonTwitcher.new(button)
	self:updateHudButton()
end

function ClientSpinWheelManager.init(self: ClientSpinWheelManager)
	RemoteEvents.NotifySpinWheelState.OnClientEvent:Connect(function(state)
		self:setSpinState(state)
	end)
	RemoteEvents.NotifySpinWheelResult.OnClientEvent:Connect(function(segmentIndex)
		self:onSpinResult(segmentIndex)
	end)

	-- the HUD badge only needs refreshing once a second (a day can roll over while the game is open)
	ClientTicker.every(1, function()
		self:updateHudButton()
	end)

	-- the gui is authored in Studio and may not have been copied to PlayerGui yet, so wait for it off the startup path
	task.spawn(function()
		self:setUpGui()
	end)
end

function ClientSpinWheelManager.setUpGui(self: ClientSpinWheelManager)
	local playerGui = player:WaitForChild("PlayerGui")
	local gui: any = playerGui:WaitForChild("SpinWheel", 10)
	if not gui then
		warn("ClientSpinWheelManager: SpinWheel gui missing from PlayerGui; the spin wheel dialog is disabled")
		return
	end

	local dialog: any = gui:FindFirstChild("Dialog")
	local wheel: any = dialog and dialog:FindFirstChild("Wheel")
	local face: any = wheel and wheel:FindFirstChild("Face")
	local fallbackPrizeTemplate: any = wheel and wheel:FindFirstChild("PrizeTemplate")
	local oddsList: any = dialog and dialog:FindFirstChild("OddsList")
	local oddsRowTemplate: any = oddsList and oddsList:FindFirstChild("RowTemplate")
	local buttons: any = dialog and dialog:FindFirstChild("Buttons")
	local spinButton: any = buttons and buttons:FindFirstChild("Spin")
	local buy1Button: any = buttons and buttons:FindFirstChild("Buy1")
	local buy5Button: any = buttons and buttons:FindFirstChild("Buy5")
	local spinLabel: any = spinButton and spinButton:FindFirstChild("Spin")
	if not face or not fallbackPrizeTemplate or not oddsRowTemplate or not spinButton or not spinLabel or not buy1Button or not buy5Button then
		warn("ClientSpinWheelManager: SpinWheel needs Dialog/Wheel/Face, Wheel/PrizeTemplate, Dialog/OddsList/RowTemplate and Dialog/Buttons/Spin (with a Spin label), Buy1 and Buy5; the dialog is disabled")
		return
	end

	-- the faces are cloned at runtime, so a respawn must not recreate the gui from StarterGui
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = DISPLAY_ORDER
	self.gui = gui
	self.dialog = dialog
	self.wheelFace = face

	fallbackPrizeTemplate.Visible = false
	self.fallbackPrizeTemplate = fallbackPrizeTemplate
	local timeSkipPrizeTemplate: any = wheel:FindFirstChild("TimeSkipPrizeTemplate")
	if timeSkipPrizeTemplate then
		timeSkipPrizeTemplate.Visible = false
		self.timeSkipPrizeTemplate = timeSkipPrizeTemplate
	end
	for rarity, templateName in DRAGON_PRIZE_TEMPLATE_NAMES do
		local template: any = wheel:FindFirstChild(templateName)
		if template then
			template.Visible = false
			self.dragonPrizeTemplatesByRarity[rarity] = template
		end
	end
	local eggPrizeTemplate: any = wheel:FindFirstChild(EGG_PRIZE_TEMPLATE_NAME)
	if eggPrizeTemplate then
		eggPrizeTemplate.Visible = false
		self.eggPrizeTemplate = eggPrizeTemplate
	end
	-- the other authored faces (the legendary dragon, the worker box and the unknown-prize faces) are not used here
	for _, unusedName in { "PetPrizeLegendaryTemplate", "BoxWorkerPrizeTemplate", "UnknownPetTemplate", "UnknownWorkerTemplate" } do
		local unused: any = wheel:FindFirstChild(unusedName)
		if unused then
			unused.Visible = false
		end
	end

	self.oddsList = oddsList
	oddsRowTemplate.Visible = false
	self.oddsRowTemplate = oddsRowTemplate

	local resultLabel: any = dialog:FindFirstChild("Result")
	if resultLabel then
		resultLabel.RichText = true
		self.resultLabel = resultLabel
	end

	local title: any = dialog:FindFirstChild("Title")
	local exitButton: any = (title and title:FindFirstChild("Exit")) or dialog:FindFirstChild("Exit")
	if exitButton then
		exitButton.Activated:Connect(function()
			self:closeDialog()
		end)
	else
		warn("ClientSpinWheelManager: SpinWheel has no Dialog/Exit or Dialog/Title/Exit button")
	end

	local oddsToggle: any = dialog:FindFirstChild("OddsToggle")
	if oddsToggle then
		self.oddsToggle = oddsToggle
		oddsToggle.RichText = true
		oddsToggle.Activated:Connect(function()
			self.showOdds = not self.showOdds
			oddsToggle.Text = if self.showOdds then "☑ Show Odds" else "☐ Show Odds"
			self:rebuildOddsList()
		end)
	end

	local fastToggle: any = dialog:FindFirstChild("FastToggle")
	if fastToggle then
		self.fastToggle = fastToggle
		fastToggle.Activated:Connect(function()
			self.fastSpin = not self.fastSpin
			fastToggle.Text = if self.fastSpin then "☑ Fast Spin" else "☐ Fast Spin"
		end)
	end

	self.spinButton = spinButton
	self.spinLabel = spinLabel
	spinButton.Text = ""
	spinButton.Activated:Connect(function()
		self:onSpinPressed()
	end)

	self.buy1Button = buy1Button
	buy1Button.Activated:Connect(function()
		if not self.isSpinning then
			self:promptBuyOne()
		end
	end)

	self.buy5Button = buy5Button
	buy5Button.Activated:Connect(function()
		if self.isSpinning then
			return
		end
		local productId = self:getProductId("five")
		if productId then
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end)

	for _, button in { spinButton, buy1Button, buy5Button } do
		local gradient = button:FindFirstChildOfClass("UIGradient")
		self.authoredButtonStyles[button] = {
			color = button.BackgroundColor3,
			gradientColor = if gradient then gradient.Color else nil,
		}
	end
end

function ClientSpinWheelManager.new(): ClientSpinWheelManager
	local self = setmetatable({} :: ClientSpinWheelManagerFields, ClientSpinWheelManager)

	self.gui = nil
	self.dialog = nil
	self.wheelFace = nil
	self.fallbackPrizeTemplate = nil
	self.timeSkipPrizeTemplate = nil
	self.dragonPrizeTemplatesByRarity = {}
	self.eggPrizeTemplate = nil
	self.oddsList = nil
	self.oddsRowTemplate = nil
	self.oddsToggle = nil
	self.fastToggle = nil
	self.spinButton = nil
	self.spinLabel = nil
	self.buy1Button = nil
	self.buy5Button = nil
	self.authoredButtonStyles = {}
	self.resultLabel = nil
	self.segments = {}
	self.spinState = { freeSpins = 0, paidSpins = 0, isDiscountAvailable = false }
	self.robuxProductIds = {}
	self.robuxPrices = {}
	self.pricesRequested = {}
	self.activeSpinToken = nil
	self.isOverlayOpen = false
	self.isSpinning = false
	self.hudButton = nil
	self.hudAlertLabel = nil
	self.hudTwitcher = nil
	self.showOdds = false
	self.fastSpin = false
	self.wheelRotation = 0
	self.wheelLoopSound = nil
	self.random = Random.new()

	return self
end

local singleton = ClientSpinWheelManager.new()

return singleton
