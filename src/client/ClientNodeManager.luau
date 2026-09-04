--!strict

local ClientNodeManager = {}
ClientNodeManager.__index = ClientNodeManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the effect templates' shapes only exist in Studio, so they are untyped here
local NodeBreaksAudioParent: any = Effects:WaitForChild("NodeBreaksAudioParent")
local NodeBreakParent: any = Effects:WaitForChild("NodeBreakParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")
local screenGuiManager = require("./ScreenGuiManager")

local PROMPT_NAME = "MineProxPrompt"

local player = game:GetService("Players").LocalPlayer :: Player

type AnimateNodeRotateState = {
	runConnect: RBXScriptConnection?,
}

type IndicatorData = {
	instance: any, -- world node instance; its shape only exists at runtime
	prompt: ProximityPrompt,
	animationMineNodeChangedConnect: RBXScriptConnection?,
	isTryingToMine: boolean,
	animateNodeRotate: AnimateNodeRotateState?,
}

type ClientNodeManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientNodeManager = typeof(setmetatable({} :: ClientNodeManagerFields, ClientNodeManager))

function ClientNodeManager.beginAnimateMineNode(self: ClientNodeManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local crystal = inst:FindFirstChild("CrystalNode_Crystal")
	if not crystal then
		-- this may be possible if someone else just mined it
		return
	end

	local nodeBreakParent = NodeBreakParent:Clone()
	nodeBreakParent:PivotTo(crystal:GetPivot())
	local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

	if primaryElement ~= enums.PrimaryElements.NONE then
		utils.setPropertyTreeClassName(nodeBreakParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
	end

	nodeBreakParent.Parent = workspace

	nodeBreakParent:FindFirstChild("BurstRing"):Emit(1)
	nodeBreakParent:FindFirstChild("CrystalBreak"):Emit(50)
	nodeBreakParent:FindFirstChild("Flash"):Emit(1)

	utils.safelyDisposeOfParticleParent(nodeBreakParent, 0.2)

	local nodeBreaksAudioParent = NodeBreaksAudioParent:Clone()
	nodeBreaksAudioParent.Position = inst:GetPivot().Position
	nodeBreaksAudioParent.Parent = workspace
	game:GetService("Debris"):AddItem(nodeBreaksAudioParent, 5) -- destroy after 5s

	local audioNodeBreaks = nodeBreaksAudioParent:FindFirstChild("AudioNodeBreaks")
	audioNodeBreaks:Play()
end

function ClientNodeManager.cleanupAnimateMineNode(self: ClientNodeManager, objectId: number)
end

function ClientNodeManager.beginAnimateNodeRotate(self: ClientNodeManager, objectId: number, partName: string, rotationPeriodSec: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local part = inst:FindFirstChild(partName)
	if not part then
		return
	end

	local runConnect = runService.PreSimulation:Connect(
		function(deltaTime: number)
			local cframe = part.CFrame
			local newCFrame = cframe * CFrame.fromEulerAnglesXYZ(0, math.rad(deltaTime * 360 / rotationPeriodSec), 0)
			part:PivotTo(newCFrame)
		end
	)

	indicatorData.animateNodeRotate = {
		runConnect = runConnect,
	}
end

function ClientNodeManager.cleanupAnimateNodeRotate(self: ClientNodeManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local animateNodeRotate = indicatorData.animateNodeRotate
	if not animateNodeRotate then
		return
	end

	local runConnect = animateNodeRotate.runConnect
	if runConnect then
		runConnect:Disconnect()
		animateNodeRotate.runConnect = nil
	end

	indicatorData.animateNodeRotate = nil

end


function ClientNodeManager.configureIndicators(self: ClientNodeManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	local objProximityPrompt = indicatorData.prompt
	local isTryingToMine = indicatorData.isTryingToMine
	local isRiding = clientRideController:isRiding()

	local isMinable = inst:HasTag(Tags.MINABLE_NODE)
	--print("configuring indicators node", objectId, inst, indicatorData, isMinable, isTryingToMine)
	if isMinable and not isTryingToMine and not isRiding then
		objProximityPrompt.Enabled = true
	else
		objProximityPrompt.Enabled = false
	end
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientNodeManager.notifyNewInstance(self: ClientNodeManager, inst: any)
	local userId = inst:GetAttribute(Attributes.USER_ID)

	if userId and userId ~= player.UserId then
		--print("someone else's player node was made", inst, userId)
		return
	end

	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = true
	objProximityPrompt.UIOffset = Vector2.new(0, 0)
	objProximityPrompt.ActionText = "Mine For Crystals"
	objProximityPrompt.HoldDuration = 0
	objProximityPrompt.MaxActivationDistance = Constants.SUMMON_MINE_NODE_DISTANCE
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to mine node", inst)
			self.indicatorMap[objectId].isTryingToMine = true
			self:configureIndicators(objectId)

			RemoteEvents.TrySummonDragonToMine:FireServer(inst:GetAttribute(Attributes.OBJECT_ID))

			local highlight = Instance.new("Highlight")
			highlight.Adornee = inst
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillColor = Color3.fromRGB(255, 255, 255)
			highlight.FillTransparency = 0
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0
			highlight.Parent = inst
			local tween = tweenService:Create(highlight, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1})
			tween.Completed:Connect(
				function()
					highlight:Destroy()
				end
			)
			tween:Play()

		end
	)

	local animationMineNodeChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_MINE_NODE):Connect(
		function()
			local animationMineNodeStr = inst:GetAttribute(Attributes.ANIMATION_MINE_NODE)
			if animationMineNodeStr then
				self:beginAnimateMineNode(objectId)
			else
				self:cleanupAnimateMineNode(objectId)
			end
		end
	)

	self.indicatorMap[objectId] = {
		instance = inst,
		prompt = objProximityPrompt,
		animationMineNodeChangedConnect = animationMineNodeChangedConnect,
		isTryingToMine = false,
	}

	self:configureIndicators(objectId)

	local animationNodeRotateStr = inst:GetAttribute(Attributes.ANIMATION_NODE_ROTATE)
	if animationNodeRotateStr then
		local iterFunc = string.gmatch(animationNodeRotateStr, "%S+")

		local partName = iterFunc() :: string
		local rotationPeriodSec = tonumber(iterFunc()) :: number
		self:beginAnimateNodeRotate(objectId, partName, rotationPeriodSec)
	end

	-- parent it to the attachment that'll be near the ground
	objProximityPrompt.Parent = inst

end

function ClientNodeManager.notifyRemoveInstance(self: ClientNodeManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local animationMineNodeChangedConnect = indicatorData.animationMineNodeChangedConnect
	if animationMineNodeChangedConnect then
		animationMineNodeChangedConnect:Disconnect()
		indicatorData.animationMineNodeChangedConnect = nil
	end

	self:cleanupAnimateMineNode(objectId)

	self:cleanupAnimateNodeRotate(objectId)

	self.indicatorMap[objectId] = nil

	indicatorData.prompt:Destroy()
end

function ClientNodeManager.notifySummonDragonToMineStatus(self: ClientNodeManager, isSuccess: boolean)
	--print("summon dragon to mine status", isSuccess)

	if isSuccess then
		screenGuiManager:showSystemMessage("A dragon heeds your call!")
	end

	for objectId, indicatorData in self.indicatorMap do
		if not indicatorData.isTryingToMine then
			continue
		end

		if not isSuccess then
			indicatorData.isTryingToMine = false
			self:configureIndicators(objectId)
		end
	end
end

function ClientNodeManager.getMapSize(self: ClientNodeManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientNodeManager.init(self: ClientNodeManager)

	collectionService:GetInstanceAddedSignal(Tags.NODE):Connect(
		function(inst)
			--print("new social node exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.NODE):Connect(
		function(inst)
			--print("social node no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.NODE) do
		--print("existing social node exists", inst)
		self:notifyNewInstance(inst)
	end

	collectionService:GetInstanceAddedSignal(Tags.MINABLE_NODE):Connect(
		function(inst: any)
			--print("became minable so we must not be in the middle of mining it", inst)
			local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
			local indicatorData = self.indicatorMap[objectId]
			if not indicatorData then
				return
			end

			indicatorData.isTryingToMine = false
			self:configureIndicators(inst:GetAttribute(Attributes.OBJECT_ID))
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.MINABLE_NODE):Connect(
		function(inst: any)
			self:configureIndicators(inst:GetAttribute(Attributes.OBJECT_ID))
		end
	)

	clientRideController:getEvent():Connect(
		function(isRiding)
			--print("node manager knows is riding", isRiding)
			for objectId, indicatorData in self.indicatorMap do
				self:configureIndicators(objectId)
			end
		end
	)

end

function ClientNodeManager.new(): ClientNodeManager
	local self = setmetatable({} :: ClientNodeManagerFields, ClientNodeManager)

	self.indicatorMap = {}

	return self
end

local singleton = ClientNodeManager.new()

return singleton
