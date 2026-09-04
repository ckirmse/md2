--!strict

local ClientVanityLockedManager = {}
ClientVanityLockedManager.__index = ClientVanityLockedManager

local collectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local PROMPT_NAME = "VanityLockedProxPrompt"

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("VanityGnomeTeaser")

type IndicatorData = {
	instance: any, -- world gnome instance; its shape only exists at runtime
	prompt: ProximityPrompt?,
}

type ClientVanityLockedManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	dialogObjectId: number?,
}

export type ClientVanityLockedManager = typeof(setmetatable({} :: ClientVanityLockedManagerFields, ClientVanityLockedManager))

function ClientVanityLockedManager.getGuiRoot(self: ClientVanityLockedManager): Instance
	return GuiRoot
end

function ClientVanityLockedManager.notifyForceEnd(self: ClientVanityLockedManager)
	self:cleanupDialog()
end

function ClientVanityLockedManager.notifyClickOutside(self: ClientVanityLockedManager)
	self:notifyForceEnd()
end

function ClientVanityLockedManager.getHudElements(self: ClientVanityLockedManager): { number }
	return {}
end

function ClientVanityLockedManager.beginDialog(self: ClientVanityLockedManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	if self.dialogObjectId then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt.Enabled = false
	end

	self.dialogObjectId = objectId

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityLockedManager.cleanupDialog(self: ClientVanityLockedManager)
	GuiRoot.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	local objectId = self.dialogObjectId
	if not objectId then
		return
	end

	self.dialogObjectId = nil

	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt.Enabled = true
	end
end

function ClientVanityLockedManager.removeIndicators(self: ClientVanityLockedManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt:Destroy()
		indicatorData.prompt = nil
	end

	self.indicatorMap[objectId] = nil
end


-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientVanityLockedManager.notifyNewInstance(self: ClientVanityLockedManager, inst: any)
	-- we track modifications of all vanity gnome locked

	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	if self.indicatorMap[objectId] then
		print("already have vanity gnome locked", inst, objectId)
		return
	end

	local indicatorData: IndicatorData = {
		instance = inst,
	}
	self.indicatorMap[objectId] = indicatorData

	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's vanity gnome locked was made", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 15)
	objProximityPrompt.ActionText = "Investigate"
	objProximityPrompt.HoldDuration = 0
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to investigate", inst)
			self:beginDialog(objectId)
		end
	)

	objProximityPrompt.Parent = inst

	indicatorData.prompt = objProximityPrompt

end

function ClientVanityLockedManager.notifyRemoveInstance(self: ClientVanityLockedManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	self:removeIndicators(objectId)
end

function ClientVanityLockedManager.getMapSize(self: ClientVanityLockedManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientVanityLockedManager.init(self: ClientVanityLockedManager)

	collectionService:GetInstanceAddedSignal(Tags.VANITY_GNOME_LOCKED):Connect(
		function(inst)
			--print("new vanity gnome locked exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.VANITY_GNOME_LOCKED):Connect(
		function(inst)
			--print("vanity gnome locked is gone", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.VANITY_GNOME_LOCKED) do
		--print("existing vanity gnome locked exists", inst)
		self:notifyNewInstance(inst)
	end


	local exitButton: any = utils.findFirstDescendant(GuiRoot, "ExitButton")
	exitButton.Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
end

function ClientVanityLockedManager.new(): ClientVanityLockedManager
	local self = setmetatable({} :: ClientVanityLockedManagerFields, ClientVanityLockedManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientVanityLockedManager.new()

return singleton
