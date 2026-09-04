--!strict

local ScreenGuiManager = {}
ScreenGuiManager.__index = ScreenGuiManager

local runService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local ParticleEffects = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("ParticleEffects")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientLuckInfoManager = require("./ClientLuckInfoManager")
local clientOptionsManager = require("./ClientOptionsManager")
local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local NumberLabelAnimator = require("./NumberLabelAnimator")
local overlayTracker = require("./OverlayTracker")
-- vendored library (out of scope per CLAUDE.md); crosses this boundary untyped
local ParticleEmitter: any = require("./Libs/ParticleEmitter/ParticleEmitter") :: any
local Satchel = require("./Satchel")
local Types = require("./Types")
local clientFtueManager: Types.ClientFtueManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientIndexManager = require("./ClientIndexManager")
local clientRideController: Types.ClientRideController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientTradePlayerList: Types.ClientTradePlayerList -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientVanityUnlockedManager: Types.ClientVanityUnlockedManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance

local SYSTEM_MESSAGE_SEC = 5

type MessageData = {
	text: string,
	count: number,
	endTime: number,
}

type ScreenGuiManagerFields = {
	messages: { MessageData },
	coinNumberAnimator: NumberLabelAnimator.NumberLabelAnimator?,
	coinNumberAnimatorConnect: RBXScriptConnection?,
	gemNumberAnimator: NumberLabelAnimator.NumberLabelAnimator?,
	gemNumberAnimatorConnect: RBXScriptConnection?,
	mutationConnect: RBXScriptConnection?,
	modificationsConnect: RBXScriptConnection?,
	inputBeganConnect: RBXScriptConnection?,
	prevItemPart: any?,
	latestEquippedItemId: any?,
	useSeparateFtueMessageFrame: boolean,
	ftueMessage: string?,
	tradeButtonHideReasonMap: { [string]: boolean },
	indexFrame: any?,
	isIndexFeatureEnabled: boolean,
	isBackpackEnabled: boolean?,
	gemsFrameBasePosition: UDim2,
	luckFrameBasePosition: UDim2,
	coinsFrameBasePosition: UDim2,
	optionButtonFrameBasePosition: UDim2,
	tradePlayerListOpenFrameBasePosition: UDim2,
}

export type ScreenGuiManager = typeof(setmetatable({} :: ScreenGuiManagerFields, ScreenGuiManager))

local function spawnLuckConfetti(parent: any)
	-- make a new anchor, not use use parent, so all the particles come from one point
	local anchor = Instance.new("Frame")
	anchor.BackgroundTransparency = 1
	anchor.Size = UDim2.new(0, 1, 0, 1)
	anchor.Position = UDim2.new(0.5, 0, 0.5, 0)
	anchor.Parent = parent

	local emitter = ParticleEmitter.fromParticle(ParticleEffects:FindFirstChild("LuckBurst"))

	emitter.Parent = anchor
	emitter:Bind("RenderStepped")
	emitter:Emit(20)

	-- can't use utils.safelyDisposeOfParticleParent(parent, sec, func) because this isn't a roblox particleeffect; we're using the ParticleEmitter library
	-- in the future maybe we can make that work

	task.delay(2, function()
		emitter.Enabled = false
		task.delay(emitter.Lifetime.Max, function()
			emitter:Destroy()
			anchor:Destroy()
		end)
	end)
end

function ScreenGuiManager.notifyBeginOverlay(self: ScreenGuiManager, overlay: Types.Overlay, hudElements: { number })
	if not utils.doesArrayContain(hudElements, enums.HudElements.COINS) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local coinsFrame = ScreenGui:WaitForChild("CoinsFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = UDim2.new(UDim.new(-0.3, 0), self.coinsFrameBasePosition.Y)

		local tween = tweenService:Create(coinsFrame, tweenInfo, goal)
		tween:Play()
	end

	-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
	-- if not utils.doesArrayContain(hudElements, enums.HudElements.GEMS) then
	-- 	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	-- 	local gemsFrame = ScreenGui:WaitForChild("GemsFrame")
	--
	-- 	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
	-- 	local goal = {}
	-- 	goal.Position = UDim2.new(UDim.new(-0.3, 0), self.gemsFrameBasePosition.Y)
	--
	-- 	local tween = tweenService:Create(gemsFrame, tweenInfo, goal)
	-- 	tween:Play()
	-- end

	if not utils.doesArrayContain(hudElements, enums.HudElements.BACKPACK) then
		self.isBackpackEnabled = Satchel:GetBackpackEnabled()

		Satchel:SetBackpackEnabled(false)
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.OPTION_BUTTON) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local optionButtonFrame = ScreenGui:WaitForChild("OptionButtonFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = UDim2.new(UDim.new(1.2, 0), self.optionButtonFrameBasePosition.Y)

		local tween = tweenService:Create(optionButtonFrame, tweenInfo, goal)
		tween:Play()
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.TRADE_BUTTON) then
		self:hideTradeButton("overlay")
		--[[
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")

		local tweenInfo = TweenInfo.new(
			0.2,
			Enum.EasingStyle.Quad
		)
		local goal = {}
		goal.Position = UDim2.new(UDim.new(1.2, 0), self.tradePlayerListOpenFrameBasePosition.Y)

		local tween = tweenService:Create(TradePlayerListOpenFrame, tweenInfo, goal)
		tween:Play()
		]]
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.LUCK) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local luckFrame = ScreenGui:WaitForChild("LuckFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = UDim2.new(UDim.new(-0.2, 0), self.luckFrameBasePosition.Y)

		local tween = tweenService:Create(luckFrame, tweenInfo, goal)
		tween:Play()
	end

	self.useSeparateFtueMessageFrame = true
	self:updateText()
end

function ScreenGuiManager.notifyEndOverlay(self: ScreenGuiManager, overlay: Types.Overlay, hudElements: { number })
	self.useSeparateFtueMessageFrame = false
	self:updateText()

	if not utils.doesArrayContain(hudElements, enums.HudElements.COINS) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local coinsFrame = ScreenGui:WaitForChild("CoinsFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = self.coinsFrameBasePosition

		local tween = tweenService:Create(coinsFrame, tweenInfo, goal)
		tween:Play()
	end

	-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
	-- if not utils.doesArrayContain(hudElements, enums.HudElements.GEMS) then
	-- 	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	-- 	local gemsFrame = ScreenGui:WaitForChild("GemsFrame")
	--
	-- 	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
	-- 	local goal = {}
	-- 	goal.Position = self.gemsFrameBasePosition
	--
	-- 	local tween = tweenService:Create(gemsFrame, tweenInfo, goal)
	-- 	tween:Play()
	-- end

	if not utils.doesArrayContain(hudElements, enums.HudElements.BACKPACK) then
		Satchel:SetBackpackEnabled(self.isBackpackEnabled)
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.OPTION_BUTTON) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local optionButtonFrame = ScreenGui:WaitForChild("OptionButtonFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = self.optionButtonFrameBasePosition

		local tween = tweenService:Create(optionButtonFrame, tweenInfo, goal)
		tween:Play()
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.TRADE_BUTTON) then
		self:showTradeButton("overlay")
		--[[
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")

		local tweenInfo = TweenInfo.new(
			0.2,
			Enum.EasingStyle.Quad
		)
		local goal = {}
		goal.Position = self.tradePlayerListOpenFrameBasePosition

		local tween = tweenService:Create(TradePlayerListOpenFrame, tweenInfo, goal)
		tween:Play()
		]]
	end

	if not utils.doesArrayContain(hudElements, enums.HudElements.LUCK) then
		local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
		local luckFrame = ScreenGui:WaitForChild("LuckFrame")

		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)
		local goal = {}
		goal.Position = self.luckFrameBasePosition

		local tween = tweenService:Create(luckFrame, tweenInfo, goal)
		tween:Play()
	end
end

function ScreenGuiManager.resetCoinValue(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local coinsFrame = ScreenGui:WaitForChild("CoinsFrame")
	coinsFrame.Visible = true
	local coinsLabel: any = utils.findFirstDescendant(coinsFrame, "Coins")

	coinsLabel.Text = string.format("%i", clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS))
end

function ScreenGuiManager.cleanupCoinAnimation(self: ScreenGuiManager)
	local coinNumberAnimator = self.coinNumberAnimator
	if coinNumberAnimator then
		coinNumberAnimator:destroy()
		self.coinNumberAnimator = nil
	end

	local coinNumberAnimatorConnect = self.coinNumberAnimatorConnect
	if coinNumberAnimatorConnect then
		coinNumberAnimatorConnect:Disconnect()
		self.coinNumberAnimatorConnect = nil
	end
end

function ScreenGuiManager.animateCoinsInRange(self: ScreenGuiManager, prevValue: number, value: number)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local coinsLabel: any = utils.findFirstDescendant(ScreenGui, "Coins")

	local duration = 0.6

	self:cleanupCoinAnimation()

	local coinNumberAnimator = NumberLabelAnimator.new(coinsLabel, prevValue, value - prevValue, duration)
	self.coinNumberAnimator = coinNumberAnimator
	self.coinNumberAnimatorConnect = (coinNumberAnimator.Completed :: RBXScriptSignal):Connect(function()
		coinNumberAnimator:destroy()
		self.coinNumberAnimator = nil

		local coinNumberAnimatorConnect = self.coinNumberAnimatorConnect
		if coinNumberAnimatorConnect then
			coinNumberAnimatorConnect:Disconnect()
			self.coinNumberAnimatorConnect = nil
		end
	end)
end

function ScreenGuiManager.notifyCoinValueChange(self: ScreenGuiManager, prevValue: number, value: number)
	self:animateCoinsInRange(prevValue, value)
end

-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
-- function ScreenGuiManager.resetGems(self: ScreenGuiManager)
-- 	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
-- 	local gemsFrame = ScreenGui:WaitForChild("GemsFrame")
-- 	local gemsTemplate = gemsFrame:WaitForChild("GemsTemplate")
--
-- 	for _, inst in (gemsFrame :: Instance):GetChildren() :: { any } do
-- 		if inst.Name == "GemsTemplate" then
-- 			inst.Visible = false
-- 			continue
-- 		end
-- 		if string.sub(inst.ClassName, 1, 2) == "UI" then
-- 			continue
-- 		end
--
-- 		inst:Destroy()
-- 	end
--
-- 	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
-- 	local gemsDataFolder = splendidDataFolder:WaitForChild("Gems")
--
-- 	local primaryElements = Elements.getPrimaryElementsSorted()
--
-- 	for _, primaryElement in primaryElements do
-- 		if not clientPlayerAttributesManager:get(Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)) then
-- 			continue
-- 		end
--
-- 		local gemsCount = clientPlayerAttributesManager:get(Elements.getGemsKeyForPrimaryElement(primaryElement))
--
-- 		for _, inst in gemsDataFolder:GetChildren() :: { any } do
-- 			if inst.Name ~= (enums.getName(enums.PrimaryElements, primaryElement) :: string) then
-- 				continue
-- 			end
--
-- 			local gemsEntry = gemsTemplate:Clone()
-- 			gemsEntry.Name = inst.Name
-- 			local imageLabel = gemsEntry:FindFirstChild("ImageLabel")
-- 			local textLabel = gemsEntry:FindFirstChild("Amount")
-- 			imageLabel.Image = "rbxassetid://" .. inst:GetAttribute(Attributes.ASSET_ID)
-- 			textLabel.Text = utils.formatLargeInteger(gemsCount)
-- 			textLabel.TextColor3 = utils.get2DColorForPrimaryElement(primaryElement)
-- 			textLabel.BorderColor3 = utils.getContrastingColor(utils.get2DColorForPrimaryElement(primaryElement))
-- 			gemsEntry.Visible = true
-- 			gemsEntry.Parent = gemsFrame
-- 		end
-- 	end
-- end

-- function ScreenGuiManager.cleanupGemAnimation(self: ScreenGuiManager)
-- 	local gemNumberAnimator = self.gemNumberAnimator
-- 	if gemNumberAnimator then
-- 		gemNumberAnimator:destroy()
-- 		self.gemNumberAnimator = nil
-- 	end
--
-- 	local gemNumberAnimatorConnect = self.gemNumberAnimatorConnect
-- 	if gemNumberAnimatorConnect then
-- 		gemNumberAnimatorConnect:Disconnect()
-- 		self.gemNumberAnimatorConnect = nil
-- 	end
-- end

-- function ScreenGuiManager.animateGemsInRange(self: ScreenGuiManager, primaryElement: number, prevValue: number, value: number)
-- 	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
-- 	local GemsFrame = ScreenGui:WaitForChild("GemsFrame")
-- 	local gemsEntry = GemsFrame:FindFirstChild(enums.getName(enums.PrimaryElements, primaryElement) :: string)
-- 	if not gemsEntry then
-- 		return
-- 	end
--
-- 	local textLabel: any = utils.findFirstDescendant(gemsEntry, "Amount")
--
-- 	local duration = 0.6
--
-- 	self:cleanupGemAnimation()
--
-- 	local gemNumberAnimator = NumberLabelAnimator.new(textLabel, prevValue, value - prevValue, duration)
-- 	self.gemNumberAnimator = gemNumberAnimator
-- 	self.gemNumberAnimatorConnect = (gemNumberAnimator.Completed :: RBXScriptSignal):Connect(function()
-- 		gemNumberAnimator:destroy()
-- 		self.gemNumberAnimator = nil
--
-- 		local gemNumberAnimatorConnect = self.gemNumberAnimatorConnect
-- 		if gemNumberAnimatorConnect then
-- 			gemNumberAnimatorConnect:Disconnect()
-- 			self.gemNumberAnimatorConnect = nil
-- 		end
-- 	end)
-- end

-- function ScreenGuiManager.notifyGemsValueChange(self: ScreenGuiManager, primaryElement: number, prevValue: number, value: number)
-- 	--print("gems value change", prevValue, value)
-- 	self:animateGemsInRange(primaryElement, prevValue, value)
-- end

function ScreenGuiManager.resetPlayerAttributeValues(self: ScreenGuiManager)
	self:cleanupCoinAnimation()
	-- legacy (2026-august-20): GemsFrame HUD disconnected, gems no longer earned/spent
	-- self:cleanupGemAnimation()

	self:resetCoinValue()
	-- self:resetGems()
end

function ScreenGuiManager.updateText(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local text: string = ""

	local overlayFtueMessageLabel = ScreenGui:WaitForChild("OverlayFtueMessageFrame"):WaitForChild("Label")

	local ftueMessage = self.ftueMessage
	if self.useSeparateFtueMessageFrame then
		if ftueMessage then
			overlayFtueMessageLabel.Text = ftueMessage
		else
			overlayFtueMessageLabel.Text = ""
		end
	else
		if ftueMessage then
			text = text .. ftueMessage
		end
		overlayFtueMessageLabel.Text = ""
	end

	for i, messageData in self.messages do
		if text ~= "" then
			text = text .. "\n"
		end
		text = text .. messageData.text
		if messageData.count > 1 then
			text = text .. string.format(" (x%i)", messageData.count)
		end
	end

	local systemMessageLabel = ScreenGui:WaitForChild("SystemMessage"):WaitForChild("Frame"):WaitForChild("Label")

	systemMessageLabel.Text = text
end

function ScreenGuiManager.showSystemMessage(self: ScreenGuiManager, text: string)
	--print("showSystemMessage", text)

	local latestMessageData: MessageData? = nil
	if #self.messages >= 1 then
		latestMessageData = self.messages[#self.messages]
	end

	if latestMessageData and latestMessageData.text == text then
		latestMessageData.count = latestMessageData.count + 1
		latestMessageData.endTime = workspace:GetServerTimeNow() + SYSTEM_MESSAGE_SEC
	else
		table.insert(self.messages, {
			text = text,
			count = 1,
			endTime = workspace:GetServerTimeNow() + SYSTEM_MESSAGE_SEC,
		})
	end

	self:updateText()
end

function ScreenGuiManager.showFtueMessage(self: ScreenGuiManager, text: string)
	self.ftueMessage = text

	self:updateText()
end

function ScreenGuiManager.clearFtueMessage(self: ScreenGuiManager)
	self.ftueMessage = nil

	self:updateText()
end

function ScreenGuiManager.putAwayHeldItem(self: ScreenGuiManager)
	-- the character rig's children only exist at runtime, so they are untyped here
	local character: any = player.Character
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end

	character.Humanoid:UnequipTools()
end

function ScreenGuiManager.equipMostRecentItem(self: ScreenGuiManager)
	if not self.latestEquippedItemId then
		return
	end

	local handle: any = utils.tryGetHandleForPlayerAndItemId(player, self.latestEquippedItemId)
	if not handle then
		-- this can definitely happen, if item is on the ground or merged away, etc.
		return
	end

	local tool = handle.Parent;

	(player.Character :: any).Humanoid:EquipTool(tool)
end

function ScreenGuiManager.toggleHeldItem(self: ScreenGuiManager)
	local tool = utils.getHoldingToolWithHandle(player)
	if not tool then
		self:equipMostRecentItem()
		return
	end

	self:putAwayHeldItem()
end

function ScreenGuiManager.setCurrentItemInstanceDisplay(self: ScreenGuiManager, inst: any)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local CurrentItemProperties = ScreenGui:WaitForChild("CurrentItemProperties")
	local line1 = CurrentItemProperties:WaitForChild("Line1")
	local line2 = CurrentItemProperties:WaitForChild("Line2")

	if inst then
		local name = inst:GetAttribute(Attributes.DISPLAY_NAME) or inst.Name

		local line1Str = name
		local rarity = inst:GetAttribute(Attributes.RARITY)
		if rarity and rarity ~= enums.Rarity.COMMON then
			line1Str = line1Str .. " (" .. (enums.getPublicName(enums.Rarity, rarity) :: string) .. ")"
		end

		line1.Text = line1Str
		line1.TextColor3 = utils.getColorForRarity(rarity)

		local uistroke = line1:FindFirstChild("UIStroke")
		uistroke.Color = utils.getContrastingColor(line1.TextColor3)
		uistroke.Transparency = 0

		local mutation = inst:GetAttribute(Attributes.MUTATION)

		line2.Text = utils.getMutModRichTextForInstance(inst)
		local colors = utils.getColorsForMutation(mutation or enums.Mutations.NORMAL)

		uistroke = line2:FindFirstChild("UIStroke")
		uistroke.Color = utils.getContrastingColor(colors[1])
		uistroke.Transparency = 0

		CurrentItemProperties.Visible = true
	else
		line1.Text = ""
		line2.Text = ""

		CurrentItemProperties.Visible = false
	end
end

function ScreenGuiManager.setStaminaDisplay(self: ScreenGuiManager, stamina: number?)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local CurrentItemProperties = ScreenGui:WaitForChild("CurrentItemProperties")
	local line3 = CurrentItemProperties:WaitForChild("Line3")

	if not stamina then
		line3.Visible = false
		return
	end

	line3.Text = string.format("Stamina: %i", stamina)
	line3.Visible = true
end

function ScreenGuiManager.setStaminaDisplayBlinkState(self: ScreenGuiManager, blinkState: any)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local CurrentItemProperties = ScreenGui:WaitForChild("CurrentItemProperties")
	local line3 = CurrentItemProperties:WaitForChild("Line3")

	if blinkState then
		line3.TextColor3 = utils.getLowStaminaColor()
	else
		line3.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

function ScreenGuiManager.updateFriendLuckBoostDisplay(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local friendLuckBoostFrame = ScreenGui:FindFirstChild("FriendLuckBoostFrame")
	if not friendLuckBoostFrame then
		return
	end

	local luckState = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData"):WaitForChild("Luck"):WaitForChild("State")
	local friendLuckPercent = (luckState:GetAttribute(Attributes.FRIEND_LUCK_PERCENT) :: number?) or 0
	local textLabel: any = utils.findFirstDescendant(friendLuckBoostFrame, "FriendLuckBoostText")
	if friendLuckPercent > 0 then
		textLabel.Text = string.format("Friend Boost: +%i%%", friendLuckPercent)
	else
		textLabel.Text = "Friend Boost: +0%"
	end
end

function ScreenGuiManager.updateLuckDisplay(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local LuckFrame = ScreenGui:FindFirstChild("LuckFrame")
	local LuckFillBar: any = utils.findFirstDescendant(LuckFrame, "FillBar")
	local TextLabel: any = utils.findFirstDescendant(LuckFrame, "TextLabel")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
	local luckDataFolder = splendidDataFolder:WaitForChild("Luck")
	local luckState: any = luckDataFolder:WaitForChild("State")
	TextLabel.Text = string.format("+%i%%", luckState:GetAttribute(Attributes.PERCENT))
	local baseTime = luckState:GetAttribute(Attributes.BASE_TIME)
	local beginTime = luckState:GetAttribute(Attributes.BEGIN_TIME)
	local endTime = luckState:GetAttribute(Attributes.END_TIME)

	local maxLabel: any = utils.findFirstDescendant(LuckFillBar, "Max")
	local timerLabel: any = utils.findFirstDescendant(LuckFillBar, "Timer")
	if beginTime and endTime then
		maxLabel.Visible = false
		timerLabel.Visible = true

		local duration = math.max(0, workspace:GetServerTimeNow() - baseTime)
		timerLabel.Text = utils.convertDurationSecToString(duration)
		-- show progress towards next step of time luck
		local fill: any = utils.findFirstDescendant(LuckFillBar, "Fill")
		local fillFrac = math.clamp((workspace:GetServerTimeNow() - beginTime) / (endTime - beginTime), 0, 1)
		fill.Size = UDim2.new(UDim.new(fillFrac, 0), fill.Size.Y :: UDim)
	else
		maxLabel.Visible = true
		timerLabel.Visible = false
	end
end

function ScreenGuiManager.run(self: ScreenGuiManager, deltaTime: number)
	local isChanged = false

	local now = workspace:GetServerTimeNow()
	local i = 1
	while i <= #self.messages do
		local messageData = self.messages[i]
		if messageData.endTime <= now then
			table.remove(self.messages, i)
			isChanged = true
		else
			i = i + 1
		end
	end

	if isChanged then
		self:updateText()
	end

	self:updateLuckDisplay()

	-- here we update whether our putAwayButton is visible or not

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local PutAwayButton = ScreenGui:WaitForChild("PutAwayButton")

	if clientFtueManager:isFtueActive() then
		PutAwayButton.Visible = false
		return
	end

	local isRiding = clientRideController:isRiding()
	if isRiding and (clientRideController:getRidingObj() :: any):GetAttribute(Attributes.PICKUP_NAME) ~= nil then
		self.latestEquippedItemId = nil
		local canPutAwayRidingDragon = clientRideController:isRidingAndControllingAndInFreeFlyZone()
		PutAwayButton.Visible = canPutAwayRidingDragon
		return
	end

	local tool: any = utils.getHoldingToolWithHandle(player)
	local isToolEquipped = tool ~= nil
	local currentItemPart: any
	if isToolEquipped then
		currentItemPart = tool:FindFirstChild("Handle")
	end

	if currentItemPart then
		self.latestEquippedItemId = currentItemPart:GetAttribute(Attributes.ITEM_ID)
	end

	PutAwayButton.Visible = (currentItemPart ~= nil)

	if currentItemPart ~= self.prevItemPart then
		local mutationConnect = self.mutationConnect
		if mutationConnect then
			mutationConnect:Disconnect()
			self.mutationConnect = nil
		end

		local modificationsConnect = self.modificationsConnect
		if modificationsConnect then
			modificationsConnect:Disconnect()
			self.modificationsConnect = nil
		end

		local inst: any
		if currentItemPart then
			if currentItemPart:HasTag(Tags.SHADOW) then
				inst = currentItemPart
			else
				inst = utils.tryGetModelForPlayerAndItemId(player, currentItemPart:GetAttribute(Attributes.ITEM_ID)) :: any
				if not inst then
					-- gems get here as of 2026-february-20, because they are just a part, no model
					-- gems can't be held as of 2026-march-26 so this probably isn't possible
					inst = currentItemPart
				end
			end
		end

		self:setCurrentItemInstanceDisplay(inst)

		if inst then
			self.mutationConnect = inst:GetAttributeChangedSignal(Attributes.MUTATION):Connect(function()
				self:setCurrentItemInstanceDisplay(inst)
			end)

			self.modificationsConnect = inst:GetAttributeChangedSignal(Attributes.MODIFICATIONS):Connect(function()
				self:setCurrentItemInstanceDisplay(inst)
			end)
		end

		-- central choke point for client handling of equipping and unequipping items
		if currentItemPart then
			clientVanityUnlockedManager:notifyItemEquipped(currentItemPart:GetAttribute(Attributes.ITEM_ID))
		else
			clientVanityUnlockedManager:notifyItemUnequipped()
		end

		self.prevItemPart = currentItemPart
	end
end

-- hack into hotbar and get its layout to put our button just to the right
function ScreenGuiManager.updatePositionPutAwayButton(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local PutAwayButton = ScreenGui:WaitForChild("PutAwayButton")

	local backpackGui = (PlayerGui :: any).BackpackGui
	local backpack = backpackGui:WaitForChild("Backpack")
	local hotbar = backpack:WaitForChild("Hotbar")

	local x = hotbar.Position.X + hotbar.Size.X
	local y = hotbar.Position.Y

	-- hack this 5 is some border size in the hotbar; should get it dynamically
	x = UDim.new(x.Scale, x.Offset + 5)
	y = UDim.new(y.Scale, y.Offset + 5)
	PutAwayButton.Position = UDim2.new(x, y)
end

function ScreenGuiManager.hideAllOtherGuis(self: ScreenGuiManager)
	for _, gui in PlayerGui:GetChildren() :: { any } do
		if not gui:IsA("ScreenGui") then
			continue
		end

		if gui.Name == "TouchGui" or gui.Name == "Freecam" then
			-- these are some key built-in ones
			continue
		end

		if gui.Name == "ScreenGui" or gui.Name == "BackpackGui" or gui.Name == "ItemScreenshotGui" or gui.Name:match("^Topbar") then
			continue
		end

		--print("disabling", gui)
		gui.Enabled = false
	end
end

function ScreenGuiManager.processPutAwayButtonActivated(self: ScreenGuiManager)
	local isRiding = clientRideController:isRiding()
	if isRiding then
		--print("trying to put away dragon")
		RemoteEvents.TryPutAwayRidingDragon:FireServer()
		return
	end

	self:toggleHeldItem()
end

function ScreenGuiManager.showTradeButton(self: ScreenGuiManager, reason: string?)
	if reason then
		self.tradeButtonHideReasonMap[reason] = nil
	end
	if next(self.tradeButtonHideReasonMap) then
		-- hide reason map is non-empty
		--[[
		print("not showing button because:")
		for reason, _ in self.tradeButtonHideReasonMap do
			print(reason)
		end
		]]
		return
	end

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")
	TradePlayerListOpenFrame.Visible = true
end

function ScreenGuiManager.hideTradeButton(self: ScreenGuiManager, reason: string?)
	if reason then
		self.tradeButtonHideReasonMap[reason] = true
	end

	if not next(self.tradeButtonHideReasonMap) then
		-- hide reason map is empty
		return
	end

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")
	TradePlayerListOpenFrame.Visible = false

	local TradeRequestedFrame = ScreenGui:FindFirstChild("TradeRequestedFrame")
	TradeRequestedFrame.Visible = false
end

function ScreenGuiManager.updateMergeAllButton(self: ScreenGuiManager)
	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
	local playerFeaturesDataFolder = splendidDataFolder:WaitForChild("PlayerFeatures")

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local FuseAllFrame = ScreenGui:FindFirstChild("FuseAllFrame")

	local ToggleLocked = FuseAllFrame:FindFirstChild("ToggleLocked")
	local StateOffButton = FuseAllFrame:FindFirstChild("StateOffButton")
	local StateOnButton = FuseAllFrame:FindFirstChild("StateOnButton")

	-- now we figure out which to show
	if playerFeaturesDataFolder:GetAttribute(Attributes.IS_MERGE_ALL_UNLOCKED) then
		ToggleLocked.Visible = false
		task.spawn(function()
			if not clientOptionsManager:haveOptionsLoaded() then
				clientOptionsManager:getEvent():Wait()
			end

			if clientOptionsManager:getOption(PlayerOptionKeys.MERGE_ALL_ENABLED) then
				StateOffButton.Visible = false
				StateOnButton.Visible = true
			else
				StateOffButton.Visible = true
				StateOnButton.Visible = false
			end
		end)
	else
		ToggleLocked.Visible = true
		StateOffButton.Visible = false
		StateOnButton.Visible = false
	end

	FuseAllFrame.Visible = true
end

function ScreenGuiManager.notifyTradingDisabled(self: ScreenGuiManager)
	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local TradeRequestedFrame = ScreenGui:FindFirstChild("TradeRequestedFrame")
	TradeRequestedFrame.Visible = false
end

function ScreenGuiManager.updateIndexFrameVisibility(self: ScreenGuiManager)
	if not self.indexFrame then
		return
	end

	(self.indexFrame :: any).Visible = self.isIndexFeatureEnabled and not clientFtueManager:isFtueActive()
end

function ScreenGuiManager.setIndexFeatureEnabled(self: ScreenGuiManager, isEnabled: boolean)
	self.isIndexFeatureEnabled = isEnabled
	self:updateIndexFrameVisibility()
end

function ScreenGuiManager.init(self: ScreenGuiManager)
	self:hideAllOtherGuis()

	runService.PostSimulation:Connect(function(deltaTime)
		self:run(deltaTime)
	end)

	-- put away button stuff

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")
	local PutAwayButton = ScreenGui:WaitForChild("PutAwayButton")
	local button: any = utils.findFirstDescendant(PutAwayButton, "ImageButton")
	button.Activated:Connect(function()
		self:processPutAwayButtonActivated()
	end)

	local unequipKeyCode = Enum.KeyCode.R

	self.inputBeganConnect = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if input.KeyCode == unequipKeyCode then
			self:processPutAwayButtonActivated()
		end
	end)

	--print("preferred input", userInputService.PreferredInput)
	if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
		local keyText: any = utils.findFirstDescendant(PutAwayButton, "KeyText")
		keyText.Text = userInputService:GetStringForKeyCode(unequipKeyCode)
	end

	self:updatePositionPutAwayButton()
	local backpackGui = (PlayerGui :: any).BackpackGui
	local backpack = backpackGui:WaitForChild("Backpack")
	local hotbar = backpack:WaitForChild("Hotbar")
	hotbar:GetAttributeChangedSignal("Size"):Connect(function()
		--print("hotbar changed size")
		self:updatePositionPutAwayButton()
	end)
	hotbar:GetAttributeChangedSignal("Position"):Connect(function()
		print("hotbar changed position")
		self:updatePositionPutAwayButton()
	end)

	-- game config will call in and show playerlistopenframe if proper

	local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")
	local ToggleTradePlayerListButton = TradePlayerListOpenFrame:FindFirstChild("ToggleTradePlayerListButton")
	ToggleTradePlayerListButton.Activated:Connect(function()
		--print("toggle trade player list")
		clientTradePlayerList:beginTradePlayerList()
	end)

	overlayTracker:addOverlayNotifier((self :: any) :: Types.OverlayNotifier)

	clientFtueManager:getIsEnabledEvent():Connect(function(isFtueEnabled: boolean)
		if isFtueEnabled then
			self:hideTradeButton("ftue")
		else
			self:showTradeButton("ftue")
		end
	end)

	self:updateLuckDisplay()

	local LuckFrame = ScreenGui:WaitForChild("LuckFrame")
	LuckFrame.Visible = true

	LuckFrame:WaitForChild("LuckInfoButton").Activated:Connect(function()
		clientLuckInfoManager:beginDialog()
	end)

	local indexFrame: any = ScreenGui:WaitForChild("IndexFrame")
	self.indexFrame = indexFrame
	self:updateIndexFrameVisibility()

	indexFrame:WaitForChild("IndexButton").Activated:Connect(function()
		clientIndexManager:toggleIndex()
	end)

	clientFtueManager:getIsEnabledEvent():Connect(function()
		self:updateIndexFrameVisibility()
	end)

	local friendLuckBoostFrame = ScreenGui:FindFirstChild("FriendLuckBoostFrame")
	if friendLuckBoostFrame then
		friendLuckBoostFrame.Visible = not clientFtueManager:isFtueActive()
		self:updateFriendLuckBoostDisplay()

		clientFtueManager:getIsEnabledEvent():Connect(function(isFtueEnabled: boolean)
			friendLuckBoostFrame.Visible = not isFtueEnabled
		end)

		local inviteFriendButton: any = utils.findFirstDescendant(friendLuckBoostFrame, "InviteFriendButton")
		if inviteFriendButton then
			local isInviting = false
			SocialService.GameInvitePromptClosed:Connect(function()
				isInviting = false
			end)

			inviteFriendButton.Activated:Connect(function()
				if isInviting then
					return
				end
				local ok, canInvite = pcall(function()
					return SocialService:CanSendGameInviteAsync(player)
				end)
				if not ok or not canInvite then
					return
				end
				isInviting = true
				SocialService:PromptGameInvite(player)
			end)
		end
	end

	local FuseAllFrame = ScreenGui:FindFirstChild("FuseAllFrame")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
	local playerFeaturesDataFolder: any = splendidDataFolder:FindFirstChild("PlayerFeatures")
	playerFeaturesDataFolder:GetAttributeChangedSignal(Attributes.IS_MERGE_ALL_UNLOCKED):Connect(function()
		--print("updated merge all unlocked", playerFeaturesDataFolder:GetAttribute(Attributes.IS_MERGE_ALL_UNLOCKED))
		self:updateMergeAllButton()
		if playerFeaturesDataFolder:GetAttribute(Attributes.IS_MERGE_ALL_UNLOCKED) then
			-- celebrate it
			self:showSystemMessage("You may now Fuse All! Turn it on to fuse <b>EVERYTHING</b>.")

			local constraint = FuseAllFrame:FindFirstChild("UISizeConstraint")
			local factor = 1.2
			local currentSize = FuseAllFrame.Size
			local frameGoal = {
				Size = UDim2.new(
					currentSize.X.Scale * factor,
					currentSize.X.Offset * factor,
					currentSize.Y.Scale * factor,
					currentSize.Y.Offset * factor
				),
			}
			local frameTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true, 0)
			tweenService:Create(FuseAllFrame, frameTweenInfo, frameGoal):Play()

			local constraintSize = constraint.MaxSize
			local constraintGoal = {
				MaxSize = Vector2.new(constraintSize.X * factor, constraintSize.Y * factor),
			}
			local constraintTweenInfo =
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true, 0)
			tweenService:Create(constraint, constraintTweenInfo, constraintGoal):Play()
		end
	end)
	self:updateMergeAllButton()

	local StateOffButton = FuseAllFrame:FindFirstChild("StateOffButton")
	local StateOnButton = FuseAllFrame:FindFirstChild("StateOnButton")

	StateOffButton.Activated:Connect(function()
		StateOffButton.Visible = false
		StateOnButton.Visible = true

		clientOptionsManager:setOption(PlayerOptionKeys.MERGE_ALL_ENABLED, true)
	end)

	StateOnButton.Activated:Connect(function()
		StateOffButton.Visible = true
		StateOnButton.Visible = false

		clientOptionsManager:setOption(PlayerOptionKeys.MERGE_ALL_ENABLED, false)
	end)
end

function ScreenGuiManager.new(): ScreenGuiManager
	local self = setmetatable({} :: ScreenGuiManagerFields, ScreenGuiManager)

	self.messages = {}

	self.mutationConnect = nil
	self.modificationsConnect = nil

	self.prevItemPart = nil
	self.latestEquippedItemId = nil

	self.useSeparateFtueMessageFrame = false

	-- only displays when no blocking reasons
	self.tradeButtonHideReasonMap = {}

	self.indexFrame = nil
	self.isIndexFeatureEnabled = true

	local ScreenGui: any = PlayerGui:WaitForChild("ScreenGui")

	local gemsFrame = ScreenGui:WaitForChild("GemsFrame")
	self.gemsFrameBasePosition = gemsFrame.Position

	local luckFrame = ScreenGui:WaitForChild("LuckFrame")
	self.luckFrameBasePosition = luckFrame.Position

	local luckState = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData"):WaitForChild("Luck"):WaitForChild("State")
	local lastLuckPercent = luckState:GetAttribute(Attributes.PERCENT) :: number
	luckState:GetAttributeChangedSignal(Attributes.PERCENT):Connect(function()
		local newPercent = luckState:GetAttribute(Attributes.PERCENT) :: number
		if newPercent > lastLuckPercent then
			spawnLuckConfetti(utils.findFirstDescendant(luckFrame, "Clover"))
		end
		lastLuckPercent = newPercent
	end)
	luckState:GetAttributeChangedSignal(Attributes.FRIEND_LUCK_PERCENT):Connect(function()
		self:updateFriendLuckBoostDisplay()
	end)

	local coinsFrame = ScreenGui:WaitForChild("CoinsFrame")
	self.coinsFrameBasePosition = coinsFrame.Position

	local optionButtonFrame = ScreenGui:WaitForChild("OptionButtonFrame")
	self.optionButtonFrameBasePosition = optionButtonFrame.Position

	local TradePlayerListOpenFrame = ScreenGui:FindFirstChild("TradePlayerListOpenFrame")
	self.tradePlayerListOpenFrameBasePosition = TradePlayerListOpenFrame.Position

	return self
end

function ScreenGuiManager.initClass(deps: any)
	clientFtueManager = deps.clientFtueManager
	clientRideController = deps.clientRideController
	clientTradePlayerList = deps.clientTradePlayerList
	clientVanityUnlockedManager = deps.clientVanityUnlockedManager
end

local singleton = ScreenGuiManager.new()

return singleton
