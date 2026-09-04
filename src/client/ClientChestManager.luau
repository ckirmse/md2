--!strict

local ClientChestManager = {}
ClientChestManager.__index = ClientChestManager

local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the templates' shapes only exist in Studio, so they are untyped here
local ClosedChestBillboard: any = UX:WaitForChild("ClosedChestBillboard")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
local MergePost: any = ParticleEffects:WaitForChild("MergePost")
local Effects = GameAssets:WaitForChild("Effects")
local FinishOpenChestAudioParent: any = Effects:WaitForChild("FinishOpenChestAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")


local PROMPT_NAME = "MineProxPrompt"

-- when someone else opens it
local OPEN_SEC = 0.3

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	instance: any, -- world chest instance; its shape only exists at runtime
	lid: any,
	baseLidCFrame: CFrame,
	openLidCFrame: CFrame,
	isOpening: boolean,
	billboard: any?, -- ClosedChestBillboard clone
	prompt: ProximityPrompt?,
	chestHighlight: Highlight?,
	characterDescendantAddedConnect: RBXScriptConnection?,
	characterDescendantRemovingConnect: RBXScriptConnection?,
	openedChangedConnect: RBXScriptConnection?,
	animationOpeningChangedConnect: RBXScriptConnection?,
}

type ClientChestManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientChestManager = typeof(setmetatable({} :: ClientChestManagerFields, ClientChestManager))

function ClientChestManager.calculateUsableKeyItemId(self: ClientChestManager, objectId: number): number?
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return nil
	end

	local inst = indicatorData.instance

	local usableKeyItemId = nil

	-- the character rig's children only exist at runtime, so they are untyped here
	local tool = (player.Character :: any):FindFirstChildOfClass("Tool")
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle then
			local itemId = handle:GetAttribute(Attributes.ITEM_ID)
			local keyObj: any = utils.tryGetModelForPlayerAndItemId(player, itemId)
			if collectionService:HasTag(keyObj, Tags.KEY) then
				local level = keyObj:GetAttribute(Attributes.LEVEL)
				if level and level >= inst:GetAttribute(Attributes.LEVEL) then
					usableKeyItemId = itemId
				end
			end
		end
	end

	return usableKeyItemId
end

function ClientChestManager.configureIndicators(self: ClientChestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	local billboard = indicatorData.billboard :: any
	local prompt = indicatorData.prompt :: ProximityPrompt
	local isOpening = indicatorData.isOpening
	local isOpened = inst:GetAttribute(Attributes.OPENED)

	local usableKeyItemId = self:calculateUsableKeyItemId(objectId)

	if isOpening or isOpened then
		billboard.Enabled = false
		prompt.Enabled = false
	else
		local canOpen = usableKeyItemId ~= nil

		if canOpen then
			billboard.Enabled = false
			prompt.Enabled = true
		else
			billboard.Enabled = true
			prompt.Enabled = false
		end
	end

	local character = player.Character :: Model
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local distance = (inst:GetPivot().Position - humanoidRootPart.Position).Magnitude

	if prompt.Enabled and distance <= Constants.OPEN_CHEST_DISTANCE then
		if not indicatorData.chestHighlight then
			local highlight = Instance.new("Highlight")
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.FillColor = Color3.fromRGB(255, 255, 255)
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0

			highlight.Parent = inst

			indicatorData.chestHighlight = highlight
		end

	else
		local chestHighlight = indicatorData.chestHighlight
		if chestHighlight then
			--print("destroying chest highlight")
			chestHighlight:Destroy()
			indicatorData.chestHighlight = nil
		end
	end

end

function ClientChestManager.setOpened(self: ClientChestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	-- this is important for joining a server with already opened chests

	indicatorData.lid:PivotTo(indicatorData.openLidCFrame)
end

function ClientChestManager.completeOpenChest(self: ClientChestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local itemId = self:calculateUsableKeyItemId(objectId)
	if not itemId then
		print("not actually holding a key the client thinks can open the chest", objectId)
		return
	end

	indicatorData.isOpening = true
	self:configureIndicators(objectId)

	RemoteEvents.TryOpenChest:FireServer(objectId, itemId)

	-- show some particle effects
	local mergePost = MergePost:Clone()
	mergePost:PivotTo(inst:GetPivot())
	mergePost.Parent = workspace

	local level = inst:GetAttribute(Attributes.LEVEL)
	mergePost:FindFirstChild("Burst"):Emit(level)
	utils.safelyDisposeOfParticleParent(mergePost)

	local finishOpenChestAudioParent = FinishOpenChestAudioParent:Clone()
	finishOpenChestAudioParent.Position = inst:GetPivot().Position
	finishOpenChestAudioParent.Parent = workspace
	game:GetService("Debris"):AddItem(finishOpenChestAudioParent, 5) -- destroy after 5s

	local audioFinishOpenChest = finishOpenChestAudioParent:FindFirstChild("AudioFinishOpenChest")
	audioFinishOpenChest:Play()

end

function ClientChestManager.beginAnimateOpening(self: ClientChestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local lid = indicatorData.lid

	local tween = tweenService:Create(lid, TweenInfo.new(OPEN_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = indicatorData.openLidCFrame})
	tween:Play()
end

function ClientChestManager.cleanupAnimateOpening(self: ClientChestManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientChestManager.notifyNewInstance(self: ClientChestManager, inst: any)

	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	local lid: any = utils.findFirstDescendant(inst, "Lid")

	local attachment = lid:FindFirstChildOfClass("Attachment")
	local pivot = attachment.WorldCFrame :: CFrame
	local rotation = CFrame.fromEulerAnglesXYZ(math.rad(-90), 0, 0)
	local rotationAroundPivot = pivot * rotation * pivot:Inverse()
	local openLidCFrame = rotationAroundPivot * lid.CFrame

	local indicatorData: IndicatorData = {
		instance = inst,
		lid = lid,
		baseLidCFrame = lid.CFrame,
		openLidCFrame = openLidCFrame,
		isOpening = false,
	}
	self.indicatorMap[objectId] = indicatorData

	-- setup billboard, show if chest is closed

	local billboard = ClosedChestBillboard:Clone()
	billboard.MaxDistance = 500
	billboard.Adornee = inst
	local _, size = inst:GetBoundingBox()
	billboard.StudsOffset = Vector3.new(0, 8 + size.Y / 2, 0)
	billboard:SetAttribute(Attributes.ITEM_ID, objectId) -- for debugging

	billboard.Parent = player:WaitForChild("PlayerGui")

	indicatorData.billboard = billboard

	local textLabel: any = utils.findFirstDescendant(billboard, "TextLabel")
	textLabel.Text = string.format("Equip key level %i or higher to open", inst:GetAttribute(Attributes.LEVEL))

	-- prompt to open
	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = true
	objProximityPrompt.UIOffset = Vector2.new(0, 0)
	objProximityPrompt.ActionText = "Unlock Chest"
	objProximityPrompt.MaxActivationDistance = Constants.OPEN_CHEST_DISTANCE
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("trying to unlock chest")
			self:completeOpenChest(objectId)
		end
	)
	objProximityPrompt.Parent = inst

	indicatorData.prompt = objProximityPrompt

	indicatorData.characterDescendantAddedConnect = (player.Character :: Model).DescendantAdded:Connect(
		function(descendant)
			self:configureIndicators(objectId)
		end
	)

	indicatorData.characterDescendantRemovingConnect = (player.Character :: Model).DescendantRemoving:Connect(
		function(descendant)
			task.defer(
				function()
					self:configureIndicators(objectId)
				end
			)
		end
	)

	indicatorData.openedChangedConnect = inst:GetAttributeChangedSignal(Attributes.OPENED):Connect(
		function()
			self:setOpened(objectId)
		end
	)

	indicatorData.animationOpeningChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_OPENING):Connect(
		function()
			local animationOpeningStr = inst:GetAttribute(Attributes.ANIMATION_OPENING)
			if animationOpeningStr then
				self:beginAnimateOpening(objectId)
			else
				self:cleanupAnimateOpening(objectId)
			end
		end
	)

	if inst:GetAttribute(Attributes.OPENED) then
		--print("setting opened", objectId)
		self:setOpened(objectId)
	end

	self:configureIndicators(objectId)

end

function ClientChestManager.notifyRemoveInstance(self: ClientChestManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local billboard = indicatorData.billboard
	if billboard then
		billboard:Destroy()
		indicatorData.billboard = nil
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt:Destroy()
		indicatorData.prompt = nil
	end

	local characterDescendantAddedConnect = indicatorData.characterDescendantAddedConnect
	if characterDescendantAddedConnect then
		characterDescendantAddedConnect:Disconnect()
		indicatorData.characterDescendantAddedConnect = nil
	end

	local characterDescendantRemovingConnect = indicatorData.characterDescendantRemovingConnect
	if characterDescendantRemovingConnect then
		characterDescendantRemovingConnect:Disconnect()
		indicatorData.characterDescendantRemovingConnect = nil
	end

	local openedChangedConnect = indicatorData.openedChangedConnect
	if openedChangedConnect then
		openedChangedConnect:Disconnect()
		indicatorData.openedChangedConnect = nil
	end

	local animationOpeningChangedConnect = indicatorData.animationOpeningChangedConnect
	if animationOpeningChangedConnect then
		animationOpeningChangedConnect:Disconnect()
		indicatorData.animationOpeningChangedConnect = nil
	end

	local chestHighlight = indicatorData.chestHighlight
	if chestHighlight then
		--print("destroying chest highlight")
		chestHighlight:Destroy()
		indicatorData.chestHighlight = nil
	end

	self.indicatorMap[objectId] = nil
end

function ClientChestManager.getMapSize(self: ClientChestManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientChestManager.init(self: ClientChestManager)

	collectionService:GetInstanceAddedSignal(Tags.CHEST):Connect(
		function(inst)
			--print("new chest exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CHEST):Connect(
		function(inst)
			--print("chest no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CHEST) do
		--print("existing chest exists", inst)
		self:notifyNewInstance(inst)
	end

end

function ClientChestManager.new(): ClientChestManager
	local self = setmetatable({} :: ClientChestManagerFields, ClientChestManager)

	self.indicatorMap = {}

	return self
end

local singleton = ClientChestManager.new()

return singleton
