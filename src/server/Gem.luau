--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local Gem = {}
Gem.__index = setmetatable(Gem, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local objectDataStore = require("./ObjectDataStore")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local playerAttributesManager = require("./PlayerAttributesManager")


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")


local VACUUM_DURATION_MIN_SEC = 0.9
local VACUUM_DURATION_MAX_SEC = 1.5

export type GemFields = Types.GemFields
export type Gem = Types.Gem

function Gem.getDataDumpString(self: Gem): string
	local text = super.getDataDumpString(self)

	-- could add custom stuff here

	return text
end

-- gems can't go in backpack; instead, their value is added to player attribute for the gem
function Gem.putInBackpack(self: Gem): Tool?
	local totalValue

	local itemData = self:getItemData()

	local unitValue = 1
	if not itemData.denominations then
		-- we are a larger gem worth a bunch of base gems; we need to calculate unit value and multiply by our count to get total value
		-- start by figuring out the proper value

		local baseItemName = gameController:getGemItemNameForPrimaryElement(itemData.primaryElement)
		if not baseItemName then
			warn("no base gem item for primary element", itemData.primaryElement)
			return nil
		end
		local baseItemData = objectDataStore:getObjectDataByName(baseItemName)
		for _, denominationData in baseItemData.denominations do
			if denominationData.itemName == itemData.name then
				unitValue = denominationData.value
				break
			end
		end
		if not unitValue then
			warn("gem cannot be looked up in its base for denomination", self:getItemName())
			return nil
		end
	end

	totalValue = self:getCount() * unitValue

	local primaryElement = itemData.primaryElement
	local playerAttributesKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)

	playerAttributesManager:addWholeNumber(self:getPlayer(), playerAttributesKeyGems, totalValue)

	itemManager:destroyItem(self)

	-- gems never yield a tool; their value is banked instead
	return nil
end

-- intercepted at load time by ItemManager.loadDataForPlayer for any saved gem item that would
-- otherwise spawn on the ground; grants its value as coins instead (2026-august-21)
function Gem.grantCoinsInsteadOfSpawning(self: Gem): ()
	local itemData = self:getItemData()

	local unitValue = 1
	if not itemData.denominations then
		local baseItemName = gameController:getGemItemNameForPrimaryElement(itemData.primaryElement)
		if baseItemName then
			local baseItemData = objectDataStore:getObjectDataByName(baseItemName)
			for _, denominationData in baseItemData.denominations do
				if denominationData.itemName == itemData.name then
					unitValue = denominationData.value
					break
				end
			end
		end
	end

	local totalValue = self:getCount() * unitValue

	gameController:grantCoinsForGemValue(self:getPlayer(), itemData.primaryElement, totalValue)

	itemManager:destroyItem(self)
end

function Gem.checkVacuum(self: Gem)
	if self.isVacuuming then
		return
	end

	--print("checking gem vacuum", self:getItemName(), self:getItemId())

	local player = self:getPlayer()
	local character: any = player and player.Character
	if not player or not character or not character.HumanoidRootPart then
		return
	end
	local playerData = self:getPlayerData()
	if not playerData then
		return
	end

	local playerPosition = character.HumanoidRootPart.Position

	local obj = self:getObj()
	local positionDiff = playerPosition - obj:GetPivot().Position
	local distance = positionDiff.Magnitude
	-- if it's pretty close vertically, ignore the Y difference
	if math.abs(positionDiff.Y) < 5 then
		distance = utils.getMagnitudeXZ(positionDiff)
	end

	local vacuumMaxDistance

	if playerData:getRidingItemId() ~= nil then
		vacuumMaxDistance = Constants.GEM_VACUUM_MAX_DISTANCE_RIDING
	else
		vacuumMaxDistance = Constants.GEM_VACUUM_MAX_DISTANCE
	end

	if distance > vacuumMaxDistance then
		return
	end

	self:beginVacuum()
end

function Gem.beginVacuum(self: Gem)
	if self.isVacuuming then
		return
	end

	local random = Random.new()
	local duration = random:NextNumber(VACUUM_DURATION_MIN_SEC, VACUUM_DURATION_MAX_SEC)

	local now = workspace:GetServerTimeNow()
	local destroyTime = now + duration

	--print("vacuuming", self:getItemName())

	utils.setPropertyTreeBaseParts(self:getObj(), "CanCollide", false)
	self:getPart().Anchored = true
	self.isVacuuming = true

	self:getObj():SetAttribute(Attributes.ANIMATION_FLY_AWAY, string.format("%.3f", destroyTime))

	task.delay(duration,
		function()
			if not self:getObj() then
				--print("gem already destroyed", self)
				return
			end

			self:putInBackpack()
		end
	)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function Gem.getSaveData(self: Gem, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	return retval
end

function Gem.loadSaveData(self: Gem, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Gem.init(self: Gem)
	utils.addTreeToCollisionGroup(self:getObj(), Constants.GEMS_COLLISION_GROUP)

	self:getObj():SetAttribute(Attributes.USER_ID, self:getUserId())
	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, self:getItemData().primaryElement)
	collectionService:AddTag(self:getObj(), Tags.GEM)
end

function Gem.notifyNewClone(self: Gem)
	--print("gem notify new clone")

	super.notifyNewClone(self)

	self:init()
end

function Gem.new(itemId: number, itemName: string, userId: number): Gem
	local self = (setmetatable(super.new(itemId, itemName, userId), Gem) :: any) :: Gem

	self:init()

	return self
end

function Gem.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return Gem
