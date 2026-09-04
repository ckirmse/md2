--!strict

local ClientCritterManager = {}
ClientCritterManager.__index = ClientCritterManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the effect templates' shapes only exist in Studio, so they are untyped here
local NodeBreaksAudioParent: any = Effects:WaitForChild("NodeBreaksAudioParent")
local NodeBreakParent: any = Effects:WaitForChild("NodeBreakParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local CritterHelpers = require("@game/ReplicatedStorage/Shared/CritterHelpers")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")

type IndicatorData = {
	instance: any, -- world critter instance; its shape only exists at runtime
	baseTime: number,
	caster: any?,
	crate: any?,
	runConnect: RBXScriptConnection?,
	animationOpeningChangedConnect: RBXScriptConnection?,
	animationExplodeCritterConnect: RBXScriptConnection?,
}

type ClientCritterManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientCritterManager = typeof(setmetatable({} :: ClientCritterManagerFields, ClientCritterManager))

function ClientCritterManager.configureIndicators(self: ClientCritterManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

end

-- as of 2026-august-11 these two are no-op stubs: the ANIMATION_OPENING handler below calls
-- them, but they were never implemented and would have crashed if that attribute ever changed
function ClientCritterManager.beginAnimateOpening(self: ClientCritterManager, objectId: number)
end

function ClientCritterManager.cleanupAnimateOpening(self: ClientCritterManager, objectId: number)
end

function ClientCritterManager.beginAnimateExplodeCritter(self: ClientCritterManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	local caster = indicatorData.caster :: any

	-- caster
	local nodeBreakParent = NodeBreakParent:Clone()
	nodeBreakParent:PivotTo(caster:GetPivot())
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

function ClientCritterManager.cleanupAnimateExplodeCritter(self: ClientCritterManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientCritterManager.notifyNewInstance(self: ClientCritterManager, inst: any)

	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	local baseTime = inst:GetAttribute(Attributes.BASE_TIME) :: number
	local indicatorData: IndicatorData = {
		instance = inst,
		baseTime = baseTime,
	}
	self.indicatorMap[objectId] = indicatorData

	local casterPath = inst:GetAttribute(Attributes.CASTER_PATH)
	local crateTemplatePath = inst:GetAttribute(Attributes.CRATE_TEMPLATE_PATH)

	local casterTemplate: any = utils.getGameAssetPathReference(casterPath)

	local caster = casterTemplate:Clone()

	caster.PrimaryPart.Anchored = true
	utils.setPropertyTreeBaseParts(caster, "CanCollide", false)
	caster:PivotTo(inst:GetPivot())

	collectionService:AddTag(caster, Tags.CRITTER_CASTER)
	caster:SetAttribute(Attributes.OBJECT_ID, objectId)

	caster.Parent = inst.Parent

	local crateTemplate: any = utils.getGameAssetPathReference(crateTemplatePath)
	local crate = crateTemplate:Clone()

	local crateAttachment: any = utils.findFirstDescendant(crate, "RopeCrate")

	local ropeConstraint: any = utils.findFirstDescendant(caster, "RopeConstraint")

	ropeConstraint.Attachment1 = crateAttachment

	crate:PivotTo(caster:GetPivot() + Vector3.new(0, -12, 0))
	crate.Parent = caster

	indicatorData.caster = caster
	indicatorData.crate = crate

	local period = inst:GetAttribute(Attributes.PERIOD) :: number
	local radius = inst:GetAttribute(Attributes.RADIUS) :: number

	local center = inst:GetPivot().Position

	indicatorData.runConnect = runService.PostSimulation:Connect(
		function()
			local elapsedTime = workspace:GetServerTimeNow() - baseTime

			local angle = (elapsedTime / period) * (math.pi * 2)

			local cframe = CritterHelpers.calculateCFrame(center, radius, angle)

			caster:PivotTo(cframe)
		end
	)

	--print("caster", caster, caster:GetPivot().Position, "crate", crate, crate:GetPivot().Position)
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


	indicatorData.animationExplodeCritterConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_EXPLODE_CRITTER):Connect(
		function()
			local animationExplodeCritterStr = inst:GetAttribute(Attributes.ANIMATION_EXPLODE_CRITTER)
			if animationExplodeCritterStr then
				self:beginAnimateExplodeCritter(objectId)
			else
				self:cleanupAnimateExplodeCritter(objectId)
			end
		end
	)

	self:configureIndicators(objectId)

end

function ClientCritterManager.notifyRemoveInstance(self: ClientCritterManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster
	if caster then
		clientRideController:notifyTargetRemoving(objectId)
		caster:Destroy();
		(indicatorData :: any).caster = nil
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	local animationExplodeCritterConnect = indicatorData.animationExplodeCritterConnect
	if animationExplodeCritterConnect then
		animationExplodeCritterConnect:Disconnect()
		indicatorData.animationExplodeCritterConnect = nil
	end

	self.indicatorMap[objectId] = nil

end

function ClientCritterManager.getMapSize(self: ClientCritterManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientCritterManager.init(self: ClientCritterManager)

	collectionService:GetInstanceAddedSignal(Tags.CRITTER):Connect(
		function(inst)
			--print("new critter exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CRITTER):Connect(
		function(inst)
			--print("critter no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CRITTER) do
		--print("existing critter exists", inst)
		self:notifyNewInstance(inst)
	end

end

function ClientCritterManager.new(): ClientCritterManager
	local self = setmetatable({} :: ClientCritterManagerFields, ClientCritterManager)

	self.indicatorMap = {}

	return self
end

local singleton = ClientCritterManager.new()

return singleton
