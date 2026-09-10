--!strict

local ClientStablesManager = {}
ClientStablesManager.__index = ClientStablesManager

local collectionService = game:GetService("CollectionService")
local playersService = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Level = workspace:WaitForChild("Level")

local player = playersService.LocalPlayer :: Player

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")
local teleporters = require("./Teleporters")

local STABLE_SLOT_COUNT = 6
local PROMPT_NAME = "StableSlotPrompt"
local PROMPT_DISTANCE = 12
local RESOLVE_ATTEMPTS = 40
local RESOLVE_INTERVAL = 0.5

type SlotData = {
	slotModel: Instance,
	hologram: Instance?,
	prompt: ProximityPrompt,
	promptTriggeredConnect: RBXScriptConnection,
}

type ClientStablesManagerFields = {
	slots: { [number]: SlotData },
	-- slotIndex -> the occupying dragon's shadow part, from the EQUIPPED_DRAGON tag
	occupancy: { [number]: Instance },
}

export type ClientStablesManager = typeof(setmetatable({} :: ClientStablesManagerFields, ClientStablesManager))

function ClientStablesManager.setHologramVisible(self: ClientStablesManager, hologram: Instance?, visible: boolean)
	if hologram and hologram:IsA("BasePart") then
		hologram.LocalTransparencyModifier = if visible then 0 else 1
	end
end

function ClientStablesManager.refreshSlot(self: ClientStablesManager, slotIndex: number)
	local slot = self.slots[slotIndex]
	if not slot then
		return
	end

	local occupant: Instance? = self.occupancy[slotIndex]

	self:setHologramVisible(slot.hologram, not occupant)

	local prompt = slot.prompt
	if occupant then
		prompt.Enabled = true
		prompt.ActionText = "Return to backpack"
		prompt.ObjectText = (occupant:GetAttribute(Attributes.DISPLAY_NAME) :: string?) or "Dragon"
	elseif clientRideController:isRiding() then
		prompt.Enabled = true
		prompt.ActionText = "Place in stable"
		prompt.ObjectText = ""
	else
		prompt.Enabled = false
	end
end

function ClientStablesManager.refreshAllSlots(self: ClientStablesManager)
	for slotIndex = 1, STABLE_SLOT_COUNT do
		self:refreshSlot(slotIndex)
	end
end

function ClientStablesManager.onSlotTriggered(self: ClientStablesManager, slotIndex: number)
	if self.occupancy[slotIndex] then
		RemoteEvents.TryUnequipDragon:FireServer(slotIndex)
		return
	end

	local ridingObj = clientRideController:getRidingObj()
	if not ridingObj then
		return
	end

	local itemId = ridingObj:GetAttribute(Attributes.ITEM_ID)
	if not itemId then
		return
	end

	RemoteEvents.TryEquipDragon:FireServer(itemId, slotIndex)
end

function ClientStablesManager.onEquippedDragonAdded(self: ClientStablesManager, shadow: Instance)
	if shadow:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		return
	end

	local slotIndex = shadow:GetAttribute(Attributes.DRAGON_SLOT_INDEX)
	if typeof(slotIndex) ~= "number" then
		return
	end

	self.occupancy[slotIndex] = shadow
	self:refreshSlot(slotIndex)
end

function ClientStablesManager.onEquippedDragonRemoved(self: ClientStablesManager, shadow: Instance)
	for slotIndex, occupantShadow in self.occupancy do
		if occupantShadow == shadow then
			self.occupancy[slotIndex] = nil
			self:refreshSlot(slotIndex)
			return
		end
	end
end

function ClientStablesManager.setupSlot(self: ClientStablesManager, slotIndex: number, slotModel: Instance)
	local anchor = slotModel:FindFirstChild("Anchor")
	if not anchor then
		warn("stable slot missing Anchor part", slotIndex)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.HoldDuration = 0
	prompt.Enabled = false

	local promptTriggeredConnect = prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end
		self:onSlotTriggered(slotIndex)
	end)

	prompt.Parent = anchor

	self.slots[slotIndex] = {
		slotModel = slotModel,
		hologram = slotModel:FindFirstChild("Hologram"),
		prompt = prompt,
		promptTriggeredConnect = promptTriggeredConnect,
	}
end

function ClientStablesManager.resolveSlots(self: ClientStablesManager)
	local plotIndex: number?
	for _ = 1, RESOLVE_ATTEMPTS do
		plotIndex = teleporters:getPlotIndex()
		if plotIndex then
			break
		end
		task.wait(RESOLVE_INTERVAL)
	end

	if not plotIndex then
		warn("ClientStablesManager: no plot index, stables disabled")
		return
	end

	for slotIndex = 1, STABLE_SLOT_COUNT do
		local slotModel: Instance?
		for _ = 1, RESOLVE_ATTEMPTS do
			slotModel = utils.findFirstDescendantWithNameAndAttribute(
				Level,
				"StableSlot" .. slotIndex,
				Attributes.INDEX,
				plotIndex
			)
			if slotModel then
				break
			end
			task.wait(RESOLVE_INTERVAL)
		end

		if slotModel then
			self:setupSlot(slotIndex, slotModel :: Instance)
		else
			warn("ClientStablesManager: could not find StableSlot" .. slotIndex)
		end
	end

	self:refreshAllSlots()
end

function ClientStablesManager.init(self: ClientStablesManager)
	collectionService:GetInstanceAddedSignal(Tags.EQUIPPED_DRAGON):Connect(function(inst)
		self:onEquippedDragonAdded(inst)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.EQUIPPED_DRAGON):Connect(function(inst)
		self:onEquippedDragonRemoved(inst)
	end)
	for _, inst in collectionService:GetTagged(Tags.EQUIPPED_DRAGON) do
		self:onEquippedDragonAdded(inst)
	end

	clientRideController:getEvent():Connect(function()
		self:refreshAllSlots()
	end)

	task.spawn(function()
		self:resolveSlots()
	end)
end

function ClientStablesManager.new(): ClientStablesManager
	local self = setmetatable({}, ClientStablesManager)
	self.slots = {}
	self.occupancy = {}
	return self
end

local singleton = ClientStablesManager.new()

return singleton
