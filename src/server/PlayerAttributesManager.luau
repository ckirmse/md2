--!strict

local PlayerAttributesManager = {}
PlayerAttributesManager.__index = PlayerAttributesManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local ftueManager = require("./FtueManager")

local serverScriptService = game:GetService("ServerScriptService")
local startData = require(serverScriptService.GameData.Control.Start)

-- per-player attribute values are numbers and booleans
export type PlayerAttributes = { [string]: any }

type PlayerAttributesManagerFields = {
	attributes: { [Player]: PlayerAttributes },
}

export type PlayerAttributesManager = typeof(setmetatable({} :: PlayerAttributesManagerFields, PlayerAttributesManager))

function PlayerAttributesManager.set(self: PlayerAttributesManager, player: Player?, key: string, value: any)
	if not player then
		warn("cannot set attribute for nil player", key, value)
		return
	end

	if not self.attributes[player] then
		warn("cannot set player attribute when player not added", player, key, value)
		return
	end

	self.attributes[player][key] = value

	RemoteEvents.NotifyPlayerAttributeChange:FireClient(player, key, value)

	if key == PlayerAttributeKeys.COINS then
		ftueManager:notifyCoinsCountChangedForPlayer(player, value)
	end

	if key == PlayerAttributeKeys.GEMS_NATURE then
		ftueManager:notifyGemsCountChangedForPlayer(player, key, value)
	end

end

function PlayerAttributesManager.addWholeNumber(self: PlayerAttributesManager, player: Player?, key: string, diff: number)
	if not player then
		warn("cannot add attribute for nil player", key, diff)
		return
	end

	if not self.attributes[player] then
		warn("cannot add player attribute when player not added", player, key, diff)
		return
	end

	if typeof(diff) ~= "number" then
		warn("pdm add whole number given non-number", diff)
		return
	end

	if diff ~= math.floor(diff) then
		warn("pdm add whole number given non-integer", diff)
		return
	end

	if diff < 0 then
		warn("pdm add whole number given negative number", diff)
		return
	end

	self:set(player, key, self.attributes[player][key] + diff)
end

function PlayerAttributesManager.subtractWholeNumber(self: PlayerAttributesManager, player: Player?, key: string, diff: number)
	if not player then
		warn("cannot sub attribute for nil player", key, diff)
		return
	end

	if not self.attributes[player] then
		warn("cannot sub player attribute when player not added", player, key, diff)
		return
	end

	if typeof(diff) ~= "number" then
		warn("pdm sub whole number given non-number", diff)
		return
	end

	if diff ~= math.floor(diff) then
		warn("sub add whole number given non-integer", diff)
		return
	end

	if diff < 0 then
		warn("pdm sub whole number given negative number", diff)
		return
	end

	self:set(player, key, self.attributes[player][key] - diff)
end

function PlayerAttributesManager.get(self: PlayerAttributesManager, player: Player?, key: string): any
	if not player then
		warn("cannot get attribute for nil player", key)
		return
	end

	if not self.attributes[player] then
		warn("cannot get player attribute when player not added", player, key)
		return nil
	end

	return self.attributes[player][key]
end

function PlayerAttributesManager.getSaveDataForPlayer(self: PlayerAttributesManager, player: Player): PlayerAttributes?
	return self.attributes[player]
end

function PlayerAttributesManager.getClientAttributesForPlayer(self: PlayerAttributesManager, player: Player): PlayerAttributes?
	return self.attributes[player]
end

function PlayerAttributesManager.resetAttributes(self: PlayerAttributesManager, player: Player)
	self.attributes[player][PlayerAttributeKeys.COINS] = startData.coins
	self.attributes[player][PlayerAttributeKeys.TOTAL_DRAGON_POWER] = 0
	self.attributes[player][PlayerAttributeKeys.IS_UNLOCKED_FIRE] = false
	self.attributes[player][PlayerAttributeKeys.IS_UNLOCKED_NATURE] = true
	self.attributes[player][PlayerAttributeKeys.IS_UNLOCKED_AIR] = false
	self.attributes[player][PlayerAttributeKeys.IS_UNLOCKED_WATER] = false
	self.attributes[player][PlayerAttributeKeys.LEVEL_FIRE] = 1
	self.attributes[player][PlayerAttributeKeys.LEVEL_NATURE] = 1
	self.attributes[player][PlayerAttributeKeys.LEVEL_WATER] = 1
	self.attributes[player][PlayerAttributeKeys.LEVEL_AIR] = 1
	self.attributes[player][PlayerAttributeKeys.XP_FIRE] = 0
	self.attributes[player][PlayerAttributeKeys.XP_NATURE] = 0
	self.attributes[player][PlayerAttributeKeys.XP_WATER] = 0
	self.attributes[player][PlayerAttributeKeys.XP_AIR] = 0
	self.attributes[player][PlayerAttributeKeys.GEMS_FIRE] = 0
	self.attributes[player][PlayerAttributeKeys.GEMS_NATURE] = 0
	self.attributes[player][PlayerAttributeKeys.GEMS_WATER] = 0
	self.attributes[player][PlayerAttributeKeys.GEMS_AIR] = 0
	self.attributes[player][PlayerAttributeKeys.APPLY_FLAME_FIRE] = 0
	self.attributes[player][PlayerAttributeKeys.APPLY_FLAME_NATURE] = 0
	self.attributes[player][PlayerAttributeKeys.APPLY_FLAME_WATER] = 0
	self.attributes[player][PlayerAttributeKeys.APPLY_FLAME_AIR] = 0

	self.attributes[player][PlayerAttributeKeys.BACKGROUND_MUSIC_ENABLED] = true
	self.attributes[player][PlayerAttributeKeys.SOUND_EFFECTS_ENABLED] = true
end

function PlayerAttributesManager.notifyAddPlayer(self: PlayerAttributesManager, player: Player)
	self.attributes[player] = {}

	self:resetAttributes(player)
end

local GEM_KEYS = {
	PlayerAttributeKeys.GEMS_FIRE,
	PlayerAttributeKeys.GEMS_NATURE,
	PlayerAttributeKeys.GEMS_WATER,
	PlayerAttributeKeys.GEMS_AIR,
}

function PlayerAttributesManager.loadSaveData(self: PlayerAttributesManager, player: Player, playerAttributes: PlayerAttributes?)
	if playerAttributes then
		-- maybe should only look for specific keys we still support? lots to think about
		for key, value in playerAttributes do
			self.attributes[player][key] = value
		end
	end

	for _, key in GEM_KEYS do
		local v = self.attributes[player][key]
		if typeof(v) == "number" and v < 0 then
			warn("fixing negative gem count for player", player, key, v)
			self.attributes[player][key] = 0
		end
	end
end

function PlayerAttributesManager.notifyRemovePlayer(self: PlayerAttributesManager, player: Player)
	self.attributes[player] = nil
end

function PlayerAttributesManager.doesHavePlayer(self: PlayerAttributesManager, player: Player): boolean
	return self.attributes[player] ~= nil
end

function PlayerAttributesManager.new(): PlayerAttributesManager
	local self: PlayerAttributesManager = setmetatable({
		attributes = {},
	} :: PlayerAttributesManagerFields, PlayerAttributesManager)

	return self
end

local singleton = PlayerAttributesManager.new()

return singleton
