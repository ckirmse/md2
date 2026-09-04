--!strict

local ClientCropManager = {}
ClientCropManager.__index = ClientCropManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
-- the effect template's shape only exists in Studio, so it is untyped here
local FireballHit: any = ParticleEffects:WaitForChild("FireballHit")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientNamePlateManager = require("./ClientNamePlateManager")

local FOOD_PARTICLE_ANCHOR_NAME = "FoodParticleAnchor"

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	instance: any, -- world crop instance; its shape only exists at runtime
	modificationsConnect: RBXScriptConnection?,
	animationEatChangedConnect: RBXScriptConnection?,
	animationFireballHitChangedConnect: RBXScriptConnection?,
	animationModificationsRemovedConnect: RBXScriptConnection?,
	runConnect: RBXScriptConnection?,
}

type ClientCropManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientCropManager = typeof(setmetatable({} :: ClientCropManagerFields, ClientCropManager))

function ClientCropManager.getGrowCompleteTimeText(self: ClientCropManager, inst: any): string?
	local growCompleteTime = inst:GetAttribute(Attributes.GROW_COMPLETE_TIME)
	if not growCompleteTime then
		return nil
	end

	--print("have grow complete time for", self)
	local timeToFullyGrownSec = math.ceil(math.max(1, growCompleteTime - workspace:GetServerTimeNow()))

	local retval = string.format("Harvest in %s", utils.convertDurationSecToString(timeToFullyGrownSec))

	return retval
end

function ClientCropManager.updateExtraText(self: ClientCropManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local extraTextArray = {}

	if inst:GetAttribute(Attributes.USER_ID) == player.UserId then
		local growCompleteTimeText = self:getGrowCompleteTimeText(inst)
		if growCompleteTimeText then
			table.insert(extraTextArray, growCompleteTimeText)
		end
	end

	local extraText: string? = nil
	for _, extraTextLine in extraTextArray do
		if extraText == nil then
			extraText = extraTextLine
		else
			extraText = extraText .. "\n" .. extraTextLine
		end
	end


	local currentExtraText = inst:GetAttribute(Attributes.NAME_PLATE_EXTRA_TEXT)
	if currentExtraText == extraText then
		return
	end

	inst:SetAttribute(Attributes.NAME_PLATE_EXTRA_TEXT, extraText)
	clientNamePlateManager:updateTextForItemId(inst:GetAttribute(Attributes.ITEM_ID))
end

function ClientCropManager.beginAnimateModificationsRemoved(self: ClientCropManager, itemId: number, particleParentPaths: { string })
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	for _, particleParentPath in particleParentPaths do
		--print("looking for", particleParentPath)
		local particleParentTemplate: any = utils.getGameAssetPathReference(particleParentPath)
		if not particleParentTemplate then
			warn("could not find", particleParentPath)
			continue
		end

		local particleParent = particleParentTemplate:Clone()
		particleParent.Transparency = 1
		particleParent:PivotTo(inst:GetPivot())
		particleParent.Parent = workspace
		utils.safelyDisposeOfParticleParent(particleParent, 0.5)
	end

end

function ClientCropManager.beginAnimateEat(self: ClientCropManager, itemId: number, particlePath: string, dragonPosition: Vector3)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local particleParent = inst:FindFirstChild(FOOD_PARTICLE_ANCHOR_NAME)
	if particleParent then
		-- already have one, don't make a second
		return
	end

	local bestPosition = inst:GetPivot().Position

	-- find our fruit nearest the dragon
	local fruitParts: { any } = utils.getAllDescendantsWithAttribute(inst, Attributes.VARIABLE_FOOD, true) :: { any }
	if #fruitParts > 0 then
		local bestFruit = fruitParts[1]
		local bestDistance = (bestFruit.Position - dragonPosition).Magnitude
		for _, fruit in fruitParts do
			local distance = (fruit.Position - dragonPosition).Magnitude
			if distance < bestDistance then
				bestFruit = fruit
				bestDistance = distance
			end
		end
		bestPosition = bestFruit.Position
	end

	local anchor = Instance.new("Part")
	anchor.Name = FOOD_PARTICLE_ANCHOR_NAME
	anchor.CFrame = CFrame.new(bestPosition)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = inst

	local particleTemplate: any = utils.getGameAssetPathReference(particlePath)
	local particle = particleTemplate:Clone()
	particle.Parent = anchor
end

function ClientCropManager.cleanupAnimateEat(self: ClientCropManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local particleParent = inst:FindFirstChild(FOOD_PARTICLE_ANCHOR_NAME)
	if particleParent then
		utils.safelyDisposeOfParticleParent(particleParent)
	end
end

function ClientCropManager.beginAnimateFireballHit(self: ClientCropManager, itemId: number, primaryElement: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local particleParent = FireballHit:Clone()
	particleParent:PivotTo(inst:GetPivot())
	utils.setPropertyTreeClassName(particleParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))

	particleParent.Parent = inst

	particleParent:FindFirstChild("FlashBurst1"):Emit(1)
	particleParent:FindFirstChild("ParticlesBurst50"):Emit(50)
	particleParent:FindFirstChild("RingBurst1"):Emit(1)

	utils.safelyDisposeOfParticleParent(particleParent)
end

function ClientCropManager.cleanupAnimateFireballHit(self: ClientCropManager, itemId: number)

end

function ClientCropManager.removeIndicators(self: ClientCropManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local modificationsConnect = indicatorData.modificationsConnect
	if modificationsConnect then
		modificationsConnect:Disconnect()
		indicatorData.modificationsConnect = nil
	end

	local animationEatChangedConnect = indicatorData.animationEatChangedConnect
	if animationEatChangedConnect then
		animationEatChangedConnect:Disconnect()
		indicatorData.animationEatChangedConnect = nil
	end

	local animationFireballHitChangedConnect = indicatorData.animationFireballHitChangedConnect
	if animationFireballHitChangedConnect then
		animationFireballHitChangedConnect:Disconnect()
		indicatorData.animationFireballHitChangedConnect = nil
	end

	local animationModificationsRemovedConnect = indicatorData.animationModificationsRemovedConnect
	if animationModificationsRemovedConnect then
		animationModificationsRemovedConnect:Disconnect()
		indicatorData.animationModificationsRemovedConnect = nil
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	-- as of 2026-august-11 these pass itemId; they were previously called with no argument,
	-- which made them silent no-ops
	self:cleanupAnimateEat(itemId)
	self:cleanupAnimateFireballHit(itemId)

	self.indicatorMap[itemId] = nil
end


-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientCropManager.notifyNewInstance(self: ClientCropManager, inst: any)
	-- we track modifications of all crops; only do grow complete time of our player's crops

	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	if self.indicatorMap[itemId] then
		print("already have crop", inst, itemId)
		return
	end

	local modificationsConnect = inst:GetAttributeChangedSignal(Attributes.MODIFICATIONS):Connect(
		function()
			-- as of 2026-august-11 this passes itemId; it previously passed the instance,
			-- which made updateExtraText a silent no-op
			self:updateExtraText(itemId)
		end
	)

	local animationEatChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_EAT):Connect(
		function()
			local animationEatStr = inst:GetAttribute(Attributes.ANIMATION_EAT)
			if animationEatStr then
				local iterFunc = string.gmatch(animationEatStr, "%S+")

				local particlePath = iterFunc() :: string
				local dragonX = tonumber(iterFunc())
				local dragonY = tonumber(iterFunc())
				local dragonZ = tonumber(iterFunc())
				local dragonPosition = Vector3.new(dragonX, dragonY, dragonZ)

				self:beginAnimateEat(itemId, particlePath, dragonPosition)
			else
				self:cleanupAnimateEat(itemId)
			end
		end
	)

	local animationFireballHitChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_FIREBALL_HIT):Connect(
		function()
			local animationFireballHitStr = inst:GetAttribute(Attributes.ANIMATION_FIREBALL_HIT)
			if animationFireballHitStr then
				local iterFunc = string.gmatch(animationFireballHitStr, "%S+")

				local primaryElement = tonumber(iterFunc()) :: number

				self:beginAnimateFireballHit(itemId, primaryElement)
			else
				self:cleanupAnimateFireballHit(itemId)
			end
		end
	)

	local animationModificationsRemovedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_MODIFICATIONS_REMOVED):Connect(
		function()
			local animationModificationsRemovedStr = inst:GetAttribute(Attributes.ANIMATION_MODIFICATIONS_REMOVED)
			if animationModificationsRemovedStr then
				local iterFunc = string.gmatch(animationModificationsRemovedStr, "%S+")

				local particleParentPaths = {}
				while true do
					local particleParentPath = iterFunc()
					if not particleParentPath then
						break
					end
					table.insert(particleParentPaths, particleParentPath)
				end

				self:beginAnimateModificationsRemoved(itemId, particleParentPaths)
			else
				-- nothing to do when removed, because we self-cleanup
			end
		end
	)

	self.indicatorMap[itemId] = {
		instance = inst,
		modificationsConnect = modificationsConnect,
		animationEatChangedConnect = animationEatChangedConnect,
		animationFireballHitChangedConnect = animationFireballHitChangedConnect,
		animationModificationsRemovedConnect = animationModificationsRemovedConnect,
		runConnect = nil,
	}

	-- as of 2026-august-11 this runs after the indicator-map insert and passes itemId; it
	-- previously ran before the insert with the instance, which made it a silent no-op
	self:updateExtraText(itemId)

	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item was made", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	local runConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			self:updateExtraText(itemId)
		end
	)

	self.indicatorMap[itemId].runConnect = runConnect

end

function ClientCropManager.notifyRemoveInstance(self: ClientCropManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	self:removeIndicators(itemId)
end

function ClientCropManager.getMapSize(self: ClientCropManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientCropManager.init(self: ClientCropManager)

	collectionService:GetInstanceAddedSignal(Tags.CROP):Connect(
		function(inst)
			--print("new crop exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CROP):Connect(
		function(inst)
			--print("crop is gone", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CROP) do
		--print("existing crop exists", inst)
		self:notifyNewInstance(inst)
	end

end

function ClientCropManager.new(): ClientCropManager
	local self = setmetatable({} :: ClientCropManagerFields, ClientCropManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientCropManager.new()

return singleton
