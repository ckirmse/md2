--!strict

local SellMixin = {}
SellMixin.__index = SellMixin


local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")

type SellMixinFields = {}

export type SellMixin = typeof(setmetatable({} :: SellMixinFields, SellMixin))

function SellMixin.notifyItemCreated(self: SellMixin, item: any)
	local obj = item:getObj()

	--print("new sell item created", obj, item:getUserId())

	obj:SetAttribute(Attributes.SELL_NAME, item:getItemName())
end

function SellMixin.notifyItemCloned(self: SellMixin, item: any)
	self:notifyItemCreated(item)
end

function SellMixin.new()
	local self = setmetatable({}, SellMixin)

	return self
end

local singleton = SellMixin.new()

return singleton
