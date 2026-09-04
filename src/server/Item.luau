--!strict

local Item = {}
Item.__index = Item

local playersService = game:GetService("Players")
local tweenService = game:GetService("TweenService")

local Types = require("./Types")
local contextualFtueManager = require("./ContextualFtueManager")
local ftueManager = require("./FtueManager")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local indexManager = require("./IndexManager")
local objectDataStore = require("./ObjectDataStore")
local plotsManager = require("./PlotsManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local DevTools = GameAssets:WaitForChild("DevTools")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToIndependentTween = require("@game/ReplicatedStorage/Shared/PivotToIndependentTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local Billboard = DevTools:WaitForChild("Billboard") :: BillboardGui


export type Repulsor = Types.Repulsor
export type ItemFields = Types.ItemFields
export type Item = Types.Item

-- part of the base item contract: subclasses that settle override this
function Item.setPreventSettling(self: Item)
end

-- part of the base item contract: subclasses override to veto pickup
function Item.canBePickedUp(self: Item): boolean
	return true
end

function Item.getDataDumpString(self: Item): string
	local text = self.itemName .. " (" .. tostring(self.itemId) .. ") user " .. self.userId

	return text
end

function Item.updateDataDump(self: Item)
	if not self:getPart() then
		return
	end

	local billboard = self:getPart():FindFirstChild("Billboard")
	if not billboard then
		return
	end

	local textLabel = billboard:FindFirstChild("TextLabel")
	local text = self:getDataDumpString()
	textLabel.Text = text
end

function Item.resetBillboard(self: Item)
	local billboard = self:getPart():FindFirstChild("Billboard")
	if itemManager:getUseBillboards() then
		if not billboard then
			local newBillboard = Billboard:Clone()
			newBillboard.Parent = self:getPart()
			newBillboard.StudsOffset = Vector3.new(0, 4 + self:getPart().Size.Y / 2, 0)
		end

		self:updateDataDump()
	else
		if billboard then
			billboard:Destroy()
		end
	end
end

function Item.calculateSettleOnGroundStep(self: Item, basePosition: Vector3, repulsors: { Repulsor }): Vector3?
	-- figure out if we need to move the item from where it currently is

	local impulse = Vector3.zero
	local itemOverlapCount = 0

	for _, repulsor in repulsors do
		local direction = Vector3.new(basePosition.X - repulsor.position.X, 0, basePosition.Z - repulsor.position.Z)
		-- using 3d distance so dragons high in the air don't affect plants on ground
		local distance = (basePosition - repulsor.position).Magnitude
		local combinedSpacing = self:getItemData().boardSpacing + repulsor.boardSpacing
		if distance > combinedSpacing then
			continue
		end
		--print("direction is", direction, "distance", distance)

		impulse += direction
		itemOverlapCount += 1
	end

	if itemOverlapCount == 0 then
		return nil
	end

	return impulse
end

function Item.getSettlePositionForLocation(self: Item, location: Vector3): Vector3
	local groundPosition = utils.getGroundPositionForLocation(location)
	local position = groundPosition + Vector3.new(0, self.part.Size.Y / 2, 0)

	return position
end

function Item.getSettleCFrameForPosition(self: Item, position: Vector3): CFrame
	-- default is to maintain current rotation
	local finalRotation = utils.getCFrameParallelToGround(self.obj:GetPivot().Rotation)
	local finalCFrame = finalRotation + position

	return finalCFrame
end

function Item.getSettleDurationForPosition(self: Item, position: Vector3): number
	local random = Random.new()
	local distance = (position - self.obj:GetPivot().Position).Magnitude
	local duration = math.max(0.3, distance * 0.05) + random:NextNumber(-0.2, 0.5)

	return duration
end

function Item.createSettleTween(self: Item, duration: number, cframe: CFrame): Tween
	-- default is to bounce on y axis
	return PivotToIndependentTween(self:getObj(), duration, "linear", "linear", "outBounce", "linear", cframe)
end

-- helper function to spread out items and make sure they're on the ground
function Item.settleOnGroundInWorkspace(self: Item, doneFunc: () -> (), extraRepulsors: { Repulsor }?)
	self:getPart().Anchored = true

	self:setVenueWorkspaceSettling()

	-- plan:
	--   calculate where we should end up
	--   tween there
	-- simple!

	-- make a list of position & spacing based on all items
	local repulsors: { Repulsor } = {}
	local items = itemManager:getItemsOnGroundByUserId(self.userId)
	for _, item in items do
		if item == self then
			continue
		end
		local itemBoardSpacing = item:getItemData().boardSpacing
		if not itemBoardSpacing then
			continue
		end
		local itemPosition
		if item.settleFinalPosition then
			itemPosition = item.settleFinalPosition
			--print("for item", self.obj, basePosition, "looking at other item's settleFinalPosition instead of existing", item.obj, itemPosition)
		else
			itemPosition = item.obj:GetPivot().Position
		end
		table.insert(repulsors, {
			position = itemPosition,
			boardSpacing = itemBoardSpacing,
		})
	end
	if extraRepulsors then
		for _, repulsor in extraRepulsors do
			table.insert(repulsors, repulsor)
		end
	end

	local playerData = self:getPlayerData()

	local currentPosition = self.obj:GetPivot().Position

	local finalPosition: Vector3?
	local random = Random.new()
	for i = 1, 1000 do
		local angle = random:NextNumber(0, 2 * math.pi)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local magnitude = 1 + i / 10
		local testLocation = currentPosition + (direction * magnitude)
		if not playerData:isLocationInPlotOrUnlockedExpansions(testLocation) then
			continue
		end
		if not utils.getGroundHeight(testLocation.X, testLocation.Z) then
			continue
		end

		local testPosition = self:getSettlePositionForLocation(testLocation)
		if self:calculateSettleOnGroundStep(testPosition, repulsors) then
			-- still overlapping, try again
			continue
		end

		--print("got final destination", testPosition)
		finalPosition = testPosition
		break
	end
	if finalPosition then
		--print("calculated good final location", self.obj, finalPosition)
	else
		print(
			"settle calculated no good final location, using existing--this is not expected to happen",
			self.obj,
			self.obj:GetPivot().Position
		)
		finalPosition = self.obj:GetPivot().Position
	end

	-- finalPosition is set on every path above
	local settlePosition = finalPosition :: Vector3

	local finalCFrame = self:getSettleCFrameForPosition(settlePosition)

	self.settleFinalPosition = settlePosition

	local duration = self:getSettleDurationForPosition(settlePosition)
	local settleTween = self:createSettleTween(duration, finalCFrame)
	self.settleTween = settleTween
	self.settleTweenCompletedConnect = settleTween.Completed:Connect(function()
		self.settleTween = nil;

		(self.settleTweenCompletedConnect :: RBXScriptConnection):Disconnect()
		self.settleTweenCompletedConnect = nil

		self:cleanupSettleOnGroundInWorkspace()

		self:setVenueWorkspaceAvailable()

		self.part.AssemblyLinearVelocity = Vector3.zero
		self.part.AssemblyAngularVelocity = Vector3.zero

		doneFunc()
	end)
	settleTween:Play()
end

function Item.cleanupSettleOnGroundInWorkspace(self: Item)
	self.settleFinalPosition = nil

	if self.settleTween then
		self.settleTween:Cancel()
		self.settleTween = nil
	end

	if self.settleTweenConnect then
		self.settleTweenConnect:Disconnect()
		self.settleTweenConnect = nil
	end
end

function Item.setVenueWorkspaceAvailable(self: Item)
	self.venueChangedEvent:Fire(enums.Venues.WORKSPACE_AVAILABLE)
end

function Item.setVenueWorkspaceSettling(self: Item)
	self.venueChangedEvent:Fire(enums.Venues.WORKSPACE_SETTLING)
end

function Item.setVenueWorkspaceBusy(self: Item)
	self.venueChangedEvent:Fire(enums.Venues.WORKSPACE_BUSY)
end

function Item.notifyParentWorkspace(self: Item)
	self:setVenueWorkspaceAvailable()
end

function Item.processParentWorkspace(self: Item)
	-- by the time this fires, if the item is a model, the parts have been reparented to model

	utils.setPropertyTreeBaseParts(self.obj, "Massless", false)

	local shouldCollideInWorkspace = self:getItemData().shouldCollideInWorkspace
	if shouldCollideInWorkspace == enums.CollideInWorkspace.ALWAYS then
		utils.setPropertyTreeBaseParts(self.obj, "CanCollide", true)
	elseif shouldCollideInWorkspace == enums.CollideInWorkspace.NEVER then
		utils.setPropertyTreeBaseParts(self.obj, "CanCollide", false)
	elseif shouldCollideInWorkspace == enums.CollideInWorkspace.FROM_TEMPLATE then
		utils.setPropertyTreeBasePartsFromTemplate(self.obj, "CanCollide", self:getItemDataType():getTemplate())
	else
		warn("unknown should collide in workspace", self, shouldCollideInWorkspace)
	end

	self:notifyParentWorkspace()
end

function Item.notifyParentPlayer(self: Item)
	self.venueChangedEvent:Fire(enums.Venues.PLAYER)
end

function Item.processParentPlayer(self: Item)
	self.part.Anchored = false

	-- by the time this fires, if the item is a model, the parts have been reparented to primary part and model split out

	-- before we made descendants massless, there was a bizarre bug where you had a low level dragon in inventory.
	-- then, ride a big dragon (any distance) and dismount. Then equip the low level dragon, and the player would teleport
	utils.setPropertyTreeBaseParts(self.part, "Massless", true)
	utils.setPropertyTreeBaseParts(self.part, "CanCollide", false)

	self:notifyParentPlayer()
end

function Item.notifyParentChanged(self: Item)
	if self.obj.Parent == workspace and self.settleFinalPosition then
		-- this happens for placing dragon on ground and nothing else as of 2026-march-12, but I don't know why
		--print("told parent changed to workspace when already settling into that, how does that happen? ignoring it safely", self.obj)
		return
	end

	self:cleanupSettleOnGroundInWorkspace()

	local playerData = self:getPlayerData()
	if playerData then
		-- enable PlayerData to track items in workspace

		local prevInWorkspace = self.prevObjParent == workspace
		local inWorkspace = self.obj.Parent == workspace

		if prevInWorkspace and not inWorkspace then
			--print("parent changed", self.itemName, "left workspace")
			playerData:notifyItemRemovedFromWorkspace(self)
		end

		if not prevInWorkspace and inWorkspace then
			--print("parent changed", self.itemName, "joined workspace")
			playerData:notifyItemAddedToWorkspace(self)
		end
	end

	if self.obj.Parent == workspace then
		-- just moved into workspace
		self:processParentWorkspace()
	else
		-- just picked it up
		self:processParentPlayer()
	end

	self.prevObjParent = self.obj.Parent

	self.isParentingOnLoad = false
end

function Item.moveFromPlayerToWorkspace(self: Item)
	-- restore the instance names lost because it had to be 'Handle' while being child of a tool
	local template = self:getItemDataType():getTemplate()
	if self.part == self.obj then
		self.part.Name = template.Name
	else
		-- this means the obj is a model and the part is the primary part, which was temporarily parented to the tool
		self.part.Name = template.PrimaryPart.Name
	end

	self.obj.Parent = workspace
end

function Item.activate(self: Item)
	self:moveFromPlayerToWorkspace()

	ftueManager:notifyItemPlacedOnGroundForPlayer(self:getPlayer(), self:getItemId())
end

function Item.getToolActivationItem(self: Item): any
	--print("Item:getToolActivationItem called")
	return self
end

function Item.setupChildPartsToObj(self: Item)
	if self.part == self.obj then
		-- a part-only item (e.g. a held shadow dragon) has no model to patch back up, and
		-- parenting the part to itself would throw; the tool welds cleaned up below only exist
		-- for model items, so there is nothing to do
		return
	end

	-- note that if you make the part not a child of the model, then the model's PrimaryPart field is set to nil
	-- we have to do this when an item which is a model is put in the backpack (so that it can be held, the part needs to be a child of the tool)
	-- so we need to patch things up here
	utils.destroyDescendantsByName(self.part, Constants.ITEM_TOOL_WELD_NAME)

	-- now reparent the other parts back to the model
	for _, inst in self.part:GetChildren() do
		if not inst:IsA("BasePart") then
			continue
		end

		inst.Parent = self.obj
	end

	self.part.Parent = self.obj
	self.obj.PrimaryPart = self.part

	-- the part and model might get different cframes while parented by backpack vs player,
	-- so lock them together (this was particularly noticeable for eggs getting merged)
	self.part.CFrame = self.obj:GetPivot()
end

function Item.setupChildPartsToPrimaryPart(self: Item)
	local part = self.part

	-- weld all the parts to the primary part so they are seen if the player holds the item
	for _, inst in self.obj:GetChildren() do
		if not inst:IsA("BasePart") then
			continue
		end
		if inst == part then
			continue
		end

		-- we should probably iterate over a children's descendents and make them massless too, though not sure as of 2025-december-4
		-- I don't think we have any of those, actually. But keep in mind --Chris

		--print("welding", part, inst)
		local weld = Instance.new("WeldConstraint")
		weld.Name = Constants.ITEM_TOOL_WELD_NAME
		weld.Part0 = part
		weld.Part1 = inst
		weld.Parent = part

		-- parent each of these parts to the primary part too, otherwise they won't be shown
		inst.Parent = part
	end
end

--[[
	being activated implies the player is currently holding it
]]
function Item.notifyToolActivated(self: Item)
	--print("notify: item activated", self, "is part anchored?", self:getPart().Anchored)

	local playerData = self:getPlayerData()
	if playerData then
		if not playerData:doAllowActivateItem(self) then
			return
		end
	end

	-- support activation creating new things (e.g. NumberItem needs this sometimes)
	local item = self:getToolActivationItem()
	if not item then
		return
	end

	if item == self then
		local tool = self:findTool()
		-- get the part out of the tool so it's not destroyed along with the tool
		self.part.Parent = nil
		if tool then
			tool:Destroy()
		end

		-- this needs to happen on merging or when forced into workspace too (such as when being used to eat a crop from the hand)
		if self.obj:IsA("Model") then
			self:setupChildPartsToObj()
			self.obj.Parent = workspace
		end
	else
		-- we tried this, it didn't play well
		-- unequip remainder
		--self:getPlayer().Character.Humanoid:UnequipTools()
	end

	-- maybe set part name here?

	-- if item was cloned, does it have a tool? I think not, so... we should be able to deal with tool stuff here

	item:activate()
end

function Item.findTool(self: Item): Tool?
	if self.part.Parent then
		if self.part.Parent:IsA("Tool") then
			return self.part.Parent
		end
	end
	return nil
end

function Item.tryGetGripCFrame(self: Item): CFrame?
	local obj = self:getObj()
	local hold = utils.findFirstDescendant(obj, "Hold")
	if not hold then
		return nil
	end

	return (hold :: any).CFrame
end

-- putInBackpack always returns the tool on success, nil on failure
function Item.putInBackpack(self: Item): Tool?
	local existingTool = self:findTool()
	if existingTool then
		-- already done
		return existingTool
	end

	local tool = Instance.new("Tool")
	tool.Name = self:getToolName()
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool:SetAttribute(Attributes.ITEM_ID, self:getItemId())
	tool:SetAttribute(Attributes.INDEX, self.obj:GetAttribute(Attributes.INDEX))
	tool:SetAttribute(Attributes.ITEM_TYPE, self:getItemData().filterType or self:getItemData().type)
	tool:SetAttribute(Attributes.RARITY, self:getItemData().rarity)

	tool.Activated:Connect(function()
		--print("activated a tool")
		if self:getItemData().mixins.pickup.equip == false then
			--print("activated a tool that isn't really equippable (large dragons)")
			return
		end
		self:notifyToolActivated()
	end)
	tool.Equipped:Connect(function()
		--print("tool equipped for", self)
		self:processEquipped()
	end)
	tool.Unequipped:Connect(function()
		--print("tool unequipped for", self)
		self:processUnequipped()
	end)
	--[[
	tool.Deactivated:Connect(
		function()
			-- probably don't need this
			print("tool deactivated for", self)
		end
	)
	]]

	local gripCFrame = self:tryGetGripCFrame()
	if gripCFrame then
		--print("have a gripCFrame, using it", self:getItemName(), gripCFrame)
		-- only set the position--if you set the whole cframe, the player's orientation will be changed to connect to it
		tool.GripPos = gripCFrame.Position
		--print("have a gripCFrame, using it", tool.Grip)
	end

	local part = self:getPart()

	-- a missing player crashed below before typing too
	local player = self:getPlayer() :: Player

	if self.obj:IsA("Model") then
		-- deal with the fact that a player can't hold a model, only a part
		self:setupChildPartsToPrimaryPart()

		-- stash the model in the backpack
		self.obj.Parent = player.Backpack
	end

	--print("obj getting renamed handle", self)
	if self:getItemData().mixins.pickup.equip == false then
		part.Name = Constants.UNEQUIPPABLE_NAME
		tool.RequiresHandle = false

		-- without the weld, the part will just fall. If it's called Handle, it doesn't (roblox magic :).

		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
		local weld = Instance.new("WeldConstraint")
		weld.Name = Constants.ITEM_TOOL_WELD_NAME
		weld.Part0 = humanoidRootPart
		weld.Part1 = part
		weld.Parent = tool
	else
		part.Name = "Handle"
	end

	part.Parent = tool
	tool.Parent = player.Backpack

	local playerData = self:getPlayerData()
	if playerData then
		indexManager:notifyItemDiscoveredIfNew(player, playerData, self:getItemName())

		if itemManager:isMutationCapableType(self:getType()) then
			-- getMutation only exists on mutation-capable subclasses, checked just above
			local mutation = (self :: any):getMutation()
			if mutation and mutation ~= enums.Mutations.NORMAL then
				indexManager:notifyMutationDiscoveredIfNew(player, playerData, mutation)
			end
		end
	end

	return tool
end

function Item.pickup(self: Item)
	self:equip()
end

-- this is when we programmatically decide to equip an item, such as post-merge
function Item.equip(self: Item)
	local tool = self:putInBackpack()
	if not tool then
		-- failed somehow I guess?
		return
	end

	if self:getItemData().mixins.pickup.equip ~= false then
		-- a missing player/character crashed here before typing too
		((self:getPlayer() :: Player).Character :: any).Humanoid:EquipTool(tool)
	end
end

-- this is when the system decides to equip an item, such as user clicking on item in backpack
function Item.processEquipped(self: Item)
	--print("processing that we were equipped", self.itemName)

	if self:getItemData().mixins.pickup.equip == false then
		-- intention is for ridable dragons to get here as of 2026-march-5
		local playerData = self:getPlayerData()
		if not playerData:doAllowActivateItem(self) then
			return
		end

		-- notifyUnequippableEquipped is defined by the subclasses this path applies to
		(self :: any):notifyUnequippableEquipped()
		return
	end

	ftueManager:notifyItemEquipped(self:getPlayer(), self:getItemId())

	-- contextual FTUE: explain crystals the first time the player holds one from their backpack
	if self:getType() == "crystal" then
		contextualFtueManager:tryTrigger(self:getPlayer(), "receiveCrystal")
	end

	-- contextual FTUE: explain vanity the first time the player holds a key or blueprint
	local itemType = self:getType()
	if itemType == "key" or itemType == "blueprint" then
		contextualFtueManager:tryTrigger(self:getPlayer(), "vanityUnlocked")
	end
end

-- this is when the system decides to unequip an item, such as user clicking on item in backpack when it had been equipped
function Item.processUnequipped(self: Item)
	--print("processing that we were equipped", self.itemName)

	ftueManager:notifyItemUnequipped(self:getPlayer(), self:getItemId())
end

function Item.createAndDecayHighlight(self: Item, color: Color3?)
	local useColor = color or Color3.fromRGB(255, 255, 255)

	-- getPart().Parent is the same as getObj()... but ONLY if the item isn't being held, and if the item isn't a shadow
	local adornee
	if self.part == self.obj then
		adornee = self.part
	else
		adornee = self.part.Parent
	end

	local highlight = Instance.new("Highlight")
	highlight.Adornee = adornee
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = useColor
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1

	local tween = tweenService:Create(
		highlight,
		TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1 }
	)
	tween.Completed:Connect(function()
		highlight:Destroy()
	end)
	tween:Play()

	highlight.Parent = self:getPart()
end

function Item.getItemId(self: Item): number
	return self.itemId
end

function Item.getItemName(self: Item): string
	return self.itemName
end

function Item.getDisplayName(self: Item): string
	local displayName = self:getItemData().displayName
	if not displayName then
		return self.itemName
	end

	return displayName
end

function Item.getToolName(self: Item): string
	return self:getVisibleName()
end

-- override in the case of variable names (such as NumberItem)
function Item.getVisibleName(self: Item): string
	return self:getDisplayName()
end

function Item.notifyVisibleNameChanged(self: Item)
	--print("setting own visible name", self:getObj(), self:getVisibleName())

	local tool = self:findTool()
	if not tool then
		return
	end

	tool.Name = self:getToolName()
end

function Item.notifyTooLow(self: Item)
	--print("item notified it became too low", self, self.obj:GetPivot().Position)
	self:teleportToRecoveryPosition()
end

function Item.getType(self: Item): string
	return self.type
end

function Item.getItemData(self: Item): any
	return objectDataStore:getObjectDataByName(self.itemName)
end

function Item.getItemDataType(self: Item): any
	return objectDataStore:getObjectDataTypeByName(self.itemName)
end

function Item.getUserId(self: Item): number
	return self.userId
end

function Item.getPlayer(self: Item): Player?
	return playersService:GetPlayerByUserId(self.userId)
end

function Item.getPlayerData(self: Item): any
	local player = self:getPlayer()
	if not player then
		return nil
	end
	return gameController:getPlayerData(player)
end

function Item.getObj(self: Item): any
	return self.obj
end

function Item.getPart(self: Item): any
	return self.part
end

function Item.getCount(self: Item): number
	return 1
end

function Item.reduceCount(self: Item, count: number): boolean
	if count <= 0 then
		warn("attempt to reduceCount of item", self, "by invalid count", count)
		return false
	end

	itemManager:destroyItem(self)

	return true
end

function Item.getCapacityCost(self: Item): number
	local capacityCost = self:getItemData().capacityCost
	if not capacityCost then
		warn("item missing capacityCost", self:getItemName())
		capacityCost = 20
	end

	return capacityCost
end

function Item.getIsParentingOnLoad(self: Item): boolean
	return self.isParentingOnLoad
end

function Item.notifyMergingWithTriggerItem(self: Item, triggerItem: any) end

function Item.getVenueChangedEvent(self: Item): RBXScriptSignal
	return self.venueChangedEvent.Event
end

function Item.getWorldSaveCFrame(self: Item): CFrame
	return self:getPart().CFrame
end

function Item.setBackpackIndex(self: Item, index: number?)
	self.obj:SetAttribute(Attributes.INDEX, index)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Item.getSaveData(self: Item, itemIdMap: any): any
	local location
	local backpackIndex
	if self.obj.Parent == workspace then
		location = "world"
	else
		location = "backpack"
		backpackIndex = self.obj:GetAttribute(Attributes.INDEX)
		--print("saving item in backpack", self:getDisplayName(), "index", backpackIndex)
	end

	local worldSaveCFrame = self:getWorldSaveCFrame()
	local saveCFrame = plotsManager:getPlotCFrameFromWorldCFrameForUserId(worldSaveCFrame, self.userId)

	return {
		type = self:getItemData().type,
		itemName = self.itemName,
		obj = {
			location = location,
			backpackIndex = backpackIndex,
			-- can't save cframes, can only save base lua objects, so convert cframe to an array
			plotCFrame = { saveCFrame:GetComponents() },
		},
	}
end

-- for when something bad happens during game, like falling off the world or not being able to settle on board
function Item.teleportToRecoveryPosition(self: Item)
	local random = Random.new()
	local recoveryPosition = plotsManager:getPlotItemRecoveryPositionByUserId(self.userId)
	if not recoveryPosition then
		warn("no recovery position for user", self.userId)
		return
	end
	local newLocation = recoveryPosition + Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))
	local newPosition = utils.getGroundPositionForLocation(newLocation)
	newPosition += Vector3.new(0, self:getPart().Size.Y + random:NextNumber(5, 10), 0)
	self.obj:PivotTo(CFrame.new(newPosition))
	self.part.AssemblyLinearVelocity = Vector3.zero
	self.part.AssemblyAngularVelocity = Vector3.zero

	if self.obj ~= self.part then
		if self.part.Parent == nil then
			-- this happens when the part's Y goes below a certain value so both the obj and part were both on the way to being destroyed
			print("part was parented to nil, patching it up")
			self.part.Parent = self.obj
			self.obj.PrimaryPart = self.part
		end
	end
	self.part.CFrame = CFrame.new(newPosition)
end

function Item.getSafeCFrameOnLoad(self: Item, cframe: CFrame): CFrame
	local location = plotsManager:getRandomLocationInMainPlotByUserId(self.userId)
	if not location then
		-- no plot for this user, so keep the saved cframe
		return cframe
	end
	local position = utils.getGroundPositionForLocation(location)
	return cframe.Rotation + position
end

function Item.loadSaveData(self: Item, itemSaveData: any, itemIdMap: any)
	local playerData = self:getPlayerData()

	if itemSaveData.obj.location == "backpack" then
		--print("have item in backpack, setting index", self.obj, itemSaveData.obj.backpackIndex)
		self.obj:SetAttribute(Attributes.INDEX, itemSaveData.obj.backpackIndex)
	else
		local c: { number } = itemSaveData.obj.plotCFrame
		-- cframe was saved as the 12 components from GetComponents, so convert it back into a cframe
		local cframePlot = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		-- the loading player always has a plot at this point, so the cast keeps the previous crash-on-nil behavior
		local cframe = plotsManager:getWorldCFrameFromPlotCFrameForUserId(cframePlot, self.userId) :: CFrame

		if not playerData:isLocationInPlotOrUnlockedExpansions(cframe.Position) or cframe.Position.Y < -0.1 then
			--if not plotsManager:isPositionInMainPlotXZByUserId(cframe.Position, self.userId) or cframe.Position.Y < -0.1 then
			-- warn(
			-- 	"saved position for an item was outside plot",
			-- 	cframePlot.Position,
			-- 	self.userId,
			-- 	self.itemName,
			-- 	"so moving it to safe spot inside plot"
			-- )
			cframe = self:getSafeCFrameOnLoad(cframe)
		end

		self.isParentingOnLoad = true

		-- move the object into place (model or part). If it's a model, this moves all of its descendants too
		self:getObj():PivotTo(cframe)
	end
end

-- everything has been loaded, so items that depend on other items existing in workspace etc can do proper initialization
function Item.notifyLoadComplete(self: Item, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?) end

function Item.processLoadComplete(self: Item, itemSaveData: any, itemIdMap: any, offlineElapsedSec: number?)
	self:notifyLoadComplete(itemSaveData, itemIdMap, offlineElapsedSec)
end

function Item.destroy(self: Item)
	local playerData = self:getPlayerData()
	if playerData then
		-- enable PlayerData to track items in workspace
		local inWorkspace = self.obj.Parent == workspace
		if inWorkspace then
			playerData:notifyItemRemovedFromWorkspace(self)
		end
	end

	if self.part.Parent and self.part.Parent:IsA("Tool") then
		--print("parent is a tool, destroying it", self)
		self.part.Parent:Destroy()
	end

	self.venueChangedEvent:Destroy();

	(self.parentChangedConnect :: RBXScriptConnection):Disconnect()
	self.parentChangedConnect = nil

	-- this can happen when a model is in the backpack
	if self.part ~= self.obj and self.part.Parent ~= self.obj then
		--print("destroying part specifically", self)
		self.part:Destroy()
		self.part = nil
	end

	self:cleanupSettleOnGroundInWorkspace()

	self.obj:Destroy()
	self.obj = nil
end

-- common stuff for new creations and clones
function Item.initItem(self: Item, obj: any)
	self.obj = obj
	if self.obj:IsA("Model") then
		self.part = self.obj.PrimaryPart
	else
		self.part = self.obj
	end

	-- if we want unique names everywhere, this works
	--obj.Name = obj.Name .. "_" .. self.itemId

	self.prevObjParent = nil

	self.venueChangedEvent = Instance.new("BindableEvent")

	self:getPart().Anchored = false

	obj:SetAttribute(Attributes.ITEM_ID, self.itemId)
	if self.part ~= obj then
		self.part:SetAttribute(Attributes.ITEM_ID, self.itemId)
	end

	obj:AddTag(Tags.ITEM)

	self:resetBillboard()

	self.obj:SetAttribute(Attributes.DISPLAY_NAME, self:getDisplayName())
	self.obj:SetAttribute(Attributes.RARITY, self:getItemData().rarity)

	self.parentChangedConnect = obj:GetPropertyChangedSignal("Parent"):Connect(function()
		self:notifyParentChanged()
	end)

	--[[
	obj.Destroying:Connect(
		function ()
			-- can be helpful for debugging
			--print("obj notified destroying", itemId)
			if itemManager:getItemById(self.itemId) then
				warn("obj notified destroying but item still around", self.itemId, "not supposed to happen")
			end
		end
	)
	]]

	--[[
	obj:GetPropertyChangedSignal("Parent"):Connect(
		function ()
			if obj.Parent == nil then
				if self.itemId ~= nil and itemManager:getItemById(self.itemId) then
					-- hopefully this won't happen any longer because we periodically check item Y values and recover them

					-- https://devforum.roblox.com/t/parts-that-fall-out-of-the-world-are-not-destroyed/2300953/2
					print("item's parent changed to nil but not purposefully destroyed", self.itemId, self:getItemName(), self.part.Position, self.part.Parent)
					-- this means the item fell to oblivion. Teleport it back to the player's plot
					self:teleportToRecoveryPosition()
					obj.Parent = workspace
				end
				return
			end
		end
	)
	]]
end

function Item.notifyNewCopy(self: Item, sourceItem: any, count: number?) end

function Item.processCopy(self: Item, sourceItem: any, count: number?)
	self:notifyNewCopy(sourceItem, count)
end

function Item.copyToPlayer(self: Item, count: number?, player: Player): any
	local item = itemManager:createItem(self:getItemName(), player.UserId)
	if not item then
		warn("copyToPlayer failed to create item", self:getItemName())
		return nil
	end

	item:processCopy(self, count)

	return item
end

function Item.notifyNewClone(self: Item) end

function Item.processClone(self: Item)
	self:notifyNewClone()
end

function Item.clone(self: Item, newItemId: number): any
	local item = utils.deepCopy(self)

	item.itemId = newItemId

	local obj = self:getItemDataType():getTemplate():Clone()
	-- put the new obj in the same spot as the one it was cloned from
	obj:PivotTo(self:getPart().CFrame)

	item:initItem(obj)

	item:processClone()

	return item
end

function Item.new(itemId: number, itemName: string, userId: number): Item
	local self: Item = setmetatable({
		itemId = itemId,
		itemName = itemName,
		userId = userId,
		isParentingOnLoad = false,
	} :: ItemFields, Item) :: any

	local itemData = self:getItemData()
	self.type = itemData.type

	local obj = self:getItemDataType():getTemplate():Clone()

	self:initItem(obj)

	return self
end

function Item.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Item
