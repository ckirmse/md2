--!strict

local collectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ClientRebirthManager = {}
ClientRebirthManager.__index = ClientRebirthManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance
local rebirthGui: any = playerGui:WaitForChild("Rebirth")

rebirthGui.DisplayOrder = 130

local REFRESH_INTERVAL_SEC = 1

type ClientRebirthManagerFields = {
	dialogFit: any,
	rewardsFrame: any,
	requirementsFrame: any,
	maxedOutFrame: any,
	incomeText: any,
	luckText: any,
	costFill: any,
	costText: any,
	petRequired: any,
	rebirthButton: any,
	rebirthButtonEnabledColor: Color3,
	refreshConnect: RBXScriptConnection?,
	timeSinceRefresh: number,
}

export type ClientRebirthManager = typeof(setmetatable({} :: ClientRebirthManagerFields, ClientRebirthManager))

function ClientRebirthManager.getGuiRoot(self: ClientRebirthManager)
	return rebirthGui
end

function ClientRebirthManager.getHudElements(self: ClientRebirthManager)
	return {}
end

function ClientRebirthManager.notifyForceEnd(self: ClientRebirthManager)
	self:cleanupRebirth()
end

function ClientRebirthManager.notifyClickOutside(self: ClientRebirthManager)
	self:notifyForceEnd()
end

function ClientRebirthManager.doesWantBlur(self: ClientRebirthManager): boolean
	return false
end

local function hasOwnedDragonWithName(itemName: string): boolean
	for _, shadow in collectionService:GetTagged(Tags.SHADOW_DRAGON) :: { any } do
		if shadow:GetAttribute(Attributes.USER_ID) ~= player.UserId then
			continue
		end
		if shadow:GetAttribute(Attributes.ITEM_NAME) == itemName then
			return true
		end
	end
	return false
end

function ClientRebirthManager.refresh(self: ClientRebirthManager)
	local nextCost = clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_NEXT_COST) :: number?

	if not nextCost then
		self.rewardsFrame.Visible = false
		self.requirementsFrame.Visible = false
		self.rebirthButton.Visible = false
		self.maxedOutFrame.Visible = true
		return
	end

	self.rewardsFrame.Visible = true
	self.requirementsFrame.Visible = true
	self.rebirthButton.Visible = true
	self.maxedOutFrame.Visible = false

	local coins = (clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS) :: number?) or 0
	local currentIncomeMult = (clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_CURRENT_INCOME_MULT) :: number?) or 1
	local currentLuckMult = (clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_CURRENT_LUCK_MULT) :: number?) or 1
	local nextIncomeMult = (clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_NEXT_INCOME_MULT) :: number?) or currentIncomeMult
	local nextLuckMult = (clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_NEXT_LUCK_MULT) :: number?) or currentLuckMult
	local requiredPetName = clientPlayerAttributesManager:get(PlayerAttributeKeys.REBIRTH_NEXT_REQUIRED_PET_NAME) :: string?

	self.incomeText.Text = string.format("Income: %gx > %gx", currentIncomeMult, nextIncomeMult)
	self.luckText.Text = string.format("Luck: %gx > %gx", currentLuckMult, nextLuckMult)

	local fillFrac = math.clamp(coins / nextCost, 0, 1)
	self.costFill.Size = UDim2.new(fillFrac, 0, self.costFill.Size.Y.Scale, self.costFill.Size.Y.Offset)
	self.costText.Text = string.format(
		"%s / %s",
		utils.formatLargeInteger(math.floor(coins)),
		utils.formatLargeInteger(math.floor(nextCost))
	)

	local hasPet = requiredPetName ~= nil and hasOwnedDragonWithName(requiredPetName :: string)
	self.petRequired.Text = if hasPet then requiredPetName else "?"

	local canAfford = coins >= nextCost and hasPet
	self.rebirthButton.Active = canAfford
	self.rebirthButton.AutoButtonColor = canAfford
	self.rebirthButton.BackgroundColor3 = if canAfford then self.rebirthButtonEnabledColor else Color3.fromRGB(128, 128, 128)
end

function ClientRebirthManager.beginRebirth(self: ClientRebirthManager)
	rebirthGui.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	self:refresh()
	self.timeSinceRefresh = 0

	self.refreshConnect = RunService.Heartbeat:Connect(function(deltaTime: number)
		self.timeSinceRefresh += deltaTime
		if self.timeSinceRefresh < REFRESH_INTERVAL_SEC then
			return
		end
		self.timeSinceRefresh = 0
		self:refresh()
	end)
end

function ClientRebirthManager.cleanupRebirth(self: ClientRebirthManager)
	rebirthGui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.refreshConnect then
		self.refreshConnect:Disconnect()
		self.refreshConnect = nil
	end
end

function ClientRebirthManager.toggleRebirth(self: ClientRebirthManager)
	if rebirthGui.Enabled then
		self:cleanupRebirth()
	else
		self:beginRebirth()
	end
end

function ClientRebirthManager.init(self: ClientRebirthManager)
	local dialogFit = rebirthGui:WaitForChild("DialogFit")
	self.dialogFit = dialogFit

	self.rewardsFrame = utils.findFirstDescendant(dialogFit, "RewardsFrame")
	self.requirementsFrame = utils.findFirstDescendant(dialogFit, "RequirementsFrame")
	self.maxedOutFrame = utils.findFirstDescendant(dialogFit, "MaxedOutFrame")

	self.incomeText = utils.findFirstDescendant(self.rewardsFrame, "IncomeText")
	self.luckText = utils.findFirstDescendant(self.rewardsFrame, "LuckText")

	self.costFill = utils.findFirstDescendant(self.requirementsFrame, "CostFillBar"):WaitForChild("Fill")
	self.costText = utils.findFirstDescendant(self.requirementsFrame, "CostText")
	self.petRequired = utils.findFirstDescendant(self.requirementsFrame, "PetRequiredText")

	self.rebirthButton = utils.findFirstDescendant(dialogFit, "RebirthButton")
	self.rebirthButtonEnabledColor = self.rebirthButton.BackgroundColor3
	self.rebirthButton.Activated:Connect(function()
		RemoteEvents.TryRebirth:FireServer()
		self:cleanupRebirth()
	end)

	local exitButton: any = utils.findFirstDescendant(dialogFit, "ExitButton")
	exitButton.Activated:Connect(function()
		self:cleanupRebirth()
	end)
end

function ClientRebirthManager.new(): ClientRebirthManager
	local self = setmetatable({} :: ClientRebirthManagerFields, ClientRebirthManager)

	self.refreshConnect = nil
	self.timeSinceRefresh = 0

	return self
end

local singleton = ClientRebirthManager.new()

return singleton
