--!strict

local ClientPlayerAttributesManager = {}
ClientPlayerAttributesManager.__index = ClientPlayerAttributesManager

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local EggSlotConfig = require("@game/ReplicatedStorage/Shared/EggSlotConfig")

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

function ClientPlayerAttributesManager.getEggSlotCount(self: ClientPlayerAttributesManager): number
	return (self.attributes[PlayerAttributeKeys.EGG_SLOT_COUNT] :: number?) or EggSlotConfig.EGG_SLOT_COUNT
end

function ClientPlayerAttributesManager.getDragonLimit(self: ClientPlayerAttributesManager): number
	return (self.attributes[PlayerAttributeKeys.DRAGON_LIMIT] :: number?) or EggSlotConfig.DRAGON_LIMIT
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
