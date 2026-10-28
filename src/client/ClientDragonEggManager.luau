--!strict

local ClientDragonEggManager = {}
ClientDragonEggManager.__index = ClientDragonEggManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the billboard template's shape only exists in Studio, so it is untyped here
local CountdownBillboard: any = UX:WaitForChild("CountdownBillboard")
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local HatchSkipMath = require("@game/ReplicatedStorage/Shared/HatchSkipMath")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = game:GetService("Players").LocalPlayer :: Player

local HATCH_PROMPT_NAME = "HatchEggProxPrompt"
local SKIP_BUTTON_NAME = "SpeedUpButton"
local SKIP_FRAME_NAME = "Frame"
local SKIP_TITLE_NAME = "ActivateNow"
local SKIP_COST_NAME = "Cost"
local SKIP_ICON_NAME = "ImageLabel"
local SKIP_CONFIRM_SEC = 3

type IndicatorData = {
	instance: any, -- world egg Model; its shape only exists at runtime
	billboard: any?, -- CountdownBillboard clone
	hatchPrompt: ProximityPrompt?,
	skipButton: any?,
	skipTitleLabel: any?,
	skipCostLabel: any?,
	skipConfirmCost: number?,
	skipConfirmUntil: number?,
	skipActivatedConnect: RBXScriptConnection?,
	runConnect: RBXScriptConnection?,
	hatchCompleteTimeChangedConnect: RBXScriptConnection?,
}

type ClientDragonEggManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	hatchHoldSec: number,
	skipSecPerDiamond: number,
}

export type ClientDragonEggManager = typeof(setmetatable({} :: ClientDragonEggManagerFields, ClientDragonEggManager))

-- lets other client managers resolve a dragon egg's world Instance by item id (e.g. to read
-- carry-related attributes off the specific egg a player is currently carrying)
function ClientDragonEggManager.getInstanceByItemId(self: ClientDragonEggManager, itemId: number): any?
	local indicatorData = self.indicatorMap[itemId]
	return indicatorData and indicatorData.instance
end

local function setLabelText(label: any, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function updateSkipButton(self: ClientDragonEggManager, indicatorData: IndicatorData, remainingSec: number)
	local button = indicatorData.skipButton
	if not button then
		return
	end

	local isSlotted = indicatorData.instance:GetAttribute(Attributes.EGG_SLOT_INDEX) ~= nil
	button.Visible = isSlotted
	if not isSlotted then
		return
	end

	local confirmUntil = indicatorData.skipConfirmUntil
	if confirmUntil and workspace:GetServerTimeNow() >= confirmUntil then
		indicatorData.skipConfirmCost = nil
		indicatorData.skipConfirmUntil = nil
	end

	local confirmCost = indicatorData.skipConfirmCost
	setLabelText(indicatorData.skipTitleLabel, if confirmCost then "Confirm?" else "Skip")
	setLabelText(indicatorData.skipCostLabel, tostring(confirmCost or HatchSkipMath.getCost(remainingSec, self.skipSecPerDiamond)))
end

function ClientDragonEggManager.activateSkip(self: ClientDragonEggManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	local completeTime = indicatorData and indicatorData.instance:GetAttribute(Attributes.HATCH_COMPLETE_TIME)
	if not indicatorData or not completeTime then
		return
	end

	local confirmCost = indicatorData.skipConfirmCost
	if confirmCost then
		indicatorData.skipConfirmCost = nil
		indicatorData.skipConfirmUntil = nil
		RemoteEvents.TrySkipHatch:FireServer(itemId, confirmCost)
		return
	end

	local remainingSec = math.max(0, completeTime - workspace:GetServerTimeNow())
	indicatorData.skipConfirmCost = HatchSkipMath.getCost(remainingSec, self.skipSecPerDiamond)
	indicatorData.skipConfirmUntil = workspace:GetServerTimeNow() + SKIP_CONFIRM_SEC
	updateSkipButton(self, indicatorData, remainingSec)
end

function ClientDragonEggManager.updateBillboardByItemId(self: ClientDragonEggManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local billboard = indicatorData.billboard
	if not billboard then
		return
	end

	local inst = indicatorData.instance

	-- the character rig's children only exist at runtime, so they are untyped here
	local distance = (((player.Character :: any).HumanoidRootPart.Position :: Vector3) - inst:GetPivot().Position).Magnitude
	billboard.Enabled = distance <= Constants.COUNTDOWN_DISTANCE

	local completeTime = inst:GetAttribute(Attributes.HATCH_COMPLETE_TIME)
	if not completeTime then
		return
	end

	local remainingSec = math.ceil(math.max(0, completeTime - workspace:GetServerTimeNow()))
	updateSkipButton(self, indicatorData, remainingSec)

	local textLabel = billboard:FindFirstChild("TextLabel")
	local s = string.format("Hatches in %ds", remainingSec)
	if s ~= textLabel.Text then
		textLabel.Text = s
	end
end

function ClientDragonEggManager.beginHatchCountdown(self: ClientDragonEggManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	-- checked live, not cached: ownership transfers from unowned (at nest spawn) to the picking-up
	-- player well after this item was first tagged, with no re-tag to hook a fresh snapshot from
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		return
	end

	local billboard = CountdownBillboard:Clone()
	billboard.MaxDistance = 500
	billboard.Adornee = inst
	billboard.Enabled = true
	local _, size = inst:GetBoundingBox()
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.StudsOffset = Vector3.new(0, 1 + size.Y / 2, 0)
	billboard:SetAttribute(Attributes.ITEM_ID, itemId) -- for debugging

	local button = billboard:FindFirstChild(SKIP_BUTTON_NAME)
	if button then
		button.Visible = false
		indicatorData.skipButton = button
		local skipFrame = button:FindFirstChild(SKIP_FRAME_NAME)
		indicatorData.skipTitleLabel = skipFrame and skipFrame:FindFirstChild(SKIP_TITLE_NAME)
		indicatorData.skipCostLabel = skipFrame and skipFrame:FindFirstChild(SKIP_COST_NAME)
		local skipIcon = skipFrame and skipFrame:FindFirstChild(SKIP_ICON_NAME)
		local diamondImage = if skipIcon then skipIcon:GetAttribute(Attributes.DIAMOND_IMAGE) else nil
		if skipIcon and typeof(diamondImage) == "string" then
			skipIcon.Image = diamondImage
		end
		billboard.Active = true
		indicatorData.skipActivatedConnect = button.Activated:Connect(function()
			self:activateSkip(itemId)
		end)
	end

	indicatorData.billboard = billboard

	self:updateBillboardByItemId(itemId)

	billboard.Parent = player:WaitForChild("PlayerGui")

	indicatorData.runConnect = runService.PostSimulation:Connect(
		function()
			self:updateBillboardByItemId(itemId)
		end
	)
end

function ClientDragonEggManager.cleanupHatchCountdown(self: ClientDragonEggManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.runConnect then
		indicatorData.runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	if indicatorData.skipActivatedConnect then
		indicatorData.skipActivatedConnect:Disconnect()
		indicatorData.skipActivatedConnect = nil
	end
	indicatorData.skipButton = nil
	indicatorData.skipTitleLabel = nil
	indicatorData.skipCostLabel = nil
	indicatorData.skipConfirmCost = nil
	indicatorData.skipConfirmUntil = nil

	if indicatorData.billboard then
		indicatorData.billboard:Destroy()
		indicatorData.billboard = nil
	end
end

function ClientDragonEggManager.setHatchConfig(self: ClientDragonEggManager, hatchConfig: any)
	if typeof(hatchConfig) ~= "table" then
		return
	end

	if typeof(hatchConfig.holdSec) == "number" then
		self.hatchHoldSec = hatchConfig.holdSec
		for _, indicatorData in self.indicatorMap do
			if indicatorData.hatchPrompt then
				indicatorData.hatchPrompt.HoldDuration = self.hatchHoldSec
			end
		end
	end

	if typeof(hatchConfig.skipSecPerDiamond) == "number" then
		self.skipSecPerDiamond = hatchConfig.skipSecPerDiamond
	end
end

function ClientDragonEggManager.createHatchPrompt(self: ClientDragonEggManager, inst: any)
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		return
	end

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local part = utils.getMainPart(inst)
	if not part then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = HATCH_PROMPT_NAME
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt.ActionText = "Hatch Egg"
	prompt.HoldDuration = self.hatchHoldSec
	prompt.MaxActivationDistance = Constants.HATCH_EGG_DISTANCE
	prompt.Parent = part

	prompt.Triggered:Connect(function()
		RemoteEvents.TryHatchEgg:FireServer(itemId)
	end)

	indicatorData.hatchPrompt = prompt
end

function ClientDragonEggManager.removeHatchPrompt(self: ClientDragonEggManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.hatchPrompt then
		indicatorData.hatchPrompt:Destroy()
		indicatorData.hatchPrompt = nil
	end
end

function ClientDragonEggManager.notifyNewInstance(self: ClientDragonEggManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	if self.indicatorMap[itemId] then
		return
	end

	self.indicatorMap[itemId] = {
		instance = inst,
	}

	local indicatorData = self.indicatorMap[itemId]

	if inst:GetAttribute(Attributes.HATCH_COMPLETE_TIME) then
		self:beginHatchCountdown(itemId)
	end

	indicatorData.hatchCompleteTimeChangedConnect = inst:GetAttributeChangedSignal(Attributes.HATCH_COMPLETE_TIME):Connect(
		function()
			if inst:GetAttribute(Attributes.HATCH_COMPLETE_TIME) then
				self:beginHatchCountdown(itemId)
			else
				self:cleanupHatchCountdown(itemId)
			end
		end
	)
end

function ClientDragonEggManager.notifyRemoveInstance(self: ClientDragonEggManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	self:cleanupHatchCountdown(itemId)

	if indicatorData.hatchCompleteTimeChangedConnect then
		indicatorData.hatchCompleteTimeChangedConnect:Disconnect()
	end

	self.indicatorMap[itemId] = nil
end

function ClientDragonEggManager.new(): ClientDragonEggManager
	local self: ClientDragonEggManager = setmetatable({
		indicatorMap = {},
		hatchHoldSec = 1,
		skipSecPerDiamond = HatchSkipMath.DEFAULT_SEC_PER_DIAMOND,
	} :: ClientDragonEggManagerFields, ClientDragonEggManager)

	return self
end

function ClientDragonEggManager.init(self: ClientDragonEggManager)
	collectionService:GetInstanceAddedSignal(Tags.DRAGON_EGG):Connect(function(inst)
		self:notifyNewInstance(inst)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.DRAGON_EGG):Connect(function(inst)
		self:notifyRemoveInstance(inst)
	end)

	for _, inst in collectionService:GetTagged(Tags.DRAGON_EGG) do
		self:notifyNewInstance(inst)
	end

	collectionService:GetInstanceAddedSignal(Tags.HATCHABLE_EGG):Connect(function(inst)
		self:createHatchPrompt(inst)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.HATCHABLE_EGG):Connect(function(inst)
		self:removeHatchPrompt(inst)
	end)

	for _, inst in collectionService:GetTagged(Tags.HATCHABLE_EGG) do
		self:createHatchPrompt(inst)
	end
end

local singleton = ClientDragonEggManager.new()

return singleton
