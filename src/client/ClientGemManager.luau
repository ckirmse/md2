--!strict

local ClientGemManager = {}
ClientGemManager.__index = ClientGemManager

local collectionService = game:GetService("CollectionService")
local playersService = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
-- the effect templates' shapes only exist in Studio, so they are untyped here
local GemHit: any = ParticleEffects:WaitForChild("GemHit")
local Effects = GameAssets:WaitForChild("Effects")
local GemCollectAudioParent: any = Effects:WaitForChild("GemCollectAudioParent")
local GemSpawnAudioParent: any = Effects:WaitForChild("GemSpawnAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local PivotToTargetTween = require("@game/ReplicatedStorage/Shared/PivotToTargetTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

type IndicatorData = {
	instance: any, -- world gem instance; its shape only exists at runtime
	animationFlyAwayChangedConnect: RBXScriptConnection?,
	tweenCompletedConnect: RBXScriptConnection?,
}

type ClientGemManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientGemManager = typeof(setmetatable({} :: ClientGemManagerFields, ClientGemManager))

function ClientGemManager.beginAnimateFlyAway(self: ClientGemManager, itemId: number, durationSec: number, targetPart: BasePart)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local tweenInfo = TweenInfo.new(
		durationSec,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	local tween = PivotToTargetTween(inst, tweenInfo, targetPart)
	indicatorData.tweenCompletedConnect = tween.Completed:Connect(
		function()
			local tweenCompletedConnect = indicatorData.tweenCompletedConnect
			if tweenCompletedConnect then
				tweenCompletedConnect:Disconnect()
				indicatorData.tweenCompletedConnect = nil
			end

			--print("tween completed")
			utils.setPropertyTreeBaseParts(inst, "Transparency", 1)

			local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

			local particleParent = GemHit:Clone()
			particleParent:PivotTo(targetPart:GetPivot())
			utils.setPropertyTreeClassName(particleParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))
			particleParent:FindFirstChild("GemBurst"):Emit(1)

			particleParent.Parent = targetPart

			utils.safelyDisposeOfParticleParent(particleParent, 0.3)

			local gemCollectAudioParent = GemCollectAudioParent:Clone()
			gemCollectAudioParent.Position = targetPart:GetPivot().Position
			gemCollectAudioParent.Parent = workspace
			game:GetService("Debris"):AddItem(gemCollectAudioParent, 5) -- destroy after 5s

			local audioGemCollect = gemCollectAudioParent:FindFirstChild("AudioGemCollect")
			audioGemCollect:Play()

		end
	)

	tween:Play()
end

function ClientGemManager.cleanupAnimateFlyAway(self: ClientGemManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local tweenCompletedConnect = indicatorData.tweenCompletedConnect
	if tweenCompletedConnect then
		tweenCompletedConnect:Disconnect()
		indicatorData.tweenCompletedConnect = nil

	end
end

function ClientGemManager.removeIndicators(self: ClientGemManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local animationFlyAwayChangedConnect = indicatorData.animationFlyAwayChangedConnect
	if animationFlyAwayChangedConnect then
		animationFlyAwayChangedConnect:Disconnect()
		indicatorData.animationFlyAwayChangedConnect = nil
	end

	-- as of 2026-august-11 this passes itemId; it was previously called with no argument,
	-- which made it a silent no-op
	self:cleanupAnimateFlyAway(itemId)

	self.indicatorMap[itemId] = nil
end

function ClientGemManager.handleAnimationFlyAway(self: ClientGemManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local animationFlyAwayStr = inst:GetAttribute(Attributes.ANIMATION_FLY_AWAY)
	if animationFlyAwayStr then
		local iterFunc = string.gmatch(animationFlyAwayStr, "%S+")

		local serverDestroyTime = tonumber(iterFunc()) :: number

		local now = workspace:GetServerTimeNow()
		local remainingDurationSec = serverDestroyTime - now
		if remainingDurationSec <= 0 then
			--print("gem out of time before animation started")
			self:removeIndicators(itemId)
		end

		local userId = inst:GetAttribute(Attributes.USER_ID)
		local targetPlayer = playersService:GetPlayerByUserId(userId)
		if not targetPlayer then
			--print("cannot find player for gem", userId)
			self:removeIndicators(itemId)
			return
		end

		local character = targetPlayer.Character or targetPlayer.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

		self:beginAnimateFlyAway(itemId, remainingDurationSec, humanoidRootPart)
	else
		self:cleanupAnimateFlyAway(itemId)
	end
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
-- that does not happen with gems, obviously
function ClientGemManager.notifyNewInstance(self: ClientGemManager, inst: any, wasJustCreated: boolean)
	-- we track modifications of all crops; only do grow complete time of our player's crops

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local animationFlyAwayChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_FLY_AWAY):Connect(
		function()
			self:handleAnimationFlyAway(itemId)
		end
	)

	self.indicatorMap[itemId] = {
		instance = inst,
		animationFlyAwayChangedConnect = animationFlyAwayChangedConnect,
	}

	if inst:GetAttribute(Attributes.ANIMATION_FLY_AWAY) then
		self:handleAnimationFlyAway(itemId)
	end

	if wasJustCreated then
		local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

		local particleParent = GemHit:Clone()
		particleParent:PivotTo(inst:GetPivot())
		utils.setPropertyTreeClassName(particleParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))

		particleParent:FindFirstChild("GemBurst"):Emit(1)
		particleParent.Parent = inst

		utils.safelyDisposeOfParticleParent(particleParent, 0.3)

		local gemSpawnAudioParent = GemSpawnAudioParent:Clone()
		gemSpawnAudioParent.Position = inst:GetPivot().Position
		gemSpawnAudioParent.Parent = workspace
		game:GetService("Debris"):AddItem(gemSpawnAudioParent, 5) -- destroy after 5s

		local audioGemSpawn = gemSpawnAudioParent:FindFirstChild("AudioGemSpawn")
		audioGemSpawn:Play()
	end

end

function ClientGemManager.notifyRemoveInstance(self: ClientGemManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	self:removeIndicators(itemId)
end

function ClientGemManager.getMapSize(self: ClientGemManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientGemManager.init(self: ClientGemManager)

	collectionService:GetInstanceAddedSignal(Tags.GEM):Connect(
		function(inst)
			--print("new gem exists", inst)
			local wasJustCreated = true
			self:notifyNewInstance(inst, wasJustCreated)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.GEM):Connect(
		function(inst)
			--print("gem is gone", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.GEM) do
		--print("existing gem exists", inst)
		local wasJustCreated = false
		self:notifyNewInstance(inst, wasJustCreated)
	end

end

function ClientGemManager.new(): ClientGemManager
	local self = setmetatable({} :: ClientGemManagerFields, ClientGemManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientGemManager.new()

return singleton
