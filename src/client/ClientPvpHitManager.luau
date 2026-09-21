--!strict

local ClientPvpHitManager = {}
ClientPvpHitManager.__index = ClientPvpHitManager

local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

local player = players.LocalPlayer :: Player

local Types = require("./Types")
local clientRideController: Types.ClientRideController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local SWING_KEY = Enum.KeyCode.F

type ClientPvpHitManagerFields = {
	indicatorMap: { [Instance]: any },
	swingIndicatorBillboard: BillboardGui,
}

export type ClientPvpHitManager = typeof(setmetatable({} :: ClientPvpHitManagerFields, ClientPvpHitManager))

function ClientPvpHitManager.configurePrompt(self: ClientPvpHitManager, egg: Instance)
	local indicatorData = self.indicatorMap[egg]
	if not indicatorData then
		return
	end

	local isFree = egg:GetAttribute(Attributes.FREE_FOR_PICKUP) == true
	local isRidingAndControlling = clientRideController:isRiding() and clientRideController:isRidingAndControlling()
	local isCarrying = clientRideController:isCarryingEgg()

	indicatorData.prompt.Enabled = isFree and isRidingAndControlling and not isCarrying
end

function ClientPvpHitManager.notifyNewInstance(self: ClientPvpHitManager, egg: Instance)
	if self.indicatorMap[egg] then
		return
	end

	local itemId = egg:GetAttribute(Attributes.ITEM_ID)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Pick Up Egg"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Constants.PICKUP_EGG_DISTANCE
	prompt.Triggered:Connect(function()
		RemoteEvents.TryPickupFreeEgg:FireServer(itemId)
	end)
	prompt.Parent = egg

	local indicatorData = {
		prompt = prompt,
	}
	self.indicatorMap[egg] = indicatorData

	indicatorData.freeChangedConnect = egg:GetAttributeChangedSignal(Attributes.FREE_FOR_PICKUP):Connect(function()
		self:configurePrompt(egg)
	end)

	self:configurePrompt(egg)
end

function ClientPvpHitManager.findNearestSwingTarget(self: ClientPvpHitManager): Instance?
	local ridingObj: any = clientRideController:getRidingObj()
	if not ridingObj then
		return nil
	end

	local ridingPosition = ridingObj:GetPivot().Position

	local nearestTarget: Instance? = nil
	local nearestDistance = Constants.PVP_HIT_INDICATOR_RANGE
	for _, shadow: any in collectionService:GetTagged(Tags.SHADOW_DRAGON) do
		if shadow == ridingObj then
			continue
		end
		if not shadow:GetAttribute(Attributes.IS_CARRYING) then
			continue
		end

		local distance = (shadow:GetPivot().Position - ridingPosition).Magnitude
		if distance <= nearestDistance then
			nearestTarget = shadow
			nearestDistance = distance
		end
	end

	return nearestTarget
end

function ClientPvpHitManager.updateSwingIndicator(self: ClientPvpHitManager)
	local isRidingAndControlling = clientRideController:isRiding() and clientRideController:isRidingAndControlling()
	local target = if isRidingAndControlling then self:findNearestSwingTarget() else nil

	self.swingIndicatorBillboard.Adornee = target
	self.swingIndicatorBillboard.Enabled = target ~= nil
end

function ClientPvpHitManager.notifyRemoveInstance(self: ClientPvpHitManager, egg: Instance)
	local indicatorData = self.indicatorMap[egg]
	if not indicatorData then
		return
	end

	if indicatorData.freeChangedConnect then
		indicatorData.freeChangedConnect:Disconnect()
	end
	indicatorData.prompt:Destroy()

	self.indicatorMap[egg] = nil
end

local function createSwingIndicatorBillboard(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PvpHitIndicator"
	billboard.Size = UDim2.new(6, 0, 1.5, 0)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
	textLabel.TextStrokeTransparency = 0
	textLabel.Text = "Press F to Hit"
	textLabel.Parent = billboard

	billboard.Parent = player:WaitForChild("PlayerGui")

	return billboard
end

function ClientPvpHitManager.new(): ClientPvpHitManager
	local self: ClientPvpHitManager = setmetatable({
		indicatorMap = {},
		swingIndicatorBillboard = createSwingIndicatorBillboard(),
	} :: ClientPvpHitManagerFields, ClientPvpHitManager)

	return self
end

function ClientPvpHitManager.initClass(deps: any)
	clientRideController = deps.clientRideController
end

function ClientPvpHitManager.init(self: ClientPvpHitManager)
	collectionService:GetInstanceAddedSignal(Tags.DRAGON_EGG):Connect(function(egg)
		self:notifyNewInstance(egg)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.DRAGON_EGG):Connect(function(egg)
		self:notifyRemoveInstance(egg)
	end)

	for _, egg in collectionService:GetTagged(Tags.DRAGON_EGG) do
		self:notifyNewInstance(egg)
	end

	-- riding/controlling/carrying state can change without the egg's own attributes changing
	runService.Heartbeat:Connect(function()
		for egg in self.indicatorMap do
			self:configurePrompt(egg)
		end

		self:updateSwingIndicator()
	end)

	userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= SWING_KEY then
			return
		end
		if not (clientRideController:isRiding() and clientRideController:isRidingAndControlling()) then
			return
		end

		RemoteEvents.TryHitCarrierEgg:FireServer()
	end)
end

local singleton = ClientPvpHitManager.new()

return singleton
