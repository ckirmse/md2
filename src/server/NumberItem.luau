--!strict

local Item = require("./Item")
local super = Item

local NumberItem = {}
NumberItem.__index = setmetatable(NumberItem, super)

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")


export type NumberItemFields = Types.NumberItemFields
export type NumberItem = Types.NumberItem

function NumberItem.getDataDumpString(self: NumberItem): string
	local text = Item.getDataDumpString(self)

	text = text .. "\nCount: " .. tostring(self.number)

	return text
end

function NumberItem.splitOffOne(self: NumberItem): NumberItem?
	if self.number < 2 then
		warn("NumberItem can't split off one", self:getItemName(), self.number)
		return nil
	end

	self:decrementCount()

	--print("creating clone to activate of", self)
	local item = itemManager:cloneItem(self) :: NumberItem?
	if not item then
		return nil
	end
	item:setCount(1)

	--print("clone is", item)

	return item
end

function NumberItem.splitOffCount(self: NumberItem, count: number): NumberItem?
	if count < 1 then
		warn("NumberItem can't split off bad count", self:getItemName(), count)
		return nil
	end

	if self.number < count + 1 then
		warn("NumberItem can't split off count", self:getItemName(), count, self.number)
		return nil
	end

	self:reduceCount(count)

	--print("creating clone to activate of", self)
	local item = itemManager:cloneItem(self) :: NumberItem?
	if not item then
		return nil
	end
	item:setCount(count)

	--print("clone is", item)

	return item
end

function NumberItem.getToolActivationItem(self: NumberItem): any
	--print("numberitem get tool activation item called", self)
	if self.number == 1 then
		--print("numberitem get tool activation returning self")
		return self
	end

	return self:splitOffOne()
end

function NumberItem.putInBackpack(self: NumberItem): Tool?
	-- if something of this itemName already exists in backpack, bump up its number and delete ourselves

	local player = self:getPlayer()
	if not player then
		return nil
	end

	-- need to check backpack AND equipped tool
	local checkTools = player.Backpack:GetChildren()
	local character = player.Character or player.CharacterAdded:Wait()
	for _, tool in character:GetChildren() do
		if not tool:IsA("Tool") then
			continue
		end

		table.insert(checkTools, tool)
	end

	for _, tool in checkTools do
		--print("tool in checkTools:", tool)
		local itemPart = tool:FindFirstChild("Handle")
		if not itemPart then
			-- larger dragons can't be equipped but they can be merged here
			itemPart = tool:FindFirstChild(Constants.UNEQUIPPABLE_NAME)
		end
		if not itemPart then
			-- we put the model of an item here, so it's OK
			continue
		end

		local itemId = itemPart:GetAttribute(Attributes.ITEM_ID) :: number?
		--print("looking at backpack item id", itemId)
		-- items sharing our itemName are the same class, so they stack like us
		local item = itemManager:getItemById(itemId) :: NumberItem?
		if not item then
			warn("cannot find item from tool", itemId)
			continue
		end
		--print("item is", item)
		local itemName = item:getItemName()
		if itemName ~= self:getItemName() then
			--print("item names don't match")
			continue
		end

		if not item:canStackWith(self) then
			continue
		end

		-- found item in backpack to boost its number
		--print("add", self.number, "number of", item, "in backpack")
		item:addCount(self.number)

		itemManager:destroyItem(self)

		-- putInBackpack always returns the tool
		return item:getPart().Parent
	end

	--print("not found in backpack, so do normal thing of putting us in backpack")

	return super.putInBackpack(self)
end

function NumberItem.canStackWith(self: NumberItem, item: any): boolean
	return true
end

function NumberItem.getCount(self: NumberItem): number
	return self.number
end

function NumberItem.notifyNumberChanged(self: NumberItem)
end

function NumberItem.processNumberChanged(self: NumberItem)
	self:getObj():SetAttribute(Attributes.COUNT, self.number)

	self:notifyNumberChanged()
	self:notifyVisibleNameChanged()
end

function NumberItem.setCount(self: NumberItem, count: number)
	self.number = count
	self:processNumberChanged()
end

function NumberItem.addCount(self: NumberItem, count: number)
	if count <= 0 then
		warn("attempt to addCount of item", self, "by invalid count", count)
		return
	end

	self.number += count

	self:processNumberChanged()
end


function NumberItem.reduceCount(self: NumberItem, count: number): boolean
	if count <= 0 then
		warn("attempt to reduceCount of item", self, "by invalid count", count)
		return false
	end

	if count > self.number then
		warn("attempt to reduceCount of item", self, "by too-high count", count, self.number)
		-- still proceed, seems like best course of action... I guess
		count = self.number
	end

	self.number -= count

	self:processNumberChanged()

	if self.number > 0 then
		return false
	end

	itemManager:destroyItem(self)

	return true
end

function NumberItem.incrementCount(self: NumberItem)
	self.number += 1
	self:processNumberChanged()
end

function NumberItem.decrementCount(self: NumberItem)
	self.number = self.number - 1
	self:processNumberChanged()
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function NumberItem.getSaveData(self: NumberItem, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.number = self.number

	return retval
end

function NumberItem.getVisibleNameSuffix(self: NumberItem): string
	if self.number == 1 then
		return ""
	end

	return " (" .. tostring(self.number) .. ")"
end

function NumberItem.getVisibleName(self: NumberItem): string
	return super.getVisibleName(self) .. self:getVisibleNameSuffix()
end

function NumberItem.loadSaveData(self: NumberItem, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	if itemSaveData.number < 1 then
		self.number = 1
	else
		self.number = itemSaveData.number or self.number
	end
	self:processNumberChanged()
end

function NumberItem.init(self: NumberItem)
	self:processNumberChanged()
end

function NumberItem.notifyNewCopy(self: NumberItem, sourceItem: any, count: number)
	super.notifyNewCopy(self, sourceItem, count)

	self.number = count
end

function NumberItem.notifyNewClone(self: NumberItem)
	super.notifyNewClone(self)

	self:init()
end

function NumberItem.new(itemId: number, itemName: string, userId: number): NumberItem
	local self = (setmetatable(super.new(itemId, itemName, userId), NumberItem) :: any) :: NumberItem

	self.number = 1

	self:init()

	return self
end

function NumberItem.initClass(deps: any)
	itemManager = deps.itemManager
end

return NumberItem
