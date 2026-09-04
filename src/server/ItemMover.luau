--!strict

local ItemMover = {}
ItemMover.__index = ItemMover

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

type ItemMoverFields = {
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
}


-- subclasses call this from runHeartbeat when they're done
export type ItemMover = Types.ItemMover

function ItemMover.notifyDone(self: ItemMover)
	-- movers only exist for live dragons, so the casts here keep the previous crash-on-missing behavior
	local item = itemManager:getItemById(self.itemId) :: Types.ShadowDragon

	item:notifyItemMoverDone()
end

function ItemMover.getObj(self: ItemMover): any
	return (itemManager:getItemById(self.itemId) :: Types.Item):getObj()
end

function ItemMover.getPart(self: ItemMover): any
	return (itemManager:getItemById(self.itemId) :: Types.Item):getPart()
end

function ItemMover.setStepCallback(self: ItemMover, func: ((CFrame) -> ())?)
	self.stepCallbackFunc = func
end

function ItemMover.getStepCallback(self: ItemMover): ((CFrame) -> ())?
	return self.stepCallbackFunc
end

function ItemMover.tryBegin(self: ItemMover): boolean
	return true
end

function ItemMover.destroy(self: ItemMover)

end

function ItemMover.new(itemId: number, endCFrame: CFrame): ItemMover
	local self: ItemMover = setmetatable({
		itemId = itemId,
		endCFrame = endCFrame,
	} :: ItemMoverFields, ItemMover) :: any

	self.beginCFrame = self:getObj():GetPivot()

	return self
end

function ItemMover.initClass(deps: any)
	itemManager = deps.itemManager
end

return ItemMover
