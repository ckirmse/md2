--!strict

local ClientMutationManager = {}
ClientMutationManager.__index = ClientMutationManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Mutations = GameAssets:WaitForChild("Mutations")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientShadowManager = require("./ClientShadowManager")

local SURFACE_APPEARANCE_NAME = "MutationSurface"

local FAST_CYCLE_SEC = 1
local SLOW_CYCLE_SEC = 4

type IndicatorData = {
	instance: any, -- world shadow/crop instance; its shape only exists at runtime
	caster: any, -- caster model for shadows, otherwise the instance itself
	mutationChangedConnect: RBXScriptConnection?,
	runConnect: RBXScriptConnection?,
	normalMutationProperties: { [any]: { [string]: any } }?,
	colors: { Color3 }?,
	perColorSec: number?,
	colorIndex: number?,
	colorTime: number?,
}

type ClientMutationManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientMutationManager = typeof(setmetatable({} :: ClientMutationManagerFields, ClientMutationManager))

function ClientMutationManager.tryFindPart(self: ClientMutationManager, itemId: number): any
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return nil
	end

	local caster = indicatorData.caster
	local inst = indicatorData.instance

	local part
	if caster:IsA("Model") then
		part = caster.PrimaryPart
		if not part then
			part = utils.tryGetHandleForModel(caster)
		end
	else
		part = inst
	end

	-- could still be nil
	return part
end

function ClientMutationManager.removeConnections(self: ClientMutationManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

end

function ClientMutationManager.getAllSurfaceAppearances(self: ClientMutationManager, itemId: number): { any }
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return {}
	end

	local caster = indicatorData.caster

	local part = self:tryFindPart(itemId)
	if not part then
		-- this can happen when held by other player, particularly soon after creation (merge)
		return {}
	end

	local surfaceAppearances
	if not part or part.Parent == caster then
		surfaceAppearances = utils.getAllDescendantsByName(caster, SURFACE_APPEARANCE_NAME)
	else
		surfaceAppearances = utils.getAllDescendantsByName(part, SURFACE_APPEARANCE_NAME)

	end

	return surfaceAppearances :: { any }
end


function ClientMutationManager.removeSurfaceAppearances(self: ClientMutationManager, itemId: number)
	local surfaceAppearances = self:getAllSurfaceAppearances(itemId)
	--print("got surfaceAppearances to remove", surfaceAppearances)
	for _, surfaceAppearance in surfaceAppearances do
		surfaceAppearance:Destroy()
	end
end

function ClientMutationManager.ensureSurfaceAppearancesIfNeeded(self: ClientMutationManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- as of 2026-april-11, surface appearances (colormap specifically) often draw as black on mobile, so not doing this
	if true then return end

	local shadow = indicatorData.instance
	local caster = indicatorData.caster

	local part = self:tryFindPart(itemId)
	if not part then
		-- this can happen when held by other player, particularly soon after creation (merge)
		return
	end

	local mutationSurfaceAppearanceName = shadow:GetAttribute(Attributes.MUTATION_SURFACE_APPEARANCE_NAME)
	if not mutationSurfaceAppearanceName then
		-- not all items have this; dragons do, plants don't as of 2026-february-18
		--print("item missing mutation surface appearance name", caster)
		return
	end

	local surfaceAppearanceTemplate: any = utils.findFirstDescendant(Mutations, mutationSurfaceAppearanceName)
	if not surfaceAppearanceTemplate then
		print("item has mutation surface name", caster, mutationSurfaceAppearanceName, "but surface appearance not found")
		return
	end

	local checkParts
	if part.Parent == caster then
		checkParts = caster:GetDescendants()
	else
		-- when being held
		checkParts = part:GetDescendants()
		table.insert(checkParts, part)
	end

	for _, obj in checkParts :: { any } do
		if not obj:IsA("MeshPart") then
			continue
		end
		-- xxx hack, should mark this better
		if obj.Name == "Saddle" then
			continue
		end

		-- parts that will get set with no texture and neon shouldn't get a surface appearance
		if obj:GetAttribute(Attributes.MUTATION_TARGET) == true then
			continue
		end

		local surfaceAppearance = obj:FindFirstChild(SURFACE_APPEARANCE_NAME)
		if not surfaceAppearance then
			surfaceAppearance = surfaceAppearanceTemplate:Clone()
			surfaceAppearance.Name = SURFACE_APPEARANCE_NAME
			surfaceAppearance.Parent = obj
		end

	end
end

function ClientMutationManager.getMutationParts(self: ClientMutationManager, itemId: number): { any }?
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return nil
	end

	local caster = indicatorData.caster

	local part = self:tryFindPart(itemId)
	if not part then
		-- this can happen when held by other player, particularly soon after creation (merge)
		return nil
	end

	-- if item is currently being held, we need to go through the primary part because the model is split off
	local mutationParts
	if caster:IsA("Model") and part and part.Parent ~= caster then
		mutationParts = utils.getAllDescendantsWithAttribute(part, Attributes.MUTATION_TARGET, true)
		if part:GetAttribute(Attributes.MUTATION_TARGET) == true then
			table.insert(mutationParts, part)
		end
		--print("got parts while holding", part, mutationParts)
	else
		mutationParts = utils.getAllDescendantsWithAttribute(caster, Attributes.MUTATION_TARGET, true)
		--print("got parts from caster", caster, mutationParts)
	end

	return mutationParts :: { any }
end

function ClientMutationManager.setMutationTargetsToMaterialAndColor(self: ClientMutationManager, itemId: number, material: Enum.Material, color: Color3)
	--print("setting", itemId, material, color)

	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local mutationParts = self:getMutationParts(itemId)

	-- back up the "normal" mutation properties if we haven't done it before
	if not indicatorData.normalMutationProperties then
		--print("saving normal mutation parts for", itemId)
		local normalMutationProperties: { [any]: { [string]: any } } = {}
		indicatorData.normalMutationProperties = normalMutationProperties
		if mutationParts then
			for _, mutationPart in mutationParts do
				normalMutationProperties[mutationPart] = {
					Material = mutationPart.Material,
					Color = mutationPart.Color,
				}
				if mutationPart:IsA("MeshPart") then
					normalMutationProperties[mutationPart].TextureID = mutationPart.TextureID
				end
			end
		end
	end

	if mutationParts then
		for _, mutationPart in mutationParts do
			mutationPart.Material = Enum.Material.Neon
			mutationPart.Color = color
			if mutationPart:IsA("MeshPart") then
				mutationPart.TextureID = ""
			end
		end
	end

end

function ClientMutationManager.setupNormalMutation(self: ClientMutationManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	self:removeSurfaceAppearances(itemId)

	local normalMutationProperties = indicatorData.normalMutationProperties
	if normalMutationProperties then
		--print("restoring normal mutation parts for", itemId)
		for mutationPart, properties in normalMutationProperties do
			for key, value in properties do
				mutationPart[key] = value
			end
		end
		indicatorData.normalMutationProperties = nil
	end
end

function ClientMutationManager.setupStaticMutation(self: ClientMutationManager, itemId: number, color: Color3)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	self:ensureSurfaceAppearancesIfNeeded(itemId)

	local surfaceAppearances = self:getAllSurfaceAppearances(itemId)
	--print("setting up static mutation", itemId, color, #surfaceAppearances, indicatorData.caster)
	for _, surfaceAppearance in surfaceAppearances do
		surfaceAppearance.Color = color
		surfaceAppearance.EmissiveTint = color
	end

	self:setMutationTargetsToMaterialAndColor(itemId, Enum.Material.Neon, color)
end

function ClientMutationManager.setupCyclingMutation(self: ClientMutationManager, itemId: number, colors: { Color3 }, perColorSec: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- as of 2026-august-11 this checks indicatorData.runConnect; it previously checked
	-- self.runConnect, which is never assigned, so the guard could never trigger
	if indicatorData.runConnect then
		-- mutations need to be reenabled sometimes, because server replicates datamodel of crops from the server, etc.
		-- so if we're already setting things every frame, leave it alone
		return
	end

	self:ensureSurfaceAppearancesIfNeeded(itemId)

	local surfaceAppearances = self:getAllSurfaceAppearances(itemId)

	local random = Random.new()

	indicatorData.colors = colors
	indicatorData.perColorSec = perColorSec
	indicatorData.colorIndex = random:NextInteger(1, #colors)
	indicatorData.colorTime = random:NextNumber(0, perColorSec)

	indicatorData.runConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			local currentColors = indicatorData.colors :: { Color3 }
			local currentPerColorSec = indicatorData.perColorSec :: number
			local colorTime = (indicatorData.colorTime :: number) + deltaTime
			local colorIndex = indicatorData.colorIndex :: number
			while colorTime > currentPerColorSec do
				colorTime -= currentPerColorSec
				colorIndex = (colorIndex % #currentColors) + 1
			end
			indicatorData.colorTime = colorTime
			indicatorData.colorIndex = colorIndex

			local currentColor = currentColors[colorIndex]
			local nextColorIndex = (colorIndex % #currentColors) + 1
			local nextColor = currentColors[nextColorIndex]
			local color = currentColor:Lerp(nextColor, colorTime / currentPerColorSec)

			for _, surfaceAppearance in surfaceAppearances do
				surfaceAppearance.Color = color
				surfaceAppearance.EmissiveTint = color
			end

			self:setMutationTargetsToMaterialAndColor(itemId, Enum.Material.Neon, color)
		end
	)
end

function ClientMutationManager.setupMutation(self: ClientMutationManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local shadow = indicatorData.instance

	local mutation = shadow:GetAttribute(Attributes.MUTATION)

	if not mutation or mutation == enums.Mutations.NORMAL then
		self:setupNormalMutation(itemId)
	else
		local colors = utils.getColorsForMutation(mutation)
		if #colors == 1 then
			self:setupStaticMutation(itemId, colors[1])
		else
			if utils.isMutationFastCycle() then
				self:setupCyclingMutation(itemId, colors, FAST_CYCLE_SEC)
			else
				self:setupCyclingMutation(itemId, colors, SLOW_CYCLE_SEC)
			end
		end
	end
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientMutationManager.notifyNewInstance(self: ClientMutationManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	-- don't create one if we already have one
	if self.indicatorMap[itemId] then
		return
	end

	local caster

	if clientShadowManager:isShadow(itemId) then
		caster = clientShadowManager:getCaster(itemId)
	else
		caster = inst
	end

	self.indicatorMap[itemId] = {
		instance = inst,
		caster = caster,
	}

	local mutationChangedConnect = inst:GetAttributeChangedSignal(Attributes.MUTATION):Connect(
		function()
			self:removeConnections(itemId)
			self:setupMutation(itemId)
		end
	)

	self:setupMutation(itemId)

	self.indicatorMap[itemId].mutationChangedConnect = mutationChangedConnect

	inst:GetPropertyChangedSignal("Parent"):Connect(
		function()
			-- server just overwrote properties of the model (if it's a crop), so reenable them
			self:setupMutation(itemId)
		end
	)

end

function ClientMutationManager.notifyRemoveInstance(self: ClientMutationManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local mutationChangedConnect = indicatorData.mutationChangedConnect
	if mutationChangedConnect then
		mutationChangedConnect:Disconnect()
		indicatorData.mutationChangedConnect = nil
	end

	-- as of 2026-august-11 this passes itemId; it was previously called with no argument,
	-- which made it a silent no-op and leaked the run connection
	self:removeConnections(itemId)

	self.indicatorMap[itemId] = nil
end

function ClientMutationManager.getMapSize(self: ClientMutationManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientMutationManager.init(self: ClientMutationManager)

	collectionService:GetInstanceAddedSignal(Tags.CROP):Connect(
		function(inst)
			--print("new crop", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CROP):Connect(
		function(inst)
			--print("crop no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)


	collectionService:GetInstanceAddedSignal(Tags.SHADOW_DRAGON):Connect(
		function(inst)
			--print("new dragon", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.SHADOW_DRAGON):Connect(
		function(inst)
			--print("dragon no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CROP) do
		--print("existing crop", inst)
		self:notifyNewInstance(inst)
	end

	for _, inst in collectionService:GetTagged(Tags.SHADOW_DRAGON) do
		--print("existing dragon", inst)
		self:notifyNewInstance(inst)
	end

end

function ClientMutationManager.new(): ClientMutationManager
	local self = setmetatable({} :: ClientMutationManagerFields, ClientMutationManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientMutationManager.new()

return singleton
