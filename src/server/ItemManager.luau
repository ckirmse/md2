--!strict

local ItemManager = {}
ItemManager.__index = ItemManager

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local Blueprint = require("./Blueprint")
local Types = require("./Types")
local Crate = require("./Crate")
local Crop = require("./Crop")
local Crystal = require("./Crystal")
local DragonEgg = require("./DragonEgg")
local ShadowDragon = require("./ShadowDragon")
local Gem = require("./Gem")
local Key = require("./Key")
local objectDataStore = require("./ObjectDataStore")
local Pack = require("./Pack")

local itemTypeClassMap: { [string]: any } = {
	blueprint = Blueprint,
	crate = Crate,
	crop = Crop,
	crystal = Crystal,
	dragonEgg = DragonEgg,
	gem = Gem,
	key = Key,
	pack = Pack,
	shadowDragon = ShadowDragon,
}

local mixinMap: any -- initialized by the game controller

type ItemManagerFields = {
	nextObjectId: number,
	-- map from itemId to item for every item on this server, whether in player's backpack or in workspace
	items: { [number]: any },
	useBillboards: boolean,
}

export type ItemManager = typeof(setmetatable({} :: ItemManagerFields, ItemManager))

function ItemManager.isMutationCapableType(self: ItemManager, itemType: string): boolean
	local itemClass = itemTypeClassMap[itemType]
	return itemClass ~= nil and itemClass.getMutation ~= nil
end

function ItemManager.getAvailableDragonsToEatForPlayer(self: ItemManager, player: Player): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		if not item:isAvailableToEat() then
			continue
		end
		if item:getUserId() ~= player.UserId then
			continue
		end

		table.insert(retval, item)
	end

	return retval
end

function ItemManager.getAvailableDragonsToOpenForPlayer(self: ItemManager, player: Player): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		if not item:isAvailableToOpen() then
			continue
		end
		if item:getUserId() ~= player.UserId then
			continue
		end

		table.insert(retval, item)
	end

	return retval
end

function ItemManager.getAvailableDragonsToMineForPlayer(self: ItemManager, player: Player): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		if not item:isAvailableToMine() then
			continue
		end
		if item:getUserId() ~= player.UserId then
			continue
		end

		table.insert(retval, item)
	end

	return retval
end

function ItemManager.getRidableDragonsForPlayer(self: ItemManager, player: Player): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		local itemData = item:getItemData()
		if not itemData.mixins.ride then
			continue
		end
		if item:getUserId() ~= player.UserId then
			continue
		end

		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getGrowingCrops(self: ItemManager): { Types.Crop }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crop" then
			continue
		end
		if not item:isGrowing() then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getCropsGettingEaten(self: ItemManager): { Types.Crop }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crop" then
			continue
		end
		if not item:isGettingEaten() then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getAllDragons(self: ItemManager): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getDragonsEatingCrop(self: ItemManager, crop: Types.Crop): { Types.ShadowDragon }
	local cropItemId = crop:getItemId()

	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		local eatingItemId = item:getEatingItemId()
		if not eatingItemId then
			continue
		end
		if eatingItemId ~= cropItemId then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getDragonsMovingToEatCrop(self: ItemManager, crop: Types.Crop): { Types.ShadowDragon }
	local cropItemId = crop:getItemId()

	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		local movingToEatItemId = item:getMovingToEatItemId()
		if not movingToEatItemId then
			continue
		end
		if movingToEatItemId ~= cropItemId then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getDragonsMovingToOpenCrystal(self: ItemManager, crystal: Types.Crystal): { Types.ShadowDragon }
	local crystalItemId = crystal:getItemId()

	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		local movingToOpenItemId = item:getMovingToOpenItemId()
		if not movingToOpenItemId then
			continue
		end
		if movingToOpenItemId ~= crystalItemId then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getCropsDragonCanEat(self: ItemManager, dragon: Types.ShadowDragon): { Types.Crop }
	local dragonUserId = dragon:getUserId()

	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crop" then
			continue
		end
		if item:getUserId() ~= dragonUserId then
			continue
		end
		if item:getObj().Parent ~= workspace then
			-- can't go eat something that's being held
			continue
		end
		if item:getCurrentFoodAmount() <= 0 then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getDragonsOnGroundForUserId(self: ItemManager, userId: any): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		if item:getUserId() ~= userId then
			continue
		end
		if item:getObj().Parent ~= workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getCropsOnGroundForUserId(self: ItemManager, userId: any): { Types.Crop }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crop" then
			continue
		end
		if item:getUserId() ~= userId then
			continue
		end
		if item:getObj().Parent ~= workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getCropsOnGround(self: ItemManager): { Types.Crop }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crop" then
			continue
		end
		if item:getObj().Parent ~= workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getDragonsOnGround(self: ItemManager): { Types.ShadowDragon }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "shadowDragon" then
			continue
		end
		if item:getObj().Parent ~= workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getOpeningCrystalsForUserId(self: ItemManager, userId: any): { Types.Crystal }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "crystal" then
			continue
		end
		if item:getUserId() ~= userId then
			continue
		end
		if not item:isOpening() then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getItemsOnGroundByUserId(self: ItemManager, userId: any): { Types.Item }
	local retval = {}
	for _, item in self.items do
		if item:getUserId() ~= userId then
			continue
		end
		if item:getObj().Parent ~= workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getItemsNotOnGroundByUserId(self: ItemManager, userId: any): { Types.Item }
	local retval = {}
	for _, item in self.items do
		if item:getUserId() ~= userId then
			continue
		end
		if item:getObj().Parent == workspace then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.getItemCountByUserId(self: ItemManager, userId: any): number
	local retval = 0
	for _, item in self.items do
		if item:getUserId() ~= userId then
			continue
		end
		retval += 1
	end
	return retval
end

function ItemManager.getItemCountByUserIdAndName(self: ItemManager, userId: any, itemName: string): number
	local itemCount = 0

	for _, item in self.items do
		if item:getUserId() ~= userId then
			continue
		end
		if item:getItemName() ~= itemName then
			continue
		end
		itemCount += 1
	end

	return itemCount
end

function ItemManager.getAllGems(self: ItemManager): { Types.Gem }
	local retval = {}
	for _, item in self.items do
		if item:getType() ~= "gem" then
			continue
		end
		table.insert(retval, item)
	end
	return retval
end

function ItemManager.checkItemsFallingTooLow(self: ItemManager)
	for _, item in self.items do
		local obj = item:getObj()
		if obj.Parent ~= workspace then
			continue
		end
		local position = obj:getPivot().Position
		if position.Y < Constants.MIN_ITEM_Y then
			item:notifyTooLow()
		end
	end
end

function ItemManager.getNextObjectId(self: ItemManager): number
	local retval = self.nextObjectId
	self.nextObjectId += 1
	return retval
end

function ItemManager.createItemRaw(self: ItemManager, itemId: number, itemData: any, userId: any): Types.Item?
	local itemName = itemData.name

	local itemTypeClass = itemTypeClassMap[itemData.type]
	if not itemTypeClass then
		warn("unknown item data type", itemData.type)
		return nil
	end

	local item = itemTypeClass.new(itemId, itemName, userId)
	self.items[itemId] = item

	item:updateDataDump()

	return item
end

function ItemManager.applyMixinsToItem(self: ItemManager, item: Types.Item)
	local itemData = item:getItemData()
	for mixinName in itemData.mixins do
		mixinMap[mixinName]:notifyItemCreated(item)
	end
end

function ItemManager.applyMixinsToClonedItem(self: ItemManager, item: Types.Item)
	local itemData = item:getItemData()
	for mixinName in itemData.mixins do
		mixinMap[mixinName]:notifyItemCloned(item)
	end
end

function ItemManager.cloneItem(self: ItemManager, item: Types.Item): Types.Item?
	local newItemId = self:getNextObjectId()
	local newItem = item:clone(newItemId)

	self.items[newItemId] = newItem

	self:applyMixinsToClonedItem(newItem)

	item:updateDataDump()

	return newItem
end

function ItemManager.createItem(self: ItemManager, itemName: string, userId: any): Types.Item?
	local itemData = objectDataStore:getObjectDataByName(itemName)
	if not itemData then
		warn("unable to find data to create item", itemName)
		return nil
	end

	local itemId = self:getNextObjectId()
	local item = self:createItemRaw(itemId, itemData, userId)
	if not item then
		return nil
	end

	self:applyMixinsToItem(item)

	return item
end

-- despite the name, callers pass a user id here and it flows through as the item owner id
function ItemManager.loadItem(self: ItemManager, itemId: number, itemData: any, player: any, itemSaveData: any, itemIdMap: any)
	--print("loading item save data now:", itemSaveData)

	local item = self:createItemRaw(itemId, itemData, player)
	if not item then
		return
	end

	item:loadSaveData(itemSaveData, itemIdMap)

	self:applyMixinsToItem(item)
end

function ItemManager.destroyItem(self: ItemManager, item: Types.Item): boolean
	--print("destroying item", item:getItemId(), item:getItemName())

	local itemId = item:getItemId()
	if self.items[itemId] then
		self.items[itemId] = nil
	else
		warn("cannot find item to destroy", item)
		return false
	end

	item:destroy()

	return true
end

function ItemManager.getSaveDataForPlayer(self: ItemManager, player: Player): any
	local saveData = {}

	local itemIdMap = {}
	local nextMappedItemId = 1
	for itemId, item in self.items do
		itemIdMap[itemId] = nextMappedItemId
		nextMappedItemId += 1
	end

	for itemId, item in self.items do
		if item:getUserId() ~= player.UserId then
			continue
		end

		local mappedItemId = itemIdMap[itemId]

		local itemSaveData = item:getSaveData(itemIdMap)
		-- json encoder can't handle tables with numeric keys unless it's a pure array (not map)
		-- and with our mapped itemIds, this IS a pure array, but... that seems risky
		-- so tostring() instead, for now at least

		-- though we're not actually using json encoder for anything at this point, so not sure we should care

		saveData[tostring(mappedItemId)] = itemSaveData
	end

	return saveData
end

function ItemManager.loadDataForPlayer(self: ItemManager, player: Player, saveData: any, offlineElapsedSec: number?)
	local itemIdMap = {}
	for savedItemIdStr, itemSaveData in saveData do
		local savedItemId = tonumber(savedItemIdStr)

		itemIdMap[savedItemId] = self:getNextObjectId()
	end

	for savedItemIdStr, itemSaveData in saveData do
		local savedItemId = tonumber(savedItemIdStr)

		local itemData = objectDataStore:getObjectDataByName(itemSaveData.itemName)
		if not itemData then
			warn("unable to find data to load item", itemSaveData.itemName)
			continue
		end
		local itemId = itemIdMap[savedItemId]

		self:loadItem(itemId, itemData, player.UserId, itemSaveData, itemIdMap)
	end

	-- now place all the items that belong in the workspace in the workspace
	for savedItemIdStr, itemSaveData in saveData do
		if itemSaveData.obj.location ~= "world" then
			continue
		end
		local savedItemId = tonumber(savedItemIdStr)
		local itemId = itemIdMap[savedItemId]
		local item = self:getItemById(itemId)
		if not item then
			-- failed to load it above
			continue
		end

		if item:getType() == "gem" then
			-- gems are no longer spawned in the world; grant their value as coins instead (2026-august-21)
			(item :: Types.Gem):grantCoinsInsteadOfSpawning()
			continue
		end

		item:getObj().Parent = workspace
	end

	-- now find all the items in the backpack
	local backpackSaveDatas = {}
	for savedItemIdStr, itemSaveData in saveData do
		if itemSaveData.obj.location ~= "backpack" then
			continue
		end
		local savedItemId = tonumber(savedItemIdStr)
		local itemId = itemIdMap[savedItemId]
		table.insert(backpackSaveDatas, {
			itemId = itemId,
			itemSaveData = itemSaveData,
		})
	end

	--[[
	-- sort items in backpack by order they were in backpack
	table.sort(backpackSaveDatas,
		function(a, b)
			--print("comparing", a, b)
			local indexA = a.itemSaveData.obj.backpackIndex
			local indexB = b.itemSaveData.obj.backpackIndex
			if not indexA then
				--print("no index for", a.itemSaveData.itemName)
				indexA = math.huge
			end
			if not indexB then
				--print("no index for", b.itemSaveData.itemName)
				indexB = math.huge
			end

			return indexA < indexB
		end
	)

	-- and place in the backpack, in that same order
	for _, backpackSaveData in backpackSaveDatas do
		local itemId = backpackSaveData.itemId
		local item = self:getItemById(itemId)
		--print("putting in backpack", item:getDisplayName())
		item:putInBackpack()
	end
	]]
	for _, backpackSaveData in backpackSaveDatas do
		local itemId = backpackSaveData.itemId
		local item = self:getItemById(itemId)
		if not item then
			-- failed to load it
			continue
		end

		--print("putting in backpack", item:getDisplayName())
		item:putInBackpack()
	end

	for savedItemIdStr, itemSaveData in saveData do
		local savedItemId = tonumber(savedItemIdStr)

		local itemId = itemIdMap[savedItemId]
		local item = self:getItemById(itemId)
		if not item then
			-- this can happen with numberitems in backpack if they get merged on load
			-- this shouldn't happen if everything is OK (because that stacking should have happened when item was put in backpack)
			print("unable to get loaded item, trying to recover", itemId, saveData)
			continue
		end

		item:processLoadComplete(itemSaveData, itemIdMap, offlineElapsedSec)
	end
end

function ItemManager.removeAllItemsForPlayer(self: ItemManager, player: Player)
	print("removing all items of user", player.UserId, "starting with total", utils.getTableSize(self.items))

	local countRemoved
	countRemoved = 0
	for itemId, item in self.items do
		if item:getUserId() ~= player.UserId then
			continue
		end
		if self:destroyItem(item) then
			countRemoved += 1
		end
	end

	print(
		"ItemManager handled player removed; removed",
		countRemoved,
		"items, leaving",
		utils.getTableSize(self.items),
		"items remaining"
	)
end

function ItemManager.notifyRemovePlayer(self: ItemManager, player: Player)
	self:removeAllItemsForPlayer(player)
end

function ItemManager.getItemById(self: ItemManager, itemId: number?): Types.Item?
	if not itemId then
		warn("getItemById asked for item for nil", debug.traceback())
		return nil
	end

	local item = self.items[itemId]
	if not item then
		-- this is OK--specifically expected to do this when destroyed
		return nil
	end

	return item
end

function ItemManager.getUseBillboards(self: ItemManager): boolean
	return self.useBillboards
end

function ItemManager.setUseBillboards(self: ItemManager, doUseBillboards: any)
	self.useBillboards = doUseBillboards

	for itemId, item in self.items do
		item:resetBillboard()
	end
end

function ItemManager.new(): ItemManager
	local self: ItemManager = setmetatable({
		nextObjectId = 1001,
		-- map from itemId to item for every item on this server, whether in player's backpack or in workspace
		items = {},

		useBillboards = false,
	} :: ItemManagerFields, ItemManager)

	return self
end

function ItemManager.initMixins(newMixinMap: any)
	mixinMap = newMixinMap
end

local singleton = ItemManager.new()

return singleton
