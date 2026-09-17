--!strict

local ClientNestManager = {}
ClientNestManager.__index = ClientNestManager

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
local utils = require("@game/ReplicatedStorage/Shared/utils")

type ClientNestManagerFields = {
	indicatorMap: { [number]: any },
}

export type ClientNestManager = typeof(setmetatable({} :: ClientNestManagerFields, ClientNestManager))

-- only pickable up while mounted and actively controlling the dragon, and only while the nest
-- actually has an egg (no respawn timer running)
function ClientNestManager.configurePrompt(self: ClientNestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local hasEgg = indicatorData.instance:GetAttribute(Attributes.NEST_RESPAWN_COMPLETE_TIME) == nil
	local isRidingAndControlling = clientRideController:isRiding() and clientRideController:isRidingAndControlling()

	indicatorData.prompt.Enabled = hasEgg and isRidingAndControlling
end

function ClientNestManager.notifyNewInstance(self: ClientNestManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
	if self.indicatorMap[objectId] then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = "Pick Up Egg"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = Constants.PICKUP_EGG_DISTANCE
	prompt.Triggered:Connect(function()
		RemoteEvents.TryPickupEgg:FireServer(objectId)
	end)

	local eggSpawn = utils.findFirstDescendant(inst, "EggSpawn")
	prompt.Parent = eggSpawn or inst

	local indicatorData = {
		instance = inst,
		prompt = prompt,
	}
	self.indicatorMap[objectId] = indicatorData

	indicatorData.respawnChangedConnect = inst:GetAttributeChangedSignal(Attributes.NEST_RESPAWN_COMPLETE_TIME):Connect(
		function()
			self:configurePrompt(objectId)
		end
	)

	self:configurePrompt(objectId)
end

function ClientNestManager.notifyRemoveInstance(self: ClientNestManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	if indicatorData.respawnChangedConnect then
		indicatorData.respawnChangedConnect:Disconnect()
	end
	indicatorData.prompt:Destroy()

	self.indicatorMap[objectId] = nil
end

function ClientNestManager.new(): ClientNestManager
	local self: ClientNestManager = setmetatable({
		indicatorMap = {},
	} :: ClientNestManagerFields, ClientNestManager)

	return self
end

function ClientNestManager.initClass(deps: any)
	clientRideController = deps.clientRideController
end

function ClientNestManager.init(self: ClientNestManager)
	collectionService:GetInstanceAddedSignal(Tags.NEST):Connect(function(inst)
		self:notifyNewInstance(inst)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.NEST):Connect(function(inst)
		self:notifyRemoveInstance(inst)
	end)

	for _, inst in collectionService:GetTagged(Tags.NEST) do
		self:notifyNewInstance(inst)
	end

	-- riding/controlling state can change without any of the nest's own attributes changing
	runService.Heartbeat:Connect(function()
		for objectId in self.indicatorMap do
			self:configurePrompt(objectId)
		end
	end)
end

local singleton = ClientNestManager.new()

return singleton
