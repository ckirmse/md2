--!strict

local ClientPickupController = {}
ClientPickupController.__index = ClientPickupController

local userInputService = game:GetService("UserInputService")

local collectionService = game:GetService("CollectionService")

local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the audio template's shape only exists in Studio, so it is untyped here
local PickupAudioParent: any = Effects:WaitForChild("PickupAudioParent")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientRideController = require("./ClientRideController")
local TargetBase = require("./TargetBase")
local clientMergeController = require("./ClientMergeController")
local clientShadowManager = require("./ClientShadowManager")

local MAX_PICKUP_DISTANCE = Constants.PICKUP_DISTANCE
local HIGHLIGHT_NAME = "PickupHighlight"

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	shadow: any, -- world shadow instance; its shape only exists at runtime
	caster: any,
	isClosest: boolean,
	highlight: Highlight?,
	targetBase: TargetBase.TargetBase?,
	casterRecreatedEventConnect: RBXScriptConnection?,
}

type ClientPickupControllerFields = {
	indicatorMap: { [number]: IndicatorData },
	targetBase: any?,
	audioPickup: any,
	audioPickupDragon: any,
}

export type ClientPickupController = typeof(setmetatable({} :: ClientPickupControllerFields, ClientPickupController))

function ClientPickupController.configureIndicators(self: ClientPickupController, itemId: number, canPickup: boolean)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local caster = indicatorData.caster
	local shadow = indicatorData.shadow

	if shadow.Parent ~= workspace then
		-- there's race conditions with the server where this is possible
		return
	end

	local highlight = indicatorData.highlight

	-- need to update this constantly because the item can move (if it's a small dragon)
	local part
	if caster:IsA("Model") then
		part = caster.PrimaryPart
		if not part then
			-- this happens with Seed_Green_Common and others often enough as of 2026-april-27... but HOW?!? xxx
			-- ok, 2026-may-5 info--if a model is destroyed, its PrimaryPart is set to nil. So clearly that's what is happening. Totally fine
			-- to happen here, as there are races with this called all the time and when we're told about destruction
			return
		end
	else
		part = caster
	end

	-- as of 2026-august-12 this calls GetPivot; it previously called getPivot (lowercase),
	-- which is not a member and would have thrown here
	local position = shadow:GetPivot().Position
	local groundHeight = utils.getGroundHeight(position.X, position.Z) or 0
	(indicatorData.targetBase :: TargetBase.TargetBase):setPosition(Vector3.new(position.X, groundHeight, position.Z));

	(highlight :: Highlight).Enabled = canPickup
end

function ClientPickupController.configureIsClosest(self: ClientPickupController, itemId: number, isClosest: boolean)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if isClosest == indicatorData.isClosest then
		return
	end

	local targetBase = indicatorData.targetBase :: TargetBase.TargetBase
	if isClosest then
		--print("pickup item now closest", itemId)
		targetBase:animateShow()
	else
		targetBase:animateHide()
		--print("pickup item now not closest", itemId)
	end

	indicatorData.isClosest = isClosest
end

function ClientPickupController.tryPickup(self: ClientPickupController, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	--print("try pickup", itemId)

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

	if caster.Parent ~= workspace then
		print("ignoring click when not in workspace, shouldn't be possible")
		return
	end

	RemoteEvents.TryPickupItem:FireServer(itemId)

	if shadow:HasTag(Tags.SHADOW_DRAGON) then
		self.audioPickupDragon:Play()
	else
		self.audioPickup:Play()
	end
end

function ClientPickupController.notifyRemoveIndicators(self: ClientPickupController, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local highlight = indicatorData.highlight
	if highlight then
		highlight:Destroy()
		indicatorData.highlight = nil
	end

	local targetBase = indicatorData.targetBase
	if targetBase then
		targetBase:destroy()
		indicatorData.targetBase = nil
	end

	local casterRecreatedEventConnect = indicatorData.casterRecreatedEventConnect
	if casterRecreatedEventConnect then
		casterRecreatedEventConnect:Disconnect()
		indicatorData.casterRecreatedEventConnect = nil
	end


	self.indicatorMap[itemId] = nil
end

function ClientPickupController.createHighlight(self: ClientPickupController, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		-- this can happen post merge
		return
	end

	local shadow = indicatorData.shadow
	local caster = indicatorData.caster

		local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Enabled = false
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = utils.getColorForRarity(shadow:GetAttribute(Attributes.RARITY))
	highlight.OutlineTransparency = 0.1
	highlight.Parent = caster

	indicatorData.highlight = highlight
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientPickupController.notifyNewInstance(self: ClientPickupController, shadow: any, caster: any)
	if shadow:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's item was made", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	--print("pickupable", shadow, inst)

	local itemId = shadow:GetAttribute(Attributes.ITEM_ID)

	if self.indicatorMap[itemId] then
		--print("pickup controller already hooked up", shadow, inst, "ignoring")
		return
	end

	--print("new instance--hooking to pickup", inst)

	self.indicatorMap[itemId] = {
		shadow = shadow,
		caster = caster,
		isClosest = false,
		highlight = nil,
		targetBase = nil,
	}

	local indicatorData = self.indicatorMap[itemId]

	-- draw an outline around an object when tapping/clicking on it will pick it up

	self:createHighlight(itemId)

	-- draw a circle on the ground underneath the item, also to allow easier picking up with tap/click

	indicatorData.targetBase = TargetBase.new(shadow, shadow:GetAttribute(Attributes.SIZE))

	if clientShadowManager:isShadow(itemId) then
		indicatorData.casterRecreatedEventConnect = (clientShadowManager:getCasterRecreatedEvent(itemId) :: RBXScriptSignal):Connect(
			function(newCaster)
				indicatorData.caster = newCaster

				local highlight = indicatorData.highlight
				if highlight then
					highlight:Destroy()
					indicatorData.highlight = nil
				end

				self:createHighlight(itemId)
			end
		)
	end
end

function ClientPickupController.getMapSize(self: ClientPickupController): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientPickupController.getEnabledPickupableCount(self: ClientPickupController): number
	local count = 0
	for _, indicatorData in self.indicatorMap do
		if (indicatorData.highlight :: Highlight).Enabled then
			count += 1
		end
	end
	return count
end

-- position passed in should be a 2d position
function ClientPickupController.handleClick(self: ClientPickupController, position: Vector2?)
	if not clientMergeController:isIdle() then
		-- no picking up/dropping while merge is in any sort of state
		return
	end

	local tool = utils.getHoldingToolWithHandle(player)

	--print("handleClick", position)

	-- this could let a player pick up an item of the same type they are already holding, though not doing that
	local hasClosest = false
	for itemId, indicatorData in self.indicatorMap do
		if indicatorData.isClosest then
			hasClosest = true
			break
		end
	end

	if tool then
		--print("activating tool")
		tool:Activate()
	else
		if hasClosest then
			--print("click while have closest")
			local itemId: any
			if position then
				local camera = workspace.CurrentCamera
				local unscaledRay = camera:ViewportPointToRay(position.X, position.Y)
				local cameraPosition = unscaledRay.Origin
				local direction = unscaledRay.Direction

				-- start looking a little in front of the camera--when in first-person mode, you otherwise always just see the player

				local origin = cameraPosition

				local raycastParams = RaycastParams.new()
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude
				raycastParams.FilterDescendantsInstances = {(player.Character :: any) :: Instance}

				local result = workspace:Raycast(origin, direction * 1000, raycastParams)
				if not result then
					return
				end
				--print("found", result, result.Instance)
				local inst: any = result.Instance
				while inst ~= nil do
					itemId = inst:GetAttribute(Attributes.ITEM_ID)
					if itemId then
						break
					end
					--print("in ancestry", inst)
					if inst:IsA("Highlight") and inst.Adornee then
						inst = inst.Adornee
					else
						inst = inst.Parent
					end
				end
			end

			if itemId then
				--print("picking up item if possible", itemId)
				local indicatorData = self.indicatorMap[itemId]
				if indicatorData then
					--print("found indicator data")
					if (indicatorData.highlight :: Highlight).Enabled then
						--print("trying to pick up")
						self:tryPickup(itemId)
						return
					end
				end
			end
		end
		--print("doing nothing")
	end
end

function ClientPickupController.init(self: ClientPickupController)
	--print("listening to new pickupables")
	collectionService:GetInstanceAddedSignal(Tags.PICKUPABLE):Connect(
		function(inst: any)
			--print("got a new pickupable", inst)

			local shadow, caster

			local itemId = inst:GetAttribute(Attributes.ITEM_ID)
			if clientShadowManager:isShadow(itemId) then
				shadow = inst
				caster = clientShadowManager:getCaster(itemId)
			else
				shadow = inst
				caster = inst
			end

			self:notifyNewInstance(shadow, caster)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.PICKUPABLE):Connect(
		function(inst: any)
			--print("item no longer pickupable", inst)
			local itemId = inst:GetAttribute(Attributes.ITEM_ID)
			self:notifyRemoveIndicators(itemId)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.PICKUPABLE) :: { any } do
		--print("starting with pickupable", inst)

		local shadow, caster

		local itemId = inst:GetAttribute(Attributes.ITEM_ID)
		if clientShadowManager:isShadow(itemId) then
			shadow = inst
			caster = clientShadowManager:getCaster(itemId)
		else
			shadow = inst
			caster = inst
		end

		self:notifyNewInstance(shadow, caster)
	end

	runService.PostSimulation:Connect(
		function(deltaTime)
			-- find closest item
			-- anything "close enough" gets a highlight and can be picked up, but only closest one gets a circle underneath
			local tool: any = utils.getHoldingToolWithHandle(player)
			local isToolEquipped = tool ~= nil

			local isRiding = clientRideController:isRiding()
			local bestItemId = nil
			local bestDistance: number? = nil
			for itemId, indicatorData in self.indicatorMap do
				local shadow = indicatorData.shadow
				-- the character rig's children only exist at runtime, so they are untyped here
				local playerPosition = (player.Character :: any).HumanoidRootPart.Position
				-- as of 2026-august-12 this calls GetPivot (lowercase getPivot is not a member)
				local shadowPosition = shadow:GetPivot().Position
				local distance = utils.getMagnitudeXZ(playerPosition - shadowPosition)
				local canPickup = false
				--[[
				if heldItemName and shadow:GetAttribute(Attributes.PICKUP_NAME) == heldItemName then
					--print("can pickup item because player is holding item of same exact type", heldItemName, shadow)
					canPickup = true
				end
				]]
				if not isRiding and not isToolEquipped and distance < MAX_PICKUP_DISTANCE then
					--print("can pickup because player is not riding or holding anything and close enough", shadow)
					canPickup = true
				end

				if canPickup then
					if not bestDistance or distance < bestDistance then
						bestItemId = itemId
						bestDistance = distance
					end
				end
				self:configureIndicators(itemId, canPickup)
			end
			--print("closest pickup item is", bestItemId)
			for itemId, indicatorData in self.indicatorMap do
				local isClosest = (itemId == bestItemId)

				self:configureIsClosest(itemId, isClosest)
			end
		end
	)

	userInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			-- support gamepad picking up/dropping items with R2 button
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				self:handleClick(nil)
			end

			-- handle mouse clicks for pick up/drop
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if gameProcessed then
					return
				end

				self:handleClick(userInputService:GetMouseLocation())
			end

		end
	)

	userInputService.TouchTapInWorld:Connect(
		function(position: Vector2, processedByUI: boolean)
			if processedByUI then
				return
			end

			-- handle touch taps for pick up/drop
			self:handleClick(position)
		end
	)

end

function ClientPickupController.new(): ClientPickupController
	local self = setmetatable({} :: ClientPickupControllerFields, ClientPickupController)

	self.indicatorMap = {}

	self.targetBase = nil

	local pickupAudioParent = PickupAudioParent:Clone()
	pickupAudioParent.Parent = workspace

	self.audioPickup = pickupAudioParent:FindFirstChild("AudioPickup")
	self.audioPickupDragon = pickupAudioParent:FindFirstChild("AudioPickupDragon")

	return self
end

local singleton = ClientPickupController.new()

return singleton
