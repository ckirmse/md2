--!strict

local ClientPlayerAttributesManager = {}
ClientPlayerAttributesManager.__index = ClientPlayerAttributesManager

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local StableConfig = require("@game/ReplicatedStorage/Shared/StableConfig")

-- attribute values are server-defined (numbers/strings/booleans keyed by PlayerAttributeKeys),
-- so the value side is genuinely dynamic
type ClientPlayerAttributesManagerFields = {
	attributes: { [string]: any },
}

export type ClientPlayerAttributesManager = typeof(setmetatable({} :: ClientPlayerAttributesManagerFields, ClientPlayerAttributesManager))

function ClientPlayerAttributesManager.setAll(self: ClientPlayerAttributesManager, newAttributes: { [string]: any })
	self.attributes = newAttributes
end

function ClientPlayerAttributesManager.getAll(self: ClientPlayerAttributesManager): { [string]: any }
	return self.attributes
end

function ClientPlayerAttributesManager.get(self: ClientPlayerAttributesManager, key: string): any
	return self.attributes[key]
end

function ClientPlayerAttributesManager.getDragonSlotCount(self: ClientPlayerAttributesManager): number
	return (self.attributes[PlayerAttributeKeys.DRAGON_SLOT_COUNT] :: number?) or StableConfig.STABLE_SLOT_COUNT
end

function ClientPlayerAttributesManager.set(self: ClientPlayerAttributesManager, key: string, value: any)
	self.attributes[key] = value
end

function ClientPlayerAttributesManager.new(): ClientPlayerAttributesManager
	local self = setmetatable({} :: ClientPlayerAttributesManagerFields, ClientPlayerAttributesManager)

	self.attributes = {}

	return self
end


local singleton = ClientPlayerAttributesManager.new()

return singleton
