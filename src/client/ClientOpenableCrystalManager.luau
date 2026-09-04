--!strict

local ClientOpenableCrystalManager = {}
ClientOpenableCrystalManager.__index = ClientOpenableCrystalManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")

local PROMPT_NAME = "OpenCrystalProxPrompt"

local player = game:GetService("Players").LocalPlayer :: Player

-- don't add more stuff here--new stuff belongs in ClientCrystalManager.luau

type IndicatorData = {
	instance: any, -- world crystal instance; its shape only exists at runtime
	prompt: ProximityPrompt,
	runConnect: RBXScriptConnection,
}

type ClientOpenableCrystalManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientOpenableCrystalManager = typeof(setmetatable({} :: ClientOpenableCrystalManagerFields, ClientOpenableCrystalManager))

function ClientOpenableCrystalManager.removeIndicators(self: ClientOpenableCrystalManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	indicatorData.prompt:Destroy()
	indicatorData.runConnect:Disconnect()

	self.indicatorMap[itemId] = nil
end

function ClientOpenableCrystalManager.configureIndicators(self: ClientOpenableCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- update proximity prompt

	local tool = utils.getHoldingToolWithHandle(player)
	local isToolEquipped = tool ~= nil
	local isRiding = clientRideController:isRiding()
	local isRidingAndControlling = clientRideController:isRidingAndControlling()

	--print("updating with", indicatorData.isBeingClaimed, isToolEquipped)

	local objProximityPrompt = indicatorData.prompt

	if isToolEquipped or (isRiding and not isRidingAndControlling) then
		objProximityPrompt.Enabled = false
	else
		objProximityPrompt.Enabled = true
	end

end


-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientOpenableCrystalManager.notifyNewInstance(self: ClientOpenableCrystalManager, inst: any)
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item is openable", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	-- there shouldn't be any, but just be safe...
	self:removeIndicators(inst)

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	--print("new instance--hooking to open", inst)

	-- note that these prompts won't work if the prompt is a child of a model and the model doesn't have a PrimaryPart

	local part
	if inst:IsA("Model") then
		part = inst.PrimaryPart
		if not part then
			warn("openable crystal is a model with no primary part", inst)
			return
		end
	else
		part = inst
	end

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 80)
	objProximityPrompt.ActionText = "Hold to Activate"
	objProximityPrompt.HoldDuration = 1
	objProximityPrompt.MaxActivationDistance = Constants.OPEN_CRYSTAL_DISTANCE
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to open crystal", inst)
			RemoteEvents.TrySummonDragonToOpen:FireServer(inst:GetAttribute(Attributes.ITEM_ID))

			local baseTransparency = part.Transparency
			part.Transparency = 0

			local highlight = Instance.new("Highlight")
			highlight.Adornee = inst
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillColor = Color3.fromRGB(255, 255, 255)
			highlight.FillTransparency = 0
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0
			highlight.Parent = part
			local tween = tweenService:Create(highlight, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1})
			tween.Completed:Connect(
				function()
					highlight:Destroy()
					part.Transparency = baseTransparency
				end
			)
			tween:Play()

		end
	)

	-- parent it to the attachment that'll be near the ground
	objProximityPrompt.Parent = utils.findFirstDescendant(inst, "Hold")

	local runConnect = runService.PreSimulation:Connect(
		function(deltaTime)
			self:configureIndicators(itemId)
		end
	)

	self.indicatorMap[itemId] = {
		instance = inst,
		prompt = objProximityPrompt,
		runConnect = runConnect,
	}

	self:configureIndicators(itemId)

end

function ClientOpenableCrystalManager.notifyRemoveOpenableInstance(self: ClientOpenableCrystalManager, inst: any)
	self:removeIndicators(inst)
end

function ClientOpenableCrystalManager.getMapSize(self: ClientOpenableCrystalManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientOpenableCrystalManager.init(self: ClientOpenableCrystalManager)

	collectionService:GetInstanceAddedSignal(Tags.OPENABLE_CRYSTAL):Connect(
		function(inst)
			self:notifyNewInstance(inst)
			--print("new item can be opened", inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.OPENABLE_CRYSTAL):Connect(
		function(inst)
			--print("item no longer openable", inst)
			self:notifyRemoveOpenableInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.OPENABLE_CRYSTAL) do
		self:notifyNewInstance(inst)
		--print("existing item can be opened", inst)
	end

end

function ClientOpenableCrystalManager.new(): ClientOpenableCrystalManager
	local self = setmetatable({} :: ClientOpenableCrystalManagerFields, ClientOpenableCrystalManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientOpenableCrystalManager.new()

return singleton
