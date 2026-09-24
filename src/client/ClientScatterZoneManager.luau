--!strict

local ClientScatterZoneManager = {}
ClientScatterZoneManager.__index = ClientScatterZoneManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local Types = require("./Types")
local clientRideController: Types.ClientRideController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

type ClientScatterZoneManagerFields = {
	indicatorMap: { [Instance]: any },
}

export type ClientScatterZoneManager = typeof(setmetatable({} :: ClientScatterZoneManagerFields, ClientScatterZoneManager))

function ClientScatterZoneManager.configurePrompt(self: ClientScatterZoneManager, egg: Instance)
	local indicatorData = self.indicatorMap[egg]
	if not indicatorData then
		return
	end

	-- scatter-zone-sourced eggs are always eligible; any other egg only once it's been dropped
	-- from a basket mid-carry (FREE_FOR_PICKUP) -- a fresh, untaken nest egg is neither
	local isEligibleSource = egg:GetAttribute(Attributes.SOURCE_SCATTER_ZONE_ID) ~= nil
		or egg:GetAttribute(Attributes.FREE_FOR_PICKUP) == true

	-- ownership stays unowned for the whole carry now, so CARRY_EXPIRES_TIME (only set while
	-- actively carried) is what actually distinguishes "free to grab" from "being carried"
	local isStillFree = egg:GetAttribute(Attributes.USER_ID) == Constants.UNOWNED_USER_ID
		and egg:GetAttribute(Attributes.CARRY_EXPIRES_TIME) == nil

	local isRidingAndControlling = clientRideController:isRiding() and clientRideController:isRidingAndControlling()
	local isCarrying = clientRideController:isCarryingEgg()

	indicatorData.prompt.Enabled = isEligibleSource and isStillFree and isRidingAndControlling and not isCarrying
end

function ClientScatterZoneManager.notifyNewInstance(self: ClientScatterZoneManager, egg: Instance)
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
		RemoteEvents.TryPickupScatteredEgg:FireServer(itemId)
	end)
	prompt.Parent = egg

	local indicatorData = {
		prompt = prompt,
	}
	self.indicatorMap[egg] = indicatorData

	indicatorData.userIdChangedConnect = egg:GetAttributeChangedSignal(Attributes.USER_ID):Connect(function()
		self:configurePrompt(egg)
	end)

	self:configurePrompt(egg)
end

function ClientScatterZoneManager.notifyRemoveInstance(self: ClientScatterZoneManager, egg: Instance)
	local indicatorData = self.indicatorMap[egg]
	if not indicatorData then
		return
	end

	if indicatorData.userIdChangedConnect then
		indicatorData.userIdChangedConnect:Disconnect()
	end
	indicatorData.prompt:Destroy()

	self.indicatorMap[egg] = nil
end

function ClientScatterZoneManager.new(): ClientScatterZoneManager
	local self: ClientScatterZoneManager = setmetatable({
		indicatorMap = {},
	} :: ClientScatterZoneManagerFields, ClientScatterZoneManager)

	return self
end

function ClientScatterZoneManager.initClass(deps: any)
	clientRideController = deps.clientRideController
end

function ClientScatterZoneManager.init(self: ClientScatterZoneManager)
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
	end)
end

local singleton = ClientScatterZoneManager.new()

return singleton
