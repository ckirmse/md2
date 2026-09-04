--!strict

local ClientTradingManager = {}
ClientTradingManager.__index = ClientTradingManager

local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")


local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")
local screenGuiManager = require("./ScreenGuiManager")

local EMPTY_FRAME_NAME = "EmptyFrame"
local PARTNER_OFFER_ITEM_FRAME_NAME = "PartnerOfferItemFrame"
local PLAYER_OFFER_ITEM_FRAME_NAME = "PlayerOfferItemFrame"

local FLASH_DURATION = 0.2

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("Trading")

local CancelConfirmation: any = GuiRoot:WaitForChild("CancelConfirmation")

type ClientTradingManagerFields = {
	instructionsTween: any,
	partnerOffer: any,
	partnerPlayerName: any,
	playerOffer: any,
	state: any,
	tradePlayerName: any,
}

export type ClientTradingManager = typeof(setmetatable({} :: ClientTradingManagerFields, ClientTradingManager))

function ClientTradingManager.getGuiRoot(self: ClientTradingManager): Instance
	return GuiRoot
end

function ClientTradingManager.notifyForceEnd(self: ClientTradingManager)
	RemoteEvents.TryCancelTrade:FireServer(self.partnerPlayerName)
	self:cleanupTrading()
end

function ClientTradingManager.notifyClickOutside(self: ClientTradingManager)
	if self.state == enums.TradingState.EXECUTING then
		return
	end

	CancelConfirmation.Visible = true
end

function ClientTradingManager.getHudElements(self: ClientTradingManager)
	return {}
end

function ClientTradingManager.tryGetPlayerOfferItemDescriptorForItemId(self: ClientTradingManager, itemId: any)
	for _, itemDescriptor in self.playerOffer.itemDescriptors do
		if itemDescriptor.itemId ~= itemId then
			continue
		end
		return itemDescriptor
	end
	return nil
end

function ClientTradingManager.getPlayerOfferCount(self: ClientTradingManager, itemId: any)
	local itemDescriptor = self:tryGetPlayerOfferItemDescriptorForItemId(itemId)
	if not itemDescriptor then
		return 0
	end
	return itemDescriptor.count
end

function ClientTradingManager.updatePlayerItemsVisualsForItemIdWithItemFrame(self: ClientTradingManager, itemId: any, itemFrame: any, doAnimate: any)
	local obj: any = utils.tryGetObjByPlayerAndItemId(player, itemId)
	if not obj then
		return
	end

	local displayName = obj:GetAttribute(Attributes.DISPLAY_NAME) :: string
	local totalCount = obj:GetAttribute(Attributes.COUNT) :: number
	local offerCount = self:getPlayerOfferCount(itemId)
	local remainingCount = totalCount - offerCount

	local rarity = obj:GetAttribute(Attributes.RARITY)
	local mutation = obj:GetAttribute(Attributes.MUTATION)
	local encodedModifications = obj:GetAttribute(Attributes.MODIFICATIONS)
	local modifications = utils.getDecodedModifications(encodedModifications)

	local mutModText = utils.getMutModText(mutation, modifications)
	local richText
	if remainingCount == 0 then
		richText = utils.getColoredText(string.format("%s%s (%i)", displayName, mutModText, remainingCount), Color3.fromRGB(128, 128, 128))
	else
		richText = utils.getColoredTextForRarity(string.format("%s%s (%i)", displayName, mutModText, remainingCount), rarity)
	end

	;(utils.findFirstDescendant(itemFrame, "TextLabel") :: any).Text = richText

	if doAnimate then
		-- zap the background white and fade back to default color (black)
		local backgroundColor = Color3.fromRGB(0, 0, 0)

		itemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		tweenService:Create(itemFrame, TweenInfo.new(FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = backgroundColor}):Play()
	end

end

function ClientTradingManager.updatePlayerItemsVisualsForItemId(self: ClientTradingManager, itemId: any, doAnimate: any)
	local Main = GuiRoot:FindFirstChild("Main")
	local PlayerItems = Main:FindFirstChild("PlayerItems")
	local ItemsScroll = PlayerItems:FindFirstChild("ItemsScroll")
	local itemFrame: any = utils.findFirstDescendantWithAttribute(ItemsScroll, Attributes.ITEM_ID, itemId)
	if not itemFrame then
		warn("can't find item frame for", itemId)
		return
	end

	self:updatePlayerItemsVisualsForItemIdWithItemFrame(itemId, itemFrame, doAnimate)
end

function ClientTradingManager.updatePlayerOfferVisualsForItemId(self: ClientTradingManager, itemId: any, doAnimate: any)
	local obj: any = utils.tryGetObjByPlayerAndItemId(player, itemId)
	if not obj then
		return
	end

	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local Slots = PlayerTray:FindFirstChild("Slots")
	local ItemFrameTemplate: any = Slots:FindFirstChild("ItemFrameTemplate")
	local EmptyFrameTemplate = Slots:FindFirstChild("EmptyFrameTemplate")

	-- first off, do we even want this item any longer?
	local offerCount = self:getPlayerOfferCount(itemId)
	local itemFrame: any = utils.findFirstDescendantWithAttribute(Slots, Attributes.ITEM_ID, itemId)

	if offerCount > 0 then
		-- this item needs to be shown in a slot
		if not itemFrame then
			local emptyFrame = Slots:FindFirstChild(EMPTY_FRAME_NAME)
			if emptyFrame then
				-- there _should_ always be one
				emptyFrame:Destroy()
			end


			itemFrame = ItemFrameTemplate:Clone()
			itemFrame.Name = "PlayerOfferItemFrame"
			itemFrame:SetAttribute(Attributes.ITEM_ID, itemId)
			itemFrame.Visible = true

			local button = itemFrame:FindFirstChild("Button")
			button.Activated:Connect(
				function()
					if self.state ~= enums.TradingState.PLAYER_OPENED and self.state ~= enums.TradingState.BOTH_OPENED and self.state ~= enums.TradingState.PLAYER_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_LOCKED_OFFER and self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_ACCEPTED then
						return
					end

					if self:tryRemoveItemFromOffer(itemId) then
						if self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
							RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
							self:setState(enums.TradingState.BOTH_OPENED)
						elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
							RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
							self:setState(enums.TradingState.BOTH_OPENED)
						elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
							RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
							self:setState(enums.TradingState.BOTH_OPENED)
						end
					end
				end
			)
		end

		local displayName = obj:GetAttribute(Attributes.DISPLAY_NAME) :: string
		local rarity = obj:GetAttribute(Attributes.RARITY)
		local mutation = obj:GetAttribute(Attributes.MUTATION)
		local encodedModifications = obj:GetAttribute(Attributes.MODIFICATIONS)
		local modifications = utils.getDecodedModifications(encodedModifications)

		local mutModText = utils.getMutModText(mutation, modifications)
		local richText = utils.getColoredTextForRarity(string.format("%s%s (%i)", displayName, mutModText, offerCount), rarity)
		;(utils.findFirstDescendant(itemFrame, "TextLabel") :: any).Text = richText
		;(utils.findFirstDescendant(itemFrame, "EditMark") :: any).Visible = false

		itemFrame.Parent = Slots

		if doAnimate then
			-- zap the background white and fade back to default color (black)
			local backgroundColor = Color3.fromRGB(0, 0, 0)

			itemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			tweenService:Create(itemFrame, TweenInfo.new(FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = backgroundColor}):Play()
		end
	else
		-- this item needs to NOT be shown in a slot
		if itemFrame then
			itemFrame:Destroy()
		end
		local emptyFrame: any = EmptyFrameTemplate:Clone()
		emptyFrame.Name = EMPTY_FRAME_NAME

		local button = emptyFrame:FindFirstChild("Button")
		button.Activated:Connect(
			function()
				if self.state ~= enums.TradingState.PLAYER_OPENED and self.state ~= enums.TradingState.BOTH_OPENED and self.state ~= enums.TradingState.PLAYER_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_LOCKED_OFFER and self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_ACCEPTED then
					return
				end

				if self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				end
			end
		)

		emptyFrame.Visible = true
		emptyFrame.Parent = Slots
	end

	PlayerTray:FindFirstChild("TapToRemoveLabel").Visible = #self.playerOffer.itemDescriptors > 0
end

function ClientTradingManager.updatePartnerOfferVisuals(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")


	local PartnerSlots = PartnerTray:FindFirstChild("Slots")
	local ItemFrameTemplate: any = PartnerSlots:FindFirstChild("ItemFrameTemplate")
	local EmptyFrameTemplate = PartnerSlots:FindFirstChild("EmptyFrameTemplate")
	for _, inst in PartnerSlots:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst.Visible = false
		if inst.Name == "ItemFrameTemplate" then
			continue
		end
		if inst.Name == "EmptyFrameTemplate" then
			continue
		end

		inst:Destroy()
	end

	for _, itemDescriptor in self.partnerOffer.itemDescriptors do
		local itemFrame: any = ItemFrameTemplate:Clone()
		itemFrame.Name = PARTNER_OFFER_ITEM_FRAME_NAME
		itemFrame.Visible = true

		local displayName = itemDescriptor.displayName
		local rarity = itemDescriptor.rarity
		local mutation = itemDescriptor.mutation
		local modifications = itemDescriptor.modifications

		local mutModText = utils.getMutModText(mutation, modifications)
		local richText = utils.getColoredTextForRarity(string.format("%s%s (%i)", displayName, mutModText, itemDescriptor.count), rarity)
		;(utils.findFirstDescendant(itemFrame, "TextLabel") :: any).Text = richText

		itemFrame.Parent = PartnerSlots
	end

	for i = #self.partnerOffer.itemDescriptors + 1, Constants.MAX_TRADE_SLOTS do
		local emptyFrame: any = EmptyFrameTemplate:Clone()
		emptyFrame.Name = EMPTY_FRAME_NAME
		emptyFrame.Visible = true
		emptyFrame.Parent = PartnerSlots
	end

end

function ClientTradingManager.tryAddItemToOffer(self: ClientTradingManager, itemId: any)
	-- find item in backpack/character
	local obj: any = utils.tryGetObjByPlayerAndItemId(player, itemId)
	if not obj then
		return false
	end

	-- use this to get total count
	local totalCount = obj:GetAttribute(Attributes.COUNT)
	if not totalCount or totalCount == 0 then
		return false
	end

	local offerCount = self:getPlayerOfferCount(itemId)
	local remainingCount = totalCount - offerCount
	if remainingCount <= 0 then
		return false
	end

	local itemDescriptor = self:tryGetPlayerOfferItemDescriptorForItemId(itemId)
	if itemDescriptor then
		itemDescriptor.count += 1
	else
		if #self.playerOffer.itemDescriptors >= Constants.MAX_TRADE_SLOTS then
			return false
		end

		table.insert(self.playerOffer.itemDescriptors,
			{
				itemId = itemId,
				count = 1,
			}
		)
	end

	local doAnimate

	doAnimate = false
	self:updatePlayerItemsVisualsForItemId(itemId, doAnimate)

	doAnimate = true
	self:updatePlayerOfferVisualsForItemId(itemId, doAnimate)

	return true
end

function ClientTradingManager.tryRemoveItemFromOffer(self: ClientTradingManager, itemId: any)
	-- find item in backpack/character
	local obj: any = utils.tryGetObjByPlayerAndItemId(player, itemId)
	if not obj then
		return false
	end

	for index, itemDescriptor in self.playerOffer.itemDescriptors do
		if itemDescriptor.itemId ~= itemId then
			continue
		end
		itemDescriptor.count -= 1
		if itemDescriptor.count <= 0 then
			table.remove(self.playerOffer.itemDescriptors, index)
		end
		break
	end

	local doAnimate

	doAnimate = true
	self:updatePlayerItemsVisualsForItemId(itemId, doAnimate)

	doAnimate = false
	self:updatePlayerOfferVisualsForItemId(itemId, doAnimate)

	return true
end

function ClientTradingManager.initPlayerItems(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local PlayerItems = Main:FindFirstChild("PlayerItems")
	local TapToAddLabel = PlayerItems:FindFirstChild("TapToAddLabel")
	local ItemsScroll = PlayerItems:FindFirstChild("ItemsScroll")
	local ItemFrameTemplate: any = ItemsScroll:FindFirstChild("ItemFrameTemplate")

	for _, inst in ItemsScroll:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst.Visible = false
		if inst.Name == "ItemFrameTemplate" then
			continue
		end

		inst:Destroy()
	end


	local tbl = utils.getPlayerHandles(player)
	local unequippables = utils.getPlayerUnequippables(player)
	-- note that table move actually performs a copy
	table.move(unequippables, 1, #unequippables, #tbl + 1, tbl)
	if #tbl == 0 then
		TapToAddLabel.Visible = false
		return
	end

	table.sort(tbl,
		function(a: any, b: any)
			local objA: any = utils.tryGetObjByPlayerAndItemId(player, a:GetAttribute(Attributes.ITEM_ID))
			local objB: any = utils.tryGetObjByPlayerAndItemId(player, b:GetAttribute(Attributes.ITEM_ID))

			local indexA = objA:GetAttribute(Attributes.INDEX)
			local indexB = objB:GetAttribute(Attributes.INDEX)
			if indexA and not indexB then
				return true
			end
			if not indexA and indexB then
				return false
			end
			if not indexA and not indexB then
				return objA.Name < objB.Name
			end

			return objA:GetAttribute(Attributes.INDEX) < objB:GetAttribute(Attributes.INDEX)
		end
	)

	local duration = 0.3
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true, -- reverses afterwards
		0
	)
	local baseSize = TapToAddLabel.Size
	local goal = {}
	local instructionsBaseSize = TapToAddLabel.Size
	goal.Size = UDim2.new(TapToAddLabel.Size.X.Scale, TapToAddLabel.Size.X.Offset, TapToAddLabel.Size.Y.Scale * 1.3, TapToAddLabel.Size.Y.Offset * 1.3)
	self.instructionsTween = tweenService:Create(TapToAddLabel, tweenInfo, goal)
	self.instructionsTween.Completed:Connect(
		function()
			-- sit it back to where it started
			TapToAddLabel.Size = baseSize
		end
	)
	self.instructionsTween:Play()

	TapToAddLabel.Visible = true

	for _, part in tbl do
		local itemId = part:GetAttribute(Attributes.ITEM_ID)

		-- we will use display name, and other attributes to color it or whatever.
		-- we can't use the tool name because it has the quantity baked in already

		local itemFrame: any = ItemFrameTemplate:Clone()
		itemFrame.Name = PLAYER_OFFER_ITEM_FRAME_NAME
		itemFrame:SetAttribute(Attributes.ITEM_ID, itemId)
		local doAnimate = false
		self:updatePlayerItemsVisualsForItemIdWithItemFrame(itemId, itemFrame, doAnimate)
		itemFrame.Visible = true

		itemFrame.Parent = ItemsScroll

		local button = itemFrame:FindFirstChild("Button")
		button.Activated:Connect(
			function()
				if self.state ~= enums.TradingState.PLAYER_OPENED and self.state ~= enums.TradingState.BOTH_OPENED and self.state ~= enums.TradingState.PLAYER_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_LOCKED_OFFER and self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_ACCEPTED then
					return
				end

				if self.instructionsTween then
					self.instructionsTween:Cancel()
					self.instructionsTween = nil

					TapToAddLabel.Size = instructionsBaseSize
				end

				if self:tryAddItemToOffer(itemId) then
					if self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
						RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
						self:setState(enums.TradingState.BOTH_OPENED)
					elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
						RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
						self:setState(enums.TradingState.BOTH_OPENED)
					elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
						RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
						self:setState(enums.TradingState.BOTH_OPENED)
					end
				end
			end
		)
	end

end

function ClientTradingManager.initTradeTrayContents(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")

	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PlayerSlots = PlayerTray:FindFirstChild("Slots")
	local PlayerEmptyFrameTemplate = PlayerSlots:FindFirstChild("EmptyFrameTemplate")

	for _, inst in PlayerSlots:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst.Visible = false
		if inst.Name == "ItemFrameTemplate" then
			continue
		end
		if inst.Name == "EmptyFrameTemplate" then
			continue
		end

		inst:Destroy()
	end
	for i = 1, Constants.MAX_TRADE_SLOTS do
		local emptyFrame: any = PlayerEmptyFrameTemplate:Clone()
		emptyFrame.Name = EMPTY_FRAME_NAME

		local button = emptyFrame:FindFirstChild("Button")
		button.Activated:Connect(
			function()
				if self.state ~= enums.TradingState.PLAYER_OPENED and self.state ~= enums.TradingState.BOTH_OPENED and self.state ~= enums.TradingState.PLAYER_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_LOCKED_OFFER and self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PARTNER_ACCEPTED then
					return
				end

				if self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
					RemoteEvents.TryRemoveTradeOffer:FireServer(self.partnerPlayerName)
					self:setState(enums.TradingState.BOTH_OPENED)
				end
			end
		)

		emptyFrame.Visible = true
		emptyFrame.Parent = PlayerSlots
	end

	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local PartnerSlots = PartnerTray:FindFirstChild("Slots")
	local PartnerEmptyFrameTemplate = PartnerSlots:FindFirstChild("EmptyFrameTemplate")

	for _, inst in PartnerSlots:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		inst.Visible = false
		if inst.Name == "ItemFrameTemplate" then
			continue
		end
		if inst.Name == "EmptyFrameTemplate" then
			continue
		end

		inst:Destroy()
	end
	for i = 1, Constants.MAX_TRADE_SLOTS do
		local emptyFrame: any = PartnerEmptyFrameTemplate:Clone()
		emptyFrame.Name = EMPTY_FRAME_NAME
		emptyFrame.Visible = true
		emptyFrame.Parent = PartnerSlots
	end
end

function ClientTradingManager.showItemEditMarks(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local itemFrames = utils.getAllDescendantsByName(PlayerTray, PLAYER_OFFER_ITEM_FRAME_NAME)
	for _, itemFrame in itemFrames do
		local editMark: any = utils.findFirstDescendant(itemFrame, "EditMark")
		editMark.Visible = true
	end
end

function ClientTradingManager.hideItemEditMarks(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local itemFrames = utils.getAllDescendantsByName(PlayerTray, PLAYER_OFFER_ITEM_FRAME_NAME)
	for _, itemFrame in itemFrames do
		local editMark: any = utils.findFirstDescendant(itemFrame, "EditMark")
		editMark.Visible = false
	end
end

function ClientTradingManager.beginPlayerOpened(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	Main.Visible = true
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local Actions = Main:FindFirstChild("Actions")

	PlayerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PlayerTray:FindFirstChild("TapToRemoveLabel").Visible = false

	PartnerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PartnerTray:FindFirstChild("PartnerOfferLabel").Text = string.format("%s offer", self.partnerPlayerName)

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Text = string.format("Waiting for %s to trade", self.partnerPlayerName)
	buttonDisabledLabel.Visible = true

	self:hideItemEditMarks()
end

function ClientTradingManager.beginBothOpened(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	Main.Visible = true
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local Actions = Main:FindFirstChild("Actions")

	PlayerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PlayerTray:FindFirstChild("UIStroke").Enabled = false
	PlayerTray:FindFirstChild("TapToRemoveLabel").Visible = false

	PartnerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PartnerTray:FindFirstChild("UIStroke").Enabled = false

	PartnerTray:FindFirstChild("PartnerOfferLabel").Text = string.format("%s offer", self.partnerPlayerName)

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = true

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false

	self:hideItemEditMarks()
end

function ClientTradingManager.beginPlayerLockedOffer(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local Actions = Main:FindFirstChild("Actions")

	PlayerTray:FindFirstChild("OfferMadeScreen").Text = string.format("%s offer", player.Name)
	PlayerTray:FindFirstChild("OfferMadeScreen").Visible = true
	PlayerTray:FindFirstChild("UIStroke").Enabled = true
	PlayerTray:FindFirstChild("TapToRemoveLabel").Visible = false

	PartnerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PartnerTray:FindFirstChild("UIStroke").Enabled = false

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Text = string.format("Waiting for offer from %s", self.partnerPlayerName)
	buttonDisabledLabel.Visible = true

	self:showItemEditMarks()
end

function ClientTradingManager.beginPartnerLockedOffer(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local Actions = Main:FindFirstChild("Actions")

	PlayerTray:FindFirstChild("OfferMadeScreen").Visible = false
	PlayerTray:FindFirstChild("UIStroke").Enabled = false

	PartnerTray:FindFirstChild("OfferMadeScreen").Text = string.format("%s offer", self.partnerPlayerName)
	PartnerTray:FindFirstChild("OfferMadeScreen").Visible = true
	PartnerTray:FindFirstChild("UIStroke").Enabled = true

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = true

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false

	self:hideItemEditMarks()
end

function ClientTradingManager.beginBothLockedOffer(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")
	local Actions = Main:FindFirstChild("Actions")

	PlayerTray:FindFirstChild("OfferMadeScreen").Text = string.format("%s offer", player.Name)
	PlayerTray:FindFirstChild("OfferMadeScreen").Visible = true
	PlayerTray:FindFirstChild("UIStroke").Enabled = true
	PlayerTray:FindFirstChild("TapToRemoveLabel").Visible = false

	PartnerTray:FindFirstChild("OfferMadeScreen").Text = string.format("%s offer", self.partnerPlayerName)
	PartnerTray:FindFirstChild("OfferMadeScreen").Visible = true
	PartnerTray:FindFirstChild("UIStroke").Enabled = true

	Actions:FindFirstChild("AcceptOfferButton").Visible = true
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false

	self:showItemEditMarks()
end

function ClientTradingManager.beginPlayerAccepted(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Text = string.format("Waiting for %s to accept", self.partnerPlayerName)
	buttonDisabledLabel.Visible = true

	self:hideItemEditMarks()
end

function ClientTradingManager.beginPartnerAccepted(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")

	Actions:FindFirstChild("AcceptOfferButton").Visible = true
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false
end

function ClientTradingManager.beginBothAccepted(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")


	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = true
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false

	self:hideItemEditMarks()
end

function ClientTradingManager.beginPlayerConfirmed(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Text = string.format("Waiting for %s to confirm", self.partnerPlayerName)
	buttonDisabledLabel.Visible = true
end

function ClientTradingManager.beginPartnerConfirmed(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = true
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Visible = false
end

function ClientTradingManager.beginExecuting(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Actions = Main:FindFirstChild("Actions")

	Actions:FindFirstChild("AcceptOfferButton").Visible = false
	Actions:FindFirstChild("AreYouSureButton").Visible = false
	Actions:FindFirstChild("MakeOfferButton").Visible = false

	local buttonDisabledLabel = Actions:FindFirstChild("ButtonDisabledLabel")
	buttonDisabledLabel.Text = string.format("Securely trading items")
	buttonDisabledLabel.Visible = true
end

function ClientTradingManager.setState(self: ClientTradingManager, state: any)

	self.state = state

	-- handle the transition
	if self.state == enums.TradingState.NONE then
		self.tradePlayerName = nil
		self.playerOffer = nil
		self.partnerOffer = nil
	elseif self.state == enums.TradingState.PLAYER_OPENED then
		self:beginPlayerOpened()
	elseif self.state == enums.TradingState.BOTH_OPENED then
		self:beginBothOpened()
	elseif self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
		self:beginPlayerLockedOffer()
	elseif self.state == enums.TradingState.PARTNER_LOCKED_OFFER then
		self:beginPartnerLockedOffer()
	elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		self:beginBothLockedOffer()
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		self:beginPlayerAccepted()
	elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
		self:beginPartnerAccepted()
	elseif self.state == enums.TradingState.BOTH_ACCEPTED then
		self:beginBothAccepted()
	elseif self.state == enums.TradingState.PLAYER_CONFIRMED then
		self:beginPlayerConfirmed()
	elseif self.state == enums.TradingState.PARTNER_CONFIRMED then
		self:beginPartnerConfirmed()
	elseif self.state == enums.TradingState.EXECUTING then
		self:beginExecuting()
	else
		warn("unknown trading state", self.state)
	end
end

function ClientTradingManager.notifyAcceptOfferActivated(self: ClientTradingManager)
	if self.state == enums.TradingState.NONE then
		return
	elseif self.state == enums.TradingState.PLAYER_OPENED then
		return
	elseif self.state == enums.TradingState.BOTH_OPENED then
		return
	elseif self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.PARTNER_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		RemoteEvents.TryAcceptTrade:FireServer(self.partnerPlayerName)
		self:setState(enums.TradingState.PLAYER_ACCEPTED)
		return
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		return
	elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
		RemoteEvents.TryAcceptTrade:FireServer(self.partnerPlayerName)
		self:setState(enums.TradingState.BOTH_ACCEPTED)
		return
	elseif self.state == enums.TradingState.BOTH_ACCEPTED then
		return
	elseif self.state == enums.TradingState.PLAYER_CONFIRMED then
		return
	elseif self.state == enums.TradingState.PARTNER_CONFIRMED then
		return
	elseif self.state == enums.TradingState.EXECUTING then
		return
	else
		warn("unknown trading state", self.state)
	end
end

function ClientTradingManager.notifyAreYouSureActivated(self: ClientTradingManager)
	if self.state == enums.TradingState.NONE then
		return
	elseif self.state == enums.TradingState.PLAYER_OPENED then
		return
	elseif self.state == enums.TradingState.BOTH_OPENED then
	elseif self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.PARTNER_LOCKED_OFFER then
	elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		return
	elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
		return
	elseif self.state == enums.TradingState.BOTH_ACCEPTED then
		RemoteEvents.TryConfirmTrade:FireServer(self.partnerPlayerName)
		self:setState(enums.TradingState.PLAYER_CONFIRMED)
		return
	elseif self.state == enums.TradingState.PLAYER_CONFIRMED then
		return
	elseif self.state == enums.TradingState.PARTNER_CONFIRMED then
		RemoteEvents.TryConfirmTrade:FireServer(self.partnerPlayerName)
		self:setState(enums.TradingState.EXECUTING)
		return
	elseif self.state == enums.TradingState.EXECUTING then
		return
	else
		warn("unknown trading state", self.state)
	end
end

function ClientTradingManager.notifyMakeOfferActivated(self: ClientTradingManager)
	if self.state == enums.TradingState.NONE then
		return
	elseif self.state == enums.TradingState.PLAYER_OPENED then
		return
	elseif self.state == enums.TradingState.BOTH_OPENED then
		RemoteEvents.TryLockTradeOffer:FireServer(self.partnerPlayerName, self.playerOffer)
		self:setState(enums.TradingState.PLAYER_LOCKED_OFFER)
	elseif self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.PARTNER_LOCKED_OFFER then
		RemoteEvents.TryLockTradeOffer:FireServer(self.partnerPlayerName, self.playerOffer)
		self:setState(enums.TradingState.BOTH_LOCKED_OFFER)
	elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		return
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		return
	elseif self.state == enums.TradingState.PARTNER_ACCEPTED then
		return
	elseif self.state == enums.TradingState.BOTH_ACCEPTED then
		return
	elseif self.state == enums.TradingState.PLAYER_CONFIRMED then
		return
	elseif self.state == enums.TradingState.PARTNER_CONFIRMED then
		return
	elseif self.state == enums.TradingState.EXECUTING then
		return
	else
		warn("unknown trading state", self.state)
	end
end

function ClientTradingManager.animateTradeCompleted(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PartnerTray = TradeTrays:FindFirstChild("PartnerTray")

	Main.Visible = false

	local partnerOfferItemFrames = utils.getAllDescendantsByName(PartnerTray, PARTNER_OFFER_ITEM_FRAME_NAME) :: { any }
	if #partnerOfferItemFrames == 0 then
		screenGuiManager:showSystemMessage(string.format("Your trade with %s is complete", self.partnerPlayerName))

		self:cleanupTrading()
		return
	end

	local messageTable = {
		default = "Enjoy your %i new items!",
		["1"] = "Enjoy your new item!",
	}
	local message = utils.getMessageFromTable(messageTable, #partnerOfferItemFrames)

	screenGuiManager:showSystemMessage(string.format(message, #partnerOfferItemFrames))

	local receivedItemFrames: { any } = {}
	local totalWidth = 0
	for _, partnerOfferItemFrame in partnerOfferItemFrames do
		local receivedItemFrame: any = partnerOfferItemFrame:Clone()
		receivedItemFrame.Name = "receivedItemFrame"
		receivedItemFrame.Position = UDim2.fromOffset(partnerOfferItemFrame.AbsolutePosition.X, partnerOfferItemFrame.AbsolutePosition.Y)
		receivedItemFrame.Size = UDim2.fromOffset(partnerOfferItemFrame.AbsoluteSize.X, partnerOfferItemFrame.AbsoluteSize.Y)

		receivedItemFrame.Parent = GuiRoot
		table.insert(receivedItemFrames, receivedItemFrame)

		totalWidth += receivedItemFrame.Size.X.Offset
	end

	local gapX = 20
	totalWidth += (#receivedItemFrames - 1) * gapX

	-- sort left to right
	table.sort(receivedItemFrames,
		function(a: any, b: any)
			return a.Position.X.Offset < b.Position.X.Offset
		end
	)

	-- animate to middle of screen
	local duration = 0.5
	local baseX = (GuiRoot.AbsoluteSize.X - totalWidth) / 2
	for i, receivedItemFrame in receivedItemFrames do
		local destPosition = UDim2.fromOffset(baseX, GuiRoot.AbsoluteSize.Y / 2 - receivedItemFrame.Size.Y.Offset / 2)

		tweenService:Create(receivedItemFrame, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = destPosition }):Play()

		baseX += receivedItemFrame.Size.X.Offset + gapX
	end

	task.wait(duration)

	--[[
	-- make a 2d particle effect on each received item
	for _, receivedItemFrame in receivedItemFrames do
		local emitter = ParticleEmitter.fromParticle(ParticleEffects:FindFirstChild("TradeReceiveItemsBurst"))
		emitter.Parent = receivedItemFrame
		emitter:Bind("RenderStepped")
		emitter:Emit(50)
	end
	]]

	task.wait(2)

	-- animate to bottom of screen (near hotbar)

	duration = 0.2
	for i, receivedItemFrame in receivedItemFrames do
		local destPosition = UDim2.fromOffset(receivedItemFrame.Position.X.Offset, GuiRoot.AbsoluteSize.Y )

		tweenService:Create(receivedItemFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = destPosition }):Play()
	end

	task.wait(duration)

	self:cleanupTrading()
end

function ClientTradingManager.beginTradingRequest(self: ClientTradingManager, playerName: any)
	if self.state ~= enums.TradingState.NONE then
		print("cannot begin trading while already trading in state", self.state)
		return
	end

	self.partnerPlayerName = playerName
	self.playerOffer = {
		-- this includes itemId, count
		itemDescriptors = {},
	}
	self.partnerOffer = {
		itemDescriptors = {},
	}

	self:initPlayerItems()
	self:initTradeTrayContents()

	self:setState(enums.TradingState.PLAYER_OPENED)

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientTradingManager.beginTradingAcceptRequest(self: ClientTradingManager, playerName: any)
	if self.state ~= enums.TradingState.NONE then
		print("cannot begin trading while already trading in state", self.state)
		return
	end

	--print("begin trade after request from", playerName)
	self.partnerPlayerName = playerName
	self.playerOffer = {
		-- this includes itemId, count
		itemDescriptors = {},
	}
	self.partnerOffer = {
		itemDescriptors = {},
	}

	self:initPlayerItems()
	self:initTradeTrayContents()

	self:setState(enums.TradingState.BOTH_OPENED)

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientTradingManager.notifyBeginTradeStatus(self: ClientTradingManager, playerName: any, doesAccept: any)
	if playerName ~= self.partnerPlayerName then
		print("notify of begin trade status from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	if self.state ~= enums.TradingState.PLAYER_OPENED then
		print("notify of begin trade status when we're not in that state", self.state)
		return
	end

	if not doesAccept then
		screenGuiManager:showSystemMessage("Your trade request was not accepted")

		self:cleanupTrading()
		return
	end

	self:setState(enums.TradingState.BOTH_OPENED)
end

function ClientTradingManager.notifyTradePartnerOffer(self: ClientTradingManager, playerName: any, partnerOffer: any)
	if playerName ~= self.partnerPlayerName then
		print("notify of trade offer from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	if self.state ~= enums.TradingState.BOTH_OPENED and self.state ~= enums.TradingState.PLAYER_LOCKED_OFFER then
		print("notify of trade offer when we're not in that state", self.state)
		return
	end

	--print("partner offer is", partnerOffer)
	self.partnerOffer = partnerOffer

	self:updatePartnerOfferVisuals()

	if self.state == enums.TradingState.BOTH_OPENED then
		self:setState(enums.TradingState.PARTNER_LOCKED_OFFER)
	elseif self.state == enums.TradingState.PLAYER_LOCKED_OFFER then
		self:setState(enums.TradingState.BOTH_LOCKED_OFFER)
	end
end

function ClientTradingManager.notifyTradePartnerRemoveOffer(self: ClientTradingManager, playerName: any)
	if playerName ~= self.partnerPlayerName then
		print("notify of trade remove offer from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	if self.state ~= enums.TradingState.PARTNER_LOCKED_OFFER and self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PLAYER_ACCEPTED then
		print("notify of trade remove offer when we're not in that state", self.state)
		return
	end

	self.partnerOffer = {
		itemDescriptors = {},
	}

	self:updatePartnerOfferVisuals()

	if self.state == enums.TradingState.PARTNER_LOCKED_OFFER then
		self:setState(enums.TradingState.BOTH_OPENED)
	elseif self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		self:setState(enums.TradingState.BOTH_OPENED)
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		self:setState(enums.TradingState.BOTH_OPENED)
	end
end

function ClientTradingManager.notifyTradePartnerAccepted(self: ClientTradingManager, playerName: any)
	if playerName ~= self.partnerPlayerName then
		print("notify of trade accepted from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	if self.state ~= enums.TradingState.BOTH_LOCKED_OFFER and self.state ~= enums.TradingState.PLAYER_ACCEPTED then
		print("notify of trade accepted when we're not in that state", self.state)
		return
	end

	if self.state == enums.TradingState.BOTH_LOCKED_OFFER then
		self:setState(enums.TradingState.PARTNER_ACCEPTED)
	elseif self.state == enums.TradingState.PLAYER_ACCEPTED then
		self:setState(enums.TradingState.BOTH_ACCEPTED)
	end
end

function ClientTradingManager.notifyTradePartnerConfirmed(self: ClientTradingManager, playerName: any)
	if playerName ~= self.partnerPlayerName then
		print("notify of trade confirmed from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	if self.state ~= enums.TradingState.BOTH_ACCEPTED and self.state ~= enums.TradingState.PLAYER_CONFIRMED then
		print("notify of trade confirmed when we're not in that state", self.state)
		return
	end

	if self.state == enums.TradingState.BOTH_ACCEPTED then
		self:setState(enums.TradingState.PARTNER_CONFIRMED)
	elseif self.state == enums.TradingState.PLAYER_CONFIRMED then
		self:setState(enums.TradingState.EXECUTING)
	end
end

function ClientTradingManager.notifyCancelTrade(self: ClientTradingManager, playerName: any)
	if playerName ~= self.partnerPlayerName then
		-- this can happen; could be a trade request that was canceled
		--print("notify of cancel trade from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	self:cleanupTrading()
end

function ClientTradingManager.notifyTradeComplete(self: ClientTradingManager, playerName: any)
	if playerName ~= self.partnerPlayerName then
		-- this shouldn't happen, generally, unless a player closed the ui at the last second
		print("notify of cancel trade from someone we are not trading with", playerName, self.partnerPlayerName)
		return
	end

	self:animateTradeCompleted()
end

function ClientTradingManager.notifyTradingDisabled(self: ClientTradingManager)
	self:cleanupTrading()
end

function ClientTradingManager.cleanupTrading(self: ClientTradingManager)
	if self.state == enums.TradingState.NONE then
		-- nothing to do!
		return
	end

	self:setState(enums.TradingState.NONE)

	if self.instructionsTween then
		self.instructionsTween:Cancel()
		self.instructionsTween = nil
	end

	CancelConfirmation.Visible = false

	GuiRoot.Enabled = false
	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientTradingManager.isTrading(self: ClientTradingManager)
	return GuiRoot.Enabled
end

function ClientTradingManager.init(self: ClientTradingManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local PlayerItems = Main:FindFirstChild("PlayerItems")
	local TapToAddLabel = PlayerItems:FindFirstChild("TapToAddLabel")
	local TradeTrays = Main:FindFirstChild("TradeTrays")
	local PlayerTray = TradeTrays:FindFirstChild("PlayerTray")
	local Actions = Main:FindFirstChild("Actions")

	if userInputService.PreferredInput == Enum.PreferredInput.Touch then
		TapToAddLabel.Text = "Tap item to add 1 to your offer"
		PlayerTray:FindFirstChild("TapToRemoveLabel").Text = "Tap to remove 1"
		Actions:FindFirstChild("MakeOfferButton").Text = "Tap to Make Offer"
	else
		TapToAddLabel.Text = "Click item to add 1 to your offer"
		PlayerTray:FindFirstChild("TapToRemoveLabel").Text = "Click to remove 1"
		Actions:FindFirstChild("MakeOfferButton").Text = "Click to Make Offer"
	end

	Actions:FindFirstChild("AcceptOfferButton").Activated:Connect(
		function()
			self:notifyAcceptOfferActivated()
		end
	)
	Actions:FindFirstChild("AreYouSureButton").Activated:Connect(
		function()
			self:notifyAreYouSureActivated()
		end
	)
	Actions:FindFirstChild("MakeOfferButton").Activated:Connect(
		function()
			self:notifyMakeOfferActivated()
		end
	)

	CancelConfirmation:FindFirstChild("KeepTradingButton").Activated:Connect(
		function()
			CancelConfirmation.Visible = false
		end
	)

	CancelConfirmation:FindFirstChild("CancelButton").Activated:Connect(
		function()
			RemoteEvents.TryCancelTrade:FireServer(self.partnerPlayerName)
			self:cleanupTrading()
		end
	)

	Main:WaitForChild("ExitButton").Activated:Connect(
		function()
			RemoteEvents.TryCancelTrade:FireServer(self.partnerPlayerName)
			self:cleanupTrading()
		end
	)

end

function ClientTradingManager.new(): ClientTradingManager
	local self = setmetatable({} :: ClientTradingManagerFields, ClientTradingManager)

	self.state = enums.TradingState.NONE

	return self
end

local singleton = ClientTradingManager.new()

return singleton
