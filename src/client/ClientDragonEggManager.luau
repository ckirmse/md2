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

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	instance: any, -- world egg Model; its shape only exists at runtime
	billboard: any?, -- CountdownBillboard clone
	runConnect: RBXScriptConnection?,
	hatchCompleteTimeChangedConnect: RBXScriptConnection?,
}

type ClientDragonEggManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientDragonEggManager = typeof(setmetatable({} :: ClientDragonEggManagerFields, ClientDragonEggManager))

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
	billboard.StudsOffset = Vector3.new(0, 4 + size.Y / 2, 0)
	billboard:SetAttribute(Attributes.ITEM_ID, itemId) -- for debugging

	local button = billboard:FindFirstChild("SpeedUpButton")
	if button then
		button.Visible = false
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

	if indicatorData.billboard then
		indicatorData.billboard:Destroy()
		indicatorData.billboard = nil
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
end

local singleton = ClientDragonEggManager.new()

return singleton
