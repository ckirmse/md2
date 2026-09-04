--!strict

local ClientConsumableCropManager = {}
ClientConsumableCropManager.__index = ClientConsumableCropManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the templates' shapes only exist in Studio, so they are untyped here
local Arrow3D: any = UX:WaitForChild("Arrow3D")
local Effects = GameAssets:WaitForChild("Effects")
local ConsumableCropAudioParent: any = Effects:WaitForChild("ConsumableCropAudioParent")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")

local PROMPT_NAME = "EatProxPrompt"
local ARROW_NAME = "EatArrow"

local ARROW_PULSE_DURATION = 1
local ARROW_PULSE_AMPLITUDE = 1

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	instance: any, -- world crop instance; its shape only exists at runtime
	prompt: ProximityPrompt?,
	arrow: any?, -- Arrow3D clone
}

type ClientConsumableCropManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	height: number,
	audioConsumableCrop: any,
	audioHarvestBegin: any,
	audioCannotHarvest: any,
}

export type ClientConsumableCropManager = typeof(setmetatable({} :: ClientConsumableCropManagerFields, ClientConsumableCropManager))

function ClientConsumableCropManager.removeIndicators(self: ClientConsumableCropManager, itemId: number, shouldFadeArrow: boolean)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt:Destroy()
		indicatorData.prompt = nil
	end

	local arrow = indicatorData.arrow
	if arrow then
		if shouldFadeArrow then
			tweenService:Create(arrow, TweenInfo.new(0.2), {Color = Color3.fromRGB(255, 255, 255)}):Play()
			local tween = tweenService:Create(arrow, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.2), {Transparency = 1})
			tween.Completed:Connect(
				function()
					arrow:Destroy()
				end
			)
			tween:Play()
		else
			arrow:Destroy()
		end
		indicatorData.arrow = nil
	end

	self.indicatorMap[itemId] = nil

end

function ClientConsumableCropManager.configureIndicators(self: ClientConsumableCropManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	-- the character rig's children only exist at runtime, so they are untyped here
	local playerY = (player.Character :: any).HumanoidRootPart.Position.Y

	local tool = utils.getHoldingToolWithHandle(player)
	local isToolEquipped = tool ~= nil
	local isRiding = clientRideController:isRiding()
	local isRidingAndControlling = clientRideController:isRidingAndControlling()
	local isPlayerFarBelowCrop = playerY < inst:GetPivot().Position.Y - 3

	-- set when the indicator is created; the cast records that
	local objProximityPrompt = indicatorData.prompt :: ProximityPrompt

	if isToolEquipped or isPlayerFarBelowCrop or (isRiding and not isRidingAndControlling) then
		objProximityPrompt.Enabled = false
	else
		objProximityPrompt.Enabled = true
		if isRiding then
			objProximityPrompt.MaxActivationDistance = Constants.RIDE_EAT_DISTANCE
		else
			-- we scale up the distance based on size (height) of the crop
			objProximityPrompt.MaxActivationDistance = math.min(Constants.SUMMON_EAT_MAX_DISTANCE, Constants.SUMMON_EAT_MIN_DISTANCE + self.height / 2)
		end
	end
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientConsumableCropManager.notifyNewConsumableInstance(self: ClientConsumableCropManager, inst: any, wasJustCreated: boolean)
	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item was made", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	-- there shouldn't be any, but just be safe...
	local shouldFadeArrow = false
	self:removeIndicators(itemId, shouldFadeArrow)


	-- Wait one heartbeat for child part CFrames to settle after reparenting from
	-- a player's hand back to workspace, otherwise GetExtentsSize returns inflated bounds.
	-- ugh roblox. Necessary hacks.
	runService.Heartbeat:Wait()
	if not inst.Parent then
		return
	end

	--print("new instance--hooking to consume", inst)

	-- note that these prompts won't work if the prompt is a child of a model and the model doesn't have a PrimaryPart

	local part
	if inst:IsA("Model") then
		part = inst.PrimaryPart
		if not part then
			warn("consumable crop is a model with no primary part", inst)
			return
		end
	else
		part = inst
	end

	-- make it able to be consumed

	self.height = utils.getInstanceHeight(inst)
	--print("consumable crop height", inst, self.height)

	-- place an attachment half way up the model to put the prompt on
	local attachment = Instance.new("Attachment")
	attachment.Axis = Vector3.yAxis
	attachment.Position = Vector3.new(0, self.height / 2, 0)
	attachment.Parent = inst

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 0)
	objProximityPrompt.ActionText = "Harvest"
	objProximityPrompt.HoldDuration = 0
	objProximityPrompt.MaxActivationDistance = 0
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to harvest", inst)
			if clientRideController:isRiding() then
				RemoteEvents.TryEatWhileRiding:FireServer(inst:GetAttribute(Attributes.ITEM_ID))
			else
				RemoteEvents.TrySummonDragonToEat:FireServer(inst:GetAttribute(Attributes.ITEM_ID))

			end
		end
	)

	objProximityPrompt.Parent = attachment

	local instHeight = utils.getInstanceHeight(inst)
	--print("placing arrow, ground at around 1.5 or whatever, part Y is", part.Position.Y, "inst height is", instHeight)

	local arrow = Arrow3D:Clone()
	arrow.Name = ARROW_NAME
	arrow.Anchored = true
	arrow.Orientation = Vector3.new(0, 90, 0)
	local arrowBottomY = part.Position.Y + instHeight + math.max(3, instHeight * 0.15)
	local arrowTopY = arrowBottomY + ARROW_PULSE_AMPLITUDE * 2
	arrow.Position = Vector3.new(part.Position.X, arrowBottomY, part.Position.Z)
	arrow.Transparency = 1

	if objProximityPrompt.Enabled then
		tweenService:Create(arrow, TweenInfo.new(0.3), {Transparency = 0}):Play()
	end

	local duration = ARROW_PULSE_DURATION
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true, -- reverses afterwards
		0
	)

	local goal = {}
	goal.Position = Vector3.new(part.Position.X, arrowTopY, part.Position.Z)

	local tween = tweenService:Create(arrow, tweenInfo, goal)
	tween:Play()

	arrow.Parent = workspace

	self.indicatorMap[itemId] = {
		instance = inst,
		prompt = objProximityPrompt,
		arrow = arrow,
	}

	if wasJustCreated then
		-- we only play audio if the crop just became consumable, not on startup
		self.audioConsumableCrop:Play()
	end
end

function ClientConsumableCropManager.notifyBeginMergeActivation(self: ClientConsumableCropManager, obj: any)
	local indicatorData = self.indicatorMap[obj:GetAttribute(Attributes.ITEM_ID)]
	if not indicatorData then
		return
	end

	local arrow = indicatorData.arrow
	if not arrow then
		return
	end
	tweenService:Create(arrow, TweenInfo.new(0.3), {Transparency = 1}):Play()
end

function ClientConsumableCropManager.notifyCancelMergeActivation(self: ClientConsumableCropManager, obj: any)
	local indicatorData = self.indicatorMap[obj:GetAttribute(Attributes.ITEM_ID)]
	if not indicatorData then
		return
	end

	local arrow = indicatorData.arrow
	if not arrow then
		return
	end
	tweenService:Create(arrow, TweenInfo.new(0.3), {Transparency = 0}):Play()
end

function ClientConsumableCropManager.notifyRemoveConsumableInstance(self: ClientConsumableCropManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	local shouldFadeArrow = (inst.Parent == workspace)
	self:removeIndicators(itemId, shouldFadeArrow)
end

function ClientConsumableCropManager.notifySummonDragonToEatStatus(self: ClientConsumableCropManager, isSuccess: boolean)
	--print("summon dragon to eat finished")
	if not isSuccess then
		self.audioCannotHarvest:Play()
		return
	end

	self.audioHarvestBegin:Play()
end

function ClientConsumableCropManager.notifyEatWhileRidingStatus(self: ClientConsumableCropManager, isSuccess: boolean)
	--print("eat while riding finished")
	if not isSuccess then
		self.audioCannotHarvest:Play()
		return
	end

	self.audioHarvestBegin:Play()
end

function ClientConsumableCropManager.getMapSize(self: ClientConsumableCropManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientConsumableCropManager.init(self: ClientConsumableCropManager)

	collectionService:GetInstanceAddedSignal(Tags.CONSUMABLE_CROP):Connect(
		function(inst)
		local wasJustCreated = true
			self:notifyNewConsumableInstance(inst, wasJustCreated)
			--print("new item can be eaten", inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CONSUMABLE_CROP):Connect(
		function(inst)
			--print("item no longer consumable", inst)
			self:notifyRemoveConsumableInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CONSUMABLE_CROP) do
		local wasJustCreated = false
		self:notifyNewConsumableInstance(inst, wasJustCreated)
		--print("existing item can be eaten", inst)
	end

	runService.PostSimulation:Connect(
		function(deltaTime)
			for itemId, indicatorData in self.indicatorMap do
				self:configureIndicators(itemId)
			end
		end
	)

	clientRideController:getEvent():Connect(
		function(isRiding)
			--print("crop manager knows is riding", isRiding)
			for itemId, indicatorData in self.indicatorMap do
				self:configureIndicators(itemId)
			end
		end
	)
end

function ClientConsumableCropManager.new(): ClientConsumableCropManager
	local self = setmetatable({} :: ClientConsumableCropManagerFields, ClientConsumableCropManager)

	self.indicatorMap = {}
	self.height = 0

	local consumableCropAudioParent = ConsumableCropAudioParent:Clone()
	consumableCropAudioParent.Parent = workspace

	self.audioConsumableCrop = consumableCropAudioParent:FindFirstChild("AudioConsumableCrop")
	self.audioHarvestBegin = consumableCropAudioParent:FindFirstChild("AudioHarvestBegin")
	self.audioCannotHarvest = consumableCropAudioParent:FindFirstChild("AudioCannotHarvest")

	return self
end


local singleton = ClientConsumableCropManager.new()

return singleton
