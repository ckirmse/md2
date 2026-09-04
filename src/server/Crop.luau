--!strict

local MItem = require("./MItem")
local super = MItem

local Crop = {}
Crop.__index = setmetatable(Crop, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local pickupMixin = require("./PickupMixin")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local modificationDataStore = require("./ModificationDataStore")

type GettingEatenState = Types.GettingEatenState

export type CropFields = Types.CropFields
export type Crop = Types.Crop

function Crop.getDataDumpString(self: Crop): string
	local itemData = self:getItemData()

	local text = super.getDataDumpString(self)
	text = text .. "\nState: " .. tostring(enums.getName(enums.CropState, self.state))
	if itemData.food then
		text = text .. "\nFood: (max " .. itemData.food.maxAmount .. ") (current " .. self.currentFoodAmount .. ")"
	end

	return text
end

function Crop.finishPlaceInWorkspace(self: Crop)
	self.part.Anchored = true

	local itemData = self:getItemData()
	if itemData.food and self.currentFoodAmount < itemData.food.maxAmount then
		self:setState(enums.CropState.GROWING)
	else
		if itemData.food then
			collectionService:AddTag(self:getObj(), Tags.CONSUMABLE_CROP)
		end

		self:setState(enums.CropState.IDLE)
	end
end

function Crop.notifyParentWorkspace(self: Crop)
	-- don't call super, because it would set the item as enums.Venues.WORKSPACE_AVAILABLE, but we may want it to settle first

	if self:getIsParentingOnLoad() or self.doPreventSettling then
		self.doPreventSettling = false
		--print("letting crop get placed directly on ground, skipping settle")
		self:setVenueWorkspaceAvailable()
		self:finishPlaceInWorkspace()
		return
	end

	if self.state == enums.CropState.MERGING then
		return
	end

	self:settleOnGroundInWorkspace(
		function()
			if not self:getObj() then
				return
			end

			self:finishPlaceInWorkspace()
		end
	)
end

function Crop.notifyParentPlayer(self: Crop)
	super.notifyParentPlayer(self)

	-- if something was happening, we gotta stop it

	if self.state == enums.CropState.GETTING_EATEN then
		gameController:endDragonsEatingCrop(self)
	else
		-- if any dragons were coming to eat us, tell 'em we're gone
		gameController:notifyCropNoLongerAvailable(self)
	end

	collectionService:RemoveTag(self:getObj(), Tags.CONSUMABLE_CROP)

	self:setState(enums.CropState.IDLE)
end

function Crop.notifyMergingWithTriggerItem(self: Crop, triggerItem: any)
	if self:isGettingEaten() then
		self:cleanupGettingEaten()
	end

	if self:getItemData().mixins.pickup then
		pickupMixin:notifyItemCannotBePickedUp(self)
	end

	collectionService:RemoveTag(self:getObj(), Tags.CONSUMABLE_CROP)

	self.state = enums.CropState.MERGING
end

function Crop.notifyDragonComingToEat(self: Crop, dragon: any)
	self:setVenueWorkspaceBusy()

	collectionService:RemoveTag(self:getObj(), Tags.CONSUMABLE_CROP)
end

function Crop.notifyDragonNoLongerComingToEat(self: Crop, dragon: any)
	self:checkFullyGrown()
end

function Crop.beginIdle(self: Crop)

end

function Crop.cleanupIdle(self: Crop)

end

function Crop.notifyDragonStartEating(self: Crop, dragon: any)
	local itemData = self:getItemData()
	if not itemData.food then
		print("invalid attempt to eat non-food crop", self:getItemName())
		return
	end

	self:setState(enums.CropState.GETTING_EATEN, dragon)
end

function Crop.beginGettingEaten(self: Crop, dragon: any)
	collectionService:RemoveTag(self:getObj(), Tags.CONSUMABLE_CROP)

	local itemData = self:getItemData()

	if self.currentFoodAmount < self:getItemData().food.maxAmount then
		-- this happens frequently enough, usually when currentFoodAmount is super low
		-- should investigate what triggers this, because the player is getting more gems than they truly should
		print("crop begin getting eaten when not at max food, is this possible?", self:getItemName(), self.currentFoodAmount, itemData.food.maxAmount, self.gettingEaten)
	end

	if itemData.food.gettingEatenParticlePath then
		local dragonPosition = dragon:getPart().Position
		self:getObj():SetAttribute(Attributes.ANIMATION_EAT, string.format("%s %.1f %.1f %.1f", itemData.food.gettingEatenParticlePath, dragonPosition.X, dragonPosition.Y, dragonPosition.Z))
	end

	local totalSteps, maxCountPerStep = gameController:calculateEatingSteps(dragon, self)

	if self:getPlayer() then
		local playerData = gameController:getPlayerData(self:getPlayer())
		if playerData:getDevToolSettings().eatFast then
			totalSteps = 1
			maxCountPerStep = 1
		end
	end

	local gettingEatenState = {
		dragonItemId = dragon:getItemId(),
		step = 0,
		totalSteps = totalSteps,
		currentCountPerStep = 0,
		maxCountPerStep = maxCountPerStep,
	}

	self.gettingEaten = gettingEatenState
end

function Crop.cleanupGettingEaten(self: Crop)
	self:getObj():SetAttribute(Attributes.ANIMATION_EAT, nil)

	gameController:endDragonsEatingCrop(self)
end

function Crop.endGettingEaten(self: Crop)
	self:setState(enums.CropState.GROWING)
end

function Crop.updateFoodVisuals(self: Crop)
	local itemData = self:getItemData()

	-- figure out max fruits we have to work with
	local count = 0
	for _, child in self:getObj():GetChildren() do
		if child:GetAttribute(Attributes.VARIABLE_FOOD) then
			count += 1
		end
	end

	local remainingFrac = self.currentFoodAmount / itemData.food.maxAmount
	local remainingInt = math.floor(remainingFrac * count)

	--print("updating food visuals count", count, "remaining frac", remainingFrac, "remaining int", remainingInt)

	count = 0
	for _, child in self:getObj():GetChildren() do
		if not child:GetAttribute(Attributes.VARIABLE_FOOD) then
			continue
		end

		count += 1
		if count <= remainingInt then
			child.Transparency = 0
		else
			child.Transparency = 1
		end
	end

	self:applyModificationsToFruitIfNeeded()
end

function Crop.beginGrowing(self: Crop)
	local player = self:getPlayer()
	if not player then
		return
	end

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local speedupFrac = playerData:getPlayerVariable(Attributes.CROPS_GROW_FASTER_FRAC)

	local itemData = self:getItemData()
	local timeToFullyGrownSec = ((itemData.food.growMin * 60) * (itemData.food.maxAmount - self.currentFoodAmount) / itemData.food.maxAmount) * (1 - speedupFrac)
	local growCompleteTime = workspace:GetServerTimeNow() + timeToFullyGrownSec
	local obj = self:getObj()

	obj:SetAttribute(Attributes.GROW_COMPLETE_TIME, growCompleteTime)
end

function Crop.cleanupGrowing(self: Crop)
	local obj = self:getObj()
	obj:SetAttribute(Attributes.GROW_COMPLETE_TIME, nil)
end

function Crop.tryStepGetEaten(self: Crop)
	--print("timer went off to get eaten", self, "by dragon", self.gettingEaten.dragonItemId)

	local cropItemData = self:getItemData()

	local dragon = itemManager:getItemById(self.gettingEaten.dragonItemId)
	-- saw dragon nil in prod here somehow 2026-april-13, multiple times xxx
	if not dragon then
		warn("crop try step get eaten cannot find dragon?!? handling but should not be possible", self.gettingEaten.dragonItemId)
		self:setVenueWorkspaceAvailable()
		self:setState(enums.CropState.GROWING)
		return
	end

	local dragonItemData = dragon:getItemData()

	self.gettingEaten.currentCountPerStep += 1
	if self.gettingEaten.currentCountPerStep < self.gettingEaten.maxCountPerStep then
		return
	end

	self.gettingEaten.currentCountPerStep = 0

	self.gettingEaten.step += 1
	--print("eaten step", self.gettingEaten.step)
	if self.gettingEaten.step >= self.gettingEaten.totalSteps then
		--print("get rest eaten")

		self.currentFoodAmount = 0

		-- get gems
		local gemCount = gameController:calculateGemsForHarvest(dragon, self)
		if gemCount > 0 then
			local thisStepGemCount = gemCount - (self.gettingEaten.totalSteps - 1) * (gemCount // self.gettingEaten.totalSteps)
			-- legacy (2026-august-20): used to spawn physical gems; now grants coins directly
			-- gameController:spawnGemsForPlayerFromItem(self:getPlayer(), dragonItemData.primaryElement, thisStepGemCount, self)
			gameController:grantCoinsForGemValue(self:getPlayer(), dragonItemData.primaryElement, thisStepGemCount)
		end

		-- get xp
		local xp = gameController:calculateXpForHarvest(dragon, self)
		if self:getPlayer() then
			local thisStepXp = xp - (self.gettingEaten.totalSteps - 1) * (xp // self.gettingEaten.totalSteps)
			--print("should award xp; total", xp, "this last batch", thisStepXp)
			if xp > 0 then
				gameController:addPrimaryElementXpToPlayer(self:getPlayer(), dragonItemData.primaryElement, thisStepXp, self:getPart())
			end
		end

		self:updateFoodVisuals()

		-- and now we're done
		if self:getModificationCount() > 0 then
			local effectPaths = ""
			for _, modification in self:getModifications() do
				if string.len(effectPaths) > 0 then
					effectPaths = effectPaths .. " "
				end
				-- an unknown modification crashed here before typing too
				local modificationData = modificationDataStore:getModificationDataByValue(modification) :: any
				if not modificationData.harvestedParticleParentTemplatePath then
					continue
				end

				effectPaths = effectPaths .. modificationData.harvestedParticleParentTemplatePath
			end

			utils.pulseAttribute(self:getObj(), Attributes.ANIMATION_MODIFICATIONS_REMOVED, effectPaths)
			self:setModifications({})
		end

		self:setVenueWorkspaceAvailable()
		self:setState(enums.CropState.GROWING)

		gameController:notifyCropFullyEaten(self, dragon, xp, gemCount)

		return
	end

	-- get fraction eaten

	local totalConsumed = cropItemData.food.maxAmount // self.gettingEaten.totalSteps
	self.currentFoodAmount = math.max(0, self.currentFoodAmount - totalConsumed)

	-- get gems
	local gemCount = gameController:calculateGemsForHarvest(dragon, self)
	if gemCount > 0 then
		local thisStepGemCount = gemCount // self.gettingEaten.totalSteps
		-- legacy (2026-august-20): used to spawn physical gems; now grants coins directly
		-- gameController:spawnGemsForPlayerFromItem(self:getPlayer(), dragonItemData.primaryElement, thisStepGemCount, self)
		gameController:grantCoinsForGemValue(self:getPlayer(), dragonItemData.primaryElement, thisStepGemCount)
	end

	-- get xp
	local xp = gameController:calculateXpForHarvest(dragon, self)
	if self:getPlayer() then
		local thisStepXp = xp // self.gettingEaten.totalSteps
		--print("should award xp; total", xp, "this early batch", thisStepXp)
		if xp > 0 then
			gameController:addPrimaryElementXpToPlayer(self:getPlayer(), dragonItemData.primaryElement, thisStepXp, self:getPart())
		end
	end

	self:updateFoodVisuals()

	self:updateDataDump()
end

function Crop.checkFullyGrown(self: Crop)
	local itemData = self:getItemData()
	if not itemData.food then
		return
	end

	if self.currentFoodAmount < itemData.food.maxAmount then
		return
	end

	collectionService:AddTag(self:getObj(), Tags.CONSUMABLE_CROP)

	self:setState(enums.CropState.IDLE)
end

function Crop.isConsumable(self: Crop)
	return self:getObj():HasTag(Tags.CONSUMABLE_CROP)
end

function Crop.growFull(self: Crop)
	if self.state ~= enums.CropState.GROWING then
		return
	end

	self.currentFoodAmount = self:getItemData().food.maxAmount
	self:updateFoodVisuals()
	self:checkFullyGrown()
end

function Crop.addGrowTime(self: Crop, elapsedSec: number)
	--print("adding grow time", self:getItemName(), elapsedSec)

	local player = self:getPlayer()
	if not player then
		return
	end

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	if self.state ~= enums.CropState.GROWING then
		return
	end

	local speedupFrac = playerData:getPlayerVariable(Attributes.CROPS_GROW_FASTER_FRAC)

	local itemData = self:getItemData()

	local growAmount = elapsedSec * itemData.food.maxAmount / (itemData.food.growMin * 60 * (1 - speedupFrac))
	self.currentFoodAmount = math.min(self.currentFoodAmount + growAmount, itemData.food.maxAmount)

	self:updateFoodVisuals()
	self:updateDataDump()

	self:checkFullyGrown()
end

function Crop.tryGrow(self: Crop, elapsedSec: number)
	if self.state ~= enums.CropState.GROWING then
		return
	end

	self:addGrowTime(elapsedSec)
end

function Crop.isGrowing(self: Crop)
	return self.state == enums.CropState.GROWING
end

function Crop.isPlayerCloseEnoughToShootFireballAtCrop(self: Crop, player: Player)
	local playerData = gameController:getPlayerData(player)
	local maxDistance = playerData:getPlayerVariable(Attributes.FIREBALL_RANGE)

	local distance = ((player.Character :: any).HumanoidRootPart.Position - self.obj:GetPivot().Position).Magnitude

	if distance > maxDistance * 1.2 then
		print("player tried to shoot fireball at crop but too far away", player, distance, maxDistance)
		return false
	end

	return true
end


function Crop.isGettingEaten(self: Crop)
	return self.state == enums.CropState.GETTING_EATEN
end

function Crop.getCurrentFoodAmount(self: Crop): number
	return self.currentFoodAmount
end

function Crop.canBePickedUp(self: Crop): boolean
	if self.state == enums.CropState.MERGING then
		return false
	end

	-- other cases handled by mixin
	return true
end

function Crop.setPreventSettling(self: Crop)
	self.doPreventSettling = true
end

function Crop.getToolName(self: Crop): string
	return utils.getColoredTextForRarity(self:getVisibleName(), self:getItemData().rarity)
end

function Crop.endState(self: Crop)
	if self.state == enums.CropState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.CropState.GETTING_EATEN then
		self:cleanupGettingEaten()
	elseif self.state == enums.CropState.GROWING then
		self:cleanupGrowing()
	elseif self.state == enums.CropState.MERGING then
		-- pass
	else
		warn("end unknown crop state", self, self.state)
	end

	self.state = nil
end

function Crop.beginState(self: Crop, state: number?, ...)
	self.state = state
	--print("crop beginning state", self:getItemName(), state)

	if self.state == enums.CropState.IDLE then
		self:beginIdle(...)
	elseif self.state == enums.CropState.GETTING_EATEN then
		self:beginGettingEaten(...)
	elseif self.state == enums.CropState.GROWING then
		self:beginGrowing(...)
	elseif self.state == enums.CropState.MERGING then
		-- pass
	else
		warn("begin unknown crop state", self, state)
	end

	self:updateDataDump()
end

function Crop.setState(self: Crop, state: number?, data: any)
	self:endState()

	self:beginState(state, data)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Crop.getSaveData(self: Crop, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.state = self.state
	retval.currentFoodAmount = self.currentFoodAmount

	return retval
end

function Crop.applyModificationsToFruitIfNeeded(self: Crop)
	local modifications = self:getModifications()
	local needNameMap: { [string]: boolean } = {}
	for _, modification in modifications do
		local modificationData = modificationDataStore:getModificationDataByValue(modification) :: any
		needNameMap[modificationData.cropParticle.Name] = true
		--print("need", modificationData.cropParticle.Name)
	end

	local fruits = utils.getAllDescendantsWithAttribute(self:getObj(), Attributes.VARIABLE_FOOD, true)
	for _, fruitInst in fruits do
		-- fruits are parts; a non-part crashed here before typing too
		local fruit = fruitInst :: any
		-- remove particles from modifications we don't have any longer
		local haveNameMap: { [string]: boolean } = {}
		for _, inst in fruit:GetDescendants() do
			if not inst:IsA("ParticleEmitter") then
				continue
			end
			if not needNameMap[inst.Name] then
				utils.safelyDisposeOfParticle(inst)
				continue
			end
			--print("already have", inst.Name)
			haveNameMap[inst.Name] = true
		end

		if fruit.Transparency == 1 then
			--print("fruit is not grown, so not showing any modifications")
			continue
		end

		-- add particles for modifications we haven't applied yet

		for _, value in modifications do
			local modificationData = modificationDataStore:getModificationDataByValue(value) :: any
			local name = modificationData.cropParticle.Name

			if haveNameMap[name] then
				continue
			end

			--print("adding", name)

			local particle = modificationData.cropParticle:Clone()
			particle.Parent = fruit
		end
	end
end

function Crop.notifyModificationsChanged(self: Crop)
	super.notifyModificationsChanged(self)

	--print("modifications changed", self:getItemName(), self, self:getModifications())

	self:applyModificationsToFruitIfNeeded()
end

function Crop.loadSaveData(self: Crop, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	self.state = itemSaveData.state
	self.currentFoodAmount = itemSaveData.currentFoodAmount

	-- offline time processed by game controller

	self:beginIdle()
end

function Crop.destroy(self: Crop)
	self:endState()

	if self.heartbeatConnect then
		self.heartbeatConnect:Disconnect()
		self.heartbeatConnect = nil
	end

	super.destroy(self)
end

function Crop.init(self: Crop)
	self.random = Random.new()

	self.state = enums.CropState.IDLE

	collectionService:AddTag(self:getObj(), Tags.CROP)

	utils.addTreeToCollisionGroup(self:getObj(), Constants.NO_COLLIDE_GEMS_COLLISION_GROUP)
end

function Crop.notifyNewClone(self: Crop)
	super.notifyNewClone(self)

	self:init()

	if self:getItemData().food then
		-- crops taken from backpack get emptied
		self.currentFoodAmount = 0
	end


end

function Crop.new(itemId: number, itemName: string, userId: number): Crop
	local self = (setmetatable(super.new(itemId, itemName, userId), Crop) :: any) :: Crop

	self:init()

	if self:getItemData().food then
		-- newly created crops start fully grown and ready to harvest
		self.currentFoodAmount = self:getItemData().food.maxAmount
	end

	return self
end

function Crop.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Crop
