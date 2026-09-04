--!strict

local ClientShadowManager = {}
ClientShadowManager.__index = ClientShadowManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientAnalyticsManager = require("./ClientAnalyticsManager")
local Types = require("./Types")

local CLIENT_ITEM_TOOL_WELD_NAME = "ClientItemToolWeld"

local player = game:GetService("Players").LocalPlayer :: Player

type PartMap = Types.PartMap

type IndicatorData = {
	shadow: any, -- world shadow part; its shape only exists at runtime
	isOwnedByPlayer: boolean,
	caster: any, -- client-built ghost model
	casterTemplate: Model?,
	casterRecreatedEvent: BindableEvent?,
	runConnect: RBXScriptConnection?,
	cframeChangedConnect: RBXScriptConnection?,
	clientControlChangedConnect: RBXScriptConnection?,
}

type ClientShadowManagerFields = {
	partMaps: { [string]: PartMap },
	indicatorMap: { [number]: IndicatorData },
	shouldProcessOtherPlayerShadows: boolean,
}

export type ClientShadowManager = typeof(setmetatable({} :: ClientShadowManagerFields, ClientShadowManager))

function ClientShadowManager.setupDragonCaster(self: ClientShadowManager, shadow: any, caster: any)
	-- make everything in a dragon CanCollide = false
	for _, inst in (caster :: Model):GetDescendants() do
		if inst:IsA("BasePart") then
			--print("parent obj", obj, "making", inst, "cancollide false")
			inst.CanCollide = false
		end

		if inst:IsA("WeldConstraint") then
			-- force all welds we have to be enabled. As of 2026-april-20, for unknown reasons, a bunch of dragon welds
			-- just get disabled no matter what we do in studio
			inst.Enabled = true
		end
	end

	-- add antigravity constraints to all the parts so dragons basically hover
	for _, inst in (caster :: Model):GetDescendants() do
		if not inst:IsA("BasePart") then
			continue
		end

		--print("applying antigravity to", inst)
		local antigravity = Instance.new("VectorForce")
		antigravity.Name = Constants.ANTIGRAVITY_NAME
		antigravity.Force = Vector3.new(0, inst.Mass * workspace.Gravity, 0)
		local attachment = inst:FindFirstChildOfClass("Attachment")
		antigravity.Attachment0 = attachment
		antigravity.ApplyAtCenterOfMass = true
		antigravity.RelativeTo = Enum.ActuatorRelativeTo.World
		antigravity.Parent = inst
	end

	local particleParent: any = utils.findFirstDescendant(caster, "Particle_Emitter")
	if particleParent then
		particleParent.Transparency = 1
		particleParent:ClearAllChildren()
	end

	-- hide the trail
	local trail: any = utils.findFirstDescendant(caster, "Trail")
	if trail then
		trail.Enabled = false
	end

	if not self.partMaps[caster.Name] then
		local partMap = self:buildPartMap(caster.PrimaryPart, {})
		self.partMaps[caster.Name] = partMap
	end
end

function ClientShadowManager.buildPartMap(self: ClientShadowManager, part: any, tbl: Types.PartMap): Types.PartMap
	--print("looking at", part)
	for _, inst in part:GetChildren() do
		if not inst:IsA("BallSocketConstraint") then
			continue
		end

		if inst.Attachment0.Parent ~= part then
			warn("attachment0 not attached to us", part, inst, inst.Attachment0)
			continue
		end
		local nextPart = inst.Attachment1.Parent
		if not tbl[part.Name] then
			tbl[part.Name] = {}
		end
		tbl[part.Name][nextPart.Name] = (part.Position - nextPart.Position).Magnitude
		self:buildPartMap(nextPart, tbl)
	end

	return tbl
end

function ClientShadowManager.tryGetCasterTemplate(self: ClientShadowManager, path: any): Model?
	local inst = utils.getGameAssetPathReference(path)
	if not inst then
		return nil
	end

	if not inst:IsA("Model") then
		warn("all casters must be model; this one is not", inst, path)
		return nil
	end

	return inst
end

function ClientShadowManager.testCasterIntegrity(self: ClientShadowManager, caster: any): boolean
	if not self.partMaps[caster.Name] then
		warn("cannot test caster integrity when missing part map", caster)
		return true
	end

	local partMap = self.partMaps[caster.Name]
	for name1, tbl in partMap do
		local part1: any = utils.findFirstDescendant(caster, name1)
		if not part1 then
			-- these happen...
			print("caster missing part", name1)
			return false
		end

		for name2, originalDistance in tbl do
			local part2: any = utils.findFirstDescendant(caster, name2)
			if not part2 then
				-- these happen...
				print("caster missing part", name2)
				return false
			end

			local distance = ((part1.Position :: Vector3) - part2.Position).Magnitude
			if distance > originalDistance * 1.2 then
				--print("seems kinda far", caster, part1, part2, distance, originalDistance)
				return false
			end
		end
	end

	return true
end

function ClientShadowManager.testCasterIntegrityLoop(self: ClientShadowManager)
	while true do
		-- need to do a wait here in case there is nothing in indicatorMap--can't hog the cpu
		task.wait(0.05)
		for itemId, indicatorData in self.indicatorMap do
			if not self:testCasterIntegrity(indicatorData.caster) then
				print("recreating caster for shadow", itemId, indicatorData.caster)
				self:recreateCaster(itemId)
				clientAnalyticsManager:logEvent(clientAnalyticsManager.Events.RecreateShadowCaster,
					{
						objectName = indicatorData.shadow:GetAttribute(Attributes.MERGE_NAME),
					}
				)
			end
			task.wait(0.05)
		end
	end
end

function ClientShadowManager.recreateCaster(self: ClientShadowManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if not indicatorData.caster then
		warn("can't recreate caster when it doesn't already exist", itemId)
		return
	end

	indicatorData.caster:Destroy()

	self:createCaster(itemId)

	local casterRecreatedEvent = indicatorData.casterRecreatedEvent
	if casterRecreatedEvent then
		casterRecreatedEvent:Fire(indicatorData.caster)
	end

end

function ClientShadowManager.createCaster(self: ClientShadowManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local shadow = indicatorData.shadow
	-- set before createCaster is ever called; the cast records that
	local casterTemplate = indicatorData.casterTemplate :: Model

	local caster: any = casterTemplate:Clone()

	if shadow:HasTag(Tags.SHADOW_DRAGON) then
		self:setupDragonCaster(shadow, caster)
	end

	caster.PrimaryPart.Anchored = true
	utils.setPropertyTreeBaseParts(caster, "CanCollide", false)
	caster:SetAttribute(Attributes.ITEM_ID, itemId)
	caster:SetAttribute(Attributes.USER_ID, shadow:GetAttribute(Attributes.USER_ID))
	caster:PivotTo(shadow:GetPivot())

	caster.Parent = shadow.Parent

	indicatorData.caster = caster
end

function ClientShadowManager.setupCasterForHolding(self: ClientShadowManager, model: any)
	local part = model.PrimaryPart

	-- weld all the parts to the primary part so they are seen if the player holds the item
	for _, inst in (model :: Model):GetChildren() do
		if not inst:IsA("BasePart") then
			continue
		end

		inst.Massless = true

		if inst == part then
			continue
		end

		--xxx hack, do this better
		if inst.Name == "Wing_Left" or inst.Name == "Wing_Right" then
			continue
		end

		--print("welding", part, inst)
		local weld = Instance.new("WeldConstraint")
		weld.Name = CLIENT_ITEM_TOOL_WELD_NAME
		weld.Part0 = part
		weld.Part1 = inst
		weld.Parent = part
	end
end


function ClientShadowManager.removeIndicators(self: ClientShadowManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	local cframeChangedConnect = indicatorData.cframeChangedConnect
	if cframeChangedConnect then
		cframeChangedConnect:Disconnect()
		indicatorData.cframeChangedConnect = nil
	end

	local clientControlChangedConnect = indicatorData.clientControlChangedConnect
	if clientControlChangedConnect then
		clientControlChangedConnect:Disconnect()
		indicatorData.clientControlChangedConnect = nil
	end

	local casterRecreatedEvent = indicatorData.casterRecreatedEvent
	if casterRecreatedEvent then
		casterRecreatedEvent:Destroy()
		indicatorData.casterRecreatedEvent = nil
	end

	indicatorData.caster:Destroy()

	self.indicatorMap[itemId] = nil
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
-- note that this means no shadow is actually ever moved from backpack <> ground--we get different calls here each time
function ClientShadowManager.notifyNewInstance(self: ClientShadowManager, shadow: any)
	--print("client shadow manager notify new instance", shadow)

	local isOwnedByPlayer
	if shadow:GetAttribute(Attributes.USER_ID) == player.UserId then
		isOwnedByPlayer = true
	else
		isOwnedByPlayer = false
		--print("someone else's shadow, we support this now, player", shadow, shadow:GetAttribute(Attributes.USER_ID))
		if not self.shouldProcessOtherPlayerShadows then
			return
		end

	end

	local itemId = shadow:GetAttribute(Attributes.ITEM_ID)

	if self.indicatorMap[itemId] then
		--print("already have shadow", shadow, itemId)
		return
	end

	if shadow.Parent ~= workspace and not shadow:GetAttribute(Attributes.EQUIP) then
		--print("unequippable item not in workspace can be ignored shadow-wise since it will never be visible")
		return
	end

	-- ok what do we want to do for each shadow
	-- create a model based on a name in an attribute
	-- place the model in the inst's location
	-- listen for the inst's cframe changes, echo that to the model

	local indicatorData: IndicatorData = {
		shadow = shadow,
		isOwnedByPlayer = isOwnedByPlayer,
		caster = nil,
		casterRecreatedEvent = Instance.new("BindableEvent"),
	}

	self.indicatorMap[itemId] = indicatorData

	local casterPath = shadow:GetAttribute(Attributes.CASTER_PATH)

	--print("have caster path", casterPath)

	local casterTemplate = self:tryGetCasterTemplate(casterPath)
	if not casterTemplate then
		warn("unable to make caster for shadow", shadow)
		self.indicatorMap[itemId] = nil
		return
	end

	indicatorData.casterTemplate = casterTemplate

	self:createCaster(itemId)

	local caster = indicatorData.caster

	local runConnect

	if shadow.Parent ~= workspace then
		--print("shadow is not in workspace, setting it up for holding")
		self:setupCasterForHolding(caster)

		-- welding the caster to the player or shadow causes crazy problems (player flying around the world)
		-- instead, we just move it in place each frame
		runConnect = runService.PostSimulation:Connect(
			function()
				local currentIndicatorData = self.indicatorMap[itemId]
				if not currentIndicatorData then
					return
				end

				local currentShadow = currentIndicatorData.shadow
				local currentCaster = currentIndicatorData.caster
				if currentShadow.Parent and currentShadow.Parent:IsA("Tool") and currentShadow.Parent.Parent == (player :: any).Backpack then
					-- make it go away, because it'll become visible for one frame in this position when getting equipped
					currentCaster:PivotTo(CFrame.identity)
					return
				end

				currentCaster:PivotTo(currentShadow:GetPivot())
			end
		)
		indicatorData.runConnect = runConnect

	end

	-- if server moves our shadow, we move the caster to match it (if client isn't in control)
	local cframeChangedConnect = shadow:GetPropertyChangedSignal("CFrame"):Connect(
		function()
			local currentIndicatorData = self.indicatorMap[itemId]
			if not currentIndicatorData then
				return
			end

			local currentShadow = currentIndicatorData.shadow
			local currentCaster = currentIndicatorData.caster

			-- ok, so... these attribute changes come down from the server in a separate "channel" compared to physics/position updates,
			-- so there might be more position updates that the server already applied that we haven't received yet
			-- likely fix is to send current cframe in this attribute change xxx
			if currentShadow:GetAttribute(Attributes.CLIENT_CONTROL) and isOwnedByPlayer then
				return
			end

			if currentShadow.Parent ~= workspace then
				-- if being held by player (directly or backpack), then that's taken care of in runConnect, so don't do anything here
				return
			end

			currentCaster:PivotTo(currentShadow:GetPivot())
		end
	)

	indicatorData.cframeChangedConnect = cframeChangedConnect

end

function ClientShadowManager.notifyRemoveInstance(self: ClientShadowManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)
	self:removeIndicators(itemId)
end

function ClientShadowManager.isShadow(self: ClientShadowManager, itemId: number): boolean
	return self.indicatorMap[itemId] ~= nil
end

function ClientShadowManager.getShadow(self: ClientShadowManager, itemId: number): any
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return nil
	end

	return indicatorData.shadow
end

function ClientShadowManager.getCaster(self: ClientShadowManager, itemId: number): any
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return nil
	end

	return indicatorData.caster
end

function ClientShadowManager.getCasterRecreatedEvent(self: ClientShadowManager, itemId: number): RBXScriptSignal?
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return nil
	end

	local casterRecreatedEvent = indicatorData.casterRecreatedEvent
	if not casterRecreatedEvent then
		return nil
	end

	-- as of 2026-august-11 this returns .Event; it previously read .event (lowercase), which
	-- is not a member of BindableEvent and would have thrown if this method were ever called
	return casterRecreatedEvent.Event
end

function ClientShadowManager.setShouldProcessOtherPlayerShadows(self: ClientShadowManager, shouldProcess: boolean)
	self.shouldProcessOtherPlayerShadows = shouldProcess

	if self.shouldProcessOtherPlayerShadows then
		for _, inst in collectionService:GetTagged(Tags.SHADOW) do
			--print("rechecking existing shadow", inst)
			self:notifyNewInstance(inst)
		end
	else
		for itemId, indicatorData in self.indicatorMap do
			if indicatorData.isOwnedByPlayer then
				continue
			end

			self:removeIndicators(itemId)
		end
	end

end

function ClientShadowManager.setShowShadows(self: ClientShadowManager, showShadows: boolean)
	for _, shadow in utils.getAllDescendantsByName(workspace, "Shadow") do
		if not shadow:IsA("BasePart") then
			continue
		end
		shadow.Transparency = showShadows and 0 or 1
	end
end

function ClientShadowManager.recreateAllCasters(self: ClientShadowManager)
	for itemId, indicatorData in self.indicatorMap do
		self:recreateCaster(itemId)
	end
end

function ClientShadowManager.getMapSize(self: ClientShadowManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientShadowManager.init(self: ClientShadowManager)

	collectionService:GetInstanceAddedSignal(Tags.SHADOW):Connect(
		function(inst)
			--print("new shadow", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.SHADOW):Connect(
		function(inst)
			--print("remove shadow", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.SHADOW) do
		--print("existing shadow", inst)
		self:notifyNewInstance(inst)
	end

	task.spawn(
		function()
			self:testCasterIntegrityLoop()
		end
	)
end

function ClientShadowManager.new(): ClientShadowManager
	local self = setmetatable({} :: ClientShadowManagerFields, ClientShadowManager)

	-- maps from caster name to
	--   map of part name, to second part name, to distance between those two parts
	-- for every pair of parts connected by a ball-socket constraint
	self.partMaps = {}

	self.indicatorMap = {}

	self.shouldProcessOtherPlayerShadows = true

	return self
end


local singleton = ClientShadowManager.new()

return singleton
