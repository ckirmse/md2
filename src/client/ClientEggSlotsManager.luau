--!strict

local ClientEggSlotsManager = {}
ClientEggSlotsManager.__index = ClientEggSlotsManager

local collectionService = game:GetService("CollectionService")
local playersService = game:GetService("Players")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Level = workspace:WaitForChild("Level")

local player = playersService.LocalPlayer :: Player

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local clientRideController = require("./ClientRideController")
local teleporters = require("./Teleporters")

local PROMPT_NAME = "EggSlotPrompt"
local PROMPT_DISTANCE = 12
local RESOLVE_ATTEMPTS = 40
local RESOLVE_INTERVAL = 0.5
local BOB_AMPLITUDE = 0.35
local BOB_PERIOD_SEC = 3

type SlotData = {
	slotModel: Instance,
	hologram: Instance?,
	prompt: ProximityPrompt,
	promptTriggeredConnect: RBXScriptConnection,
}

type BobData = {
	baseCFrame: CFrame,
	lastCFrame: CFrame,
	phase: number,
}

type ClientEggSlotsManagerFields = {
	plotIndex: number?,
	slots: { [number]: SlotData },
	pendingSlotIndexes: { [number]: boolean }, -- slots whose model is still being waited for
	-- slotIndex -> the occupying egg, from the SLOTTED_EGG tag
	occupancy: { [number]: Instance },
	carriedEggConnect: RBXScriptConnection?,
	bobbingEggs: { [Instance]: BobData },
}

export type ClientEggSlotsManager = typeof(setmetatable({} :: ClientEggSlotsManagerFields, ClientEggSlotsManager))

function ClientEggSlotsManager.setHologramVisible(self: ClientEggSlotsManager, hologram: Instance?, visible: boolean)
	if hologram and hologram:IsA("BasePart") then
		hologram.LocalTransparencyModifier = if visible then 0 else 1
	end
end

-- the egg the player could put in a slot right now: the one in the ridden dragon's basket, else the one held in hand
function ClientEggSlotsManager.getPlaceableEggItemId(self: ClientEggSlotsManager): number?
	local ridingObj = clientRideController:getRidingObj()
	if ridingObj then
		local carriedItemId = ridingObj:GetAttribute(Attributes.CARRIED_EGG_ITEM_ID)
		if typeof(carriedItemId) == "number" then
			return carriedItemId
		end
	end

	local tool = utils.getHoldingToolWithHandle(player)
	if tool and tool:GetAttribute(Attributes.ITEM_TYPE) == "dragonEgg" then
		local heldItemId = tool:GetAttribute(Attributes.ITEM_ID)
		if typeof(heldItemId) == "number" then
			return heldItemId
		end
	end

	return nil
end

function ClientEggSlotsManager.refreshSlot(self: ClientEggSlotsManager, slotIndex: number)
	local slot = self.slots[slotIndex]
	if not slot then
		return
	end

	local occupant: Instance? = self.occupancy[slotIndex]

	self:setHologramVisible(slot.hologram, not occupant)

	local prompt = slot.prompt
	if occupant then
		-- a ready egg is hatched with its own hold prompt instead
		prompt.Enabled = not collectionService:HasTag(occupant, Tags.HATCHABLE_EGG)
		prompt.ActionText = "Return to backpack"
		prompt.ObjectText = (occupant:GetAttribute(Attributes.DISPLAY_NAME) :: string?) or "Egg"
	elseif self:getPlaceableEggItemId() then
		prompt.Enabled = true
		prompt.ActionText = "Place egg"
		prompt.ObjectText = ""
	else
		prompt.Enabled = false
	end
end

function ClientEggSlotsManager.refreshAllSlots(self: ClientEggSlotsManager)
	for slotIndex = 1, clientPlayerAttributesManager:getEggSlotCount() do
		self:refreshSlot(slotIndex)
	end
end

function ClientEggSlotsManager.onSlotTriggered(self: ClientEggSlotsManager, slotIndex: number)
	if self.occupancy[slotIndex] then
		RemoteEvents.TryRemoveEgg:FireServer(slotIndex)
		return
	end

	local itemId = self:getPlaceableEggItemId()
	if not itemId then
		return
	end

	RemoteEvents.TryPlaceEgg:FireServer(itemId, slotIndex)
end

function ClientEggSlotsManager.onSlottedEggAdded(self: ClientEggSlotsManager, egg: Instance)
	local eggPivot = (egg :: any):GetPivot()
	self.bobbingEggs[egg] = { baseCFrame = eggPivot, lastCFrame = eggPivot, phase = math.random() * BOB_PERIOD_SEC }

	if egg:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		return
	end

	local slotIndex = egg:GetAttribute(Attributes.EGG_SLOT_INDEX)
	if typeof(slotIndex) ~= "number" then
		return
	end

	self.occupancy[slotIndex] = egg
	self:refreshSlot(slotIndex)
end

function ClientEggSlotsManager.onSlottedEggRemoved(self: ClientEggSlotsManager, egg: Instance)
	self.bobbingEggs[egg] = nil

	for slotIndex, occupantEgg in self.occupancy do
		if occupantEgg == egg then
			self.occupancy[slotIndex] = nil
			self:refreshSlot(slotIndex)
			return
		end
	end
end

function ClientEggSlotsManager.setupSlot(self: ClientEggSlotsManager, slotIndex: number, slotModel: Instance)
	local anchor = slotModel:FindFirstChild("Anchor")
	if not anchor then
		warn("egg slot missing Anchor part", slotIndex)
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

function ClientEggSlotsManager.findSlotModel(self: ClientEggSlotsManager, plotIndex: number, slotIndex: number): Instance?
	for _ = 1, RESOLVE_ATTEMPTS do
		local slotModel = utils.findFirstDescendantWithNameAndAttribute(
			Level,
			"EggSlot" .. slotIndex,
			Attributes.INDEX,
			plotIndex
		)
		if slotModel then
			return slotModel
		end
		task.wait(RESOLVE_INTERVAL)
	end

	return nil
end

-- sets up every slot the player currently owns that is not set up yet; each one waits for its own model on its own
-- thread, so a model that is slow to appear never delays the others
function ClientEggSlotsManager.setupOwnedSlots(self: ClientEggSlotsManager)
	local plotIndex = self.plotIndex
	if not plotIndex then
		return
	end

	local slotCount = clientPlayerAttributesManager:getEggSlotCount()

	-- slots above a lowered count (a data reset) are gone from the world, so their prompts go too
	for slotIndex, slot in self.slots do
		if slotIndex > slotCount then
			slot.promptTriggeredConnect:Disconnect()
			slot.prompt:Destroy()
			self.slots[slotIndex] = nil
		end
	end

	for slotIndex = 1, slotCount do
		if self.slots[slotIndex] or self.pendingSlotIndexes[slotIndex] then
			continue
		end
		self.pendingSlotIndexes[slotIndex] = true

		task.spawn(function()
			local slotModel = self:findSlotModel(plotIndex, slotIndex)
			self.pendingSlotIndexes[slotIndex] = nil

			if slotIndex > clientPlayerAttributesManager:getEggSlotCount() then
				return
			end

			if not slotModel then
				warn("ClientEggSlotsManager: could not find EggSlot" .. slotIndex)
				return
			end

			self:setupSlot(slotIndex, slotModel)
			self:refreshSlot(slotIndex)
		end)
	end
end

function ClientEggSlotsManager.resolveSlots(self: ClientEggSlotsManager)
	for _ = 1, RESOLVE_ATTEMPTS do
		self.plotIndex = teleporters:getPlotIndex()
		if self.plotIndex then
			break
		end
		task.wait(RESOLVE_INTERVAL)
	end

	if not self.plotIndex then
		warn("ClientEggSlotsManager: no plot index, egg slots disabled")
		return
	end

	self:setupOwnedSlots()
end

function ClientEggSlotsManager.notifySlotCountChanged(self: ClientEggSlotsManager)
	self:setupOwnedSlots()
end

-- picking up or dropping an egg changes what the slots can offer without any ride event
function ClientEggSlotsManager.watchRiddenDragonCarriedEgg(self: ClientEggSlotsManager)
	if self.carriedEggConnect then
		self.carriedEggConnect:Disconnect()
		self.carriedEggConnect = nil
	end

	local ridingObj = clientRideController:getRidingObj()
	if not ridingObj then
		return
	end

	self.carriedEggConnect = ridingObj:GetAttributeChangedSignal(Attributes.CARRIED_EGG_ITEM_ID):Connect(function()
		self:refreshAllSlots()
	end)
end

-- the server pivots a slotted egg once, so the bob is purely visual and runs here; a pivot that is not the one applied
-- last frame is the server moving the egg, which becomes the new resting point
function ClientEggSlotsManager.updateBobbing(self: ClientEggSlotsManager)
	local now = os.clock()
	for egg, bob in self.bobbingEggs do
		local pivotOwner = egg :: any
		local currentCFrame: CFrame = pivotOwner:GetPivot()
		if (currentCFrame.Position - bob.lastCFrame.Position).Magnitude > 0.01 then
			bob.baseCFrame = currentCFrame
		end

		local offsetY = math.sin(2 * math.pi * (now + bob.phase) / BOB_PERIOD_SEC) * BOB_AMPLITUDE
		local bobbedCFrame = bob.baseCFrame + Vector3.new(0, offsetY, 0)
		pivotOwner:PivotTo(bobbedCFrame)
		bob.lastCFrame = bobbedCFrame
	end
end

function ClientEggSlotsManager.init(self: ClientEggSlotsManager)
	runService.Heartbeat:Connect(function()
		self:updateBobbing()
	end)

	collectionService:GetInstanceAddedSignal(Tags.SLOTTED_EGG):Connect(function(inst)
		self:onSlottedEggAdded(inst)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.SLOTTED_EGG):Connect(function(inst)
		self:onSlottedEggRemoved(inst)
	end)
	for _, inst in collectionService:GetTagged(Tags.SLOTTED_EGG) do
		self:onSlottedEggAdded(inst)
	end

	-- a slotted egg turning ready (or not) switches its slot prompt on or off
	collectionService:GetInstanceAddedSignal(Tags.HATCHABLE_EGG):Connect(function()
		self:refreshAllSlots()
	end)
	collectionService:GetInstanceRemovedSignal(Tags.HATCHABLE_EGG):Connect(function()
		self:refreshAllSlots()
	end)

	local function watchCharacter(character: Model)
		character.ChildAdded:Connect(function()
			self:refreshAllSlots()
		end)
		character.ChildRemoved:Connect(function()
			self:refreshAllSlots()
		end)
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	clientRideController:getEvent():Connect(function()
		self:watchRiddenDragonCarriedEgg()
		self:refreshAllSlots()
	end)
	self:watchRiddenDragonCarriedEgg()

	task.spawn(function()
		self:resolveSlots()
	end)
end

function ClientEggSlotsManager.new(): ClientEggSlotsManager
	local self = setmetatable({}, ClientEggSlotsManager)
	self.plotIndex = nil
	self.slots = {}
	self.pendingSlotIndexes = {}
	self.occupancy = {}
	self.carriedEggConnect = nil
	self.bobbingEggs = {}
	return self
end

local singleton = ClientEggSlotsManager.new()

return singleton
