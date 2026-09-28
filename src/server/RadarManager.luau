--!strict

local RadarManager = {}
RadarManager.__index = RadarManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local rideMixin = require("./RideMixin")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

type GuidanceState = {
	eggItemId: number,
	radarItemId: number,
	targetRarity: number,
	range: number,
	expiresAt: number,
}

type RadarManagerFields = {
	-- one guidance slot per (player, targetRarity) -- different radar tiers can run concurrently
	guidanceByPlayer: { [Player]: { [number]: GuidanceState } },
}

export type RadarManager = typeof(setmetatable({} :: RadarManagerFields, RadarManager))

-- source-agnostic: finds the nearest unowned, not-currently-carried dragon egg matching rarity
-- and range -- works the same whether the egg came from a Nest, a ScatterZone, or was dropped
function RadarManager.findNearestAvailableEgg(self: RadarManager, position: Vector3, rarity: number, maxRange: number): Types.DragonEgg?
	local closestEgg: Types.DragonEgg?
	local closestDistance = math.huge

	for _, egg in itemManager:getAllDragonEggs() do
		if egg:getUserId() ~= Constants.UNOWNED_USER_ID then
			continue
		end

		if egg:getObj():GetAttribute(Attributes.CARRY_EXPIRES_TIME) then
			continue
		end

		if (egg:getObj():GetAttribute(Attributes.RARITY) :: number?) ~= rarity then
			continue
		end

		local distance = (egg:getObj():GetPivot().Position - position).Magnitude
		if distance > maxRange then
			continue
		end

		if distance < closestDistance then
			closestDistance = distance
			closestEgg = egg
		end
	end

	return closestEgg
end

function RadarManager.hasActiveGuidance(self: RadarManager, player: Player, targetRarity: number): boolean
	local byRarity = self.guidanceByPlayer[player]
	return byRarity ~= nil and byRarity[targetRarity] ~= nil
end

function RadarManager.clearGuidance(self: RadarManager, player: Player, targetRarity: number, shouldConsumeRadar: boolean?)
	local byRarity = self.guidanceByPlayer[player]
	local guidance = byRarity and byRarity[targetRarity]
	if byRarity then
		byRarity[targetRarity] = nil
	end

	RemoteEvents.NotifyRadarTarget:FireClient(player, targetRarity, nil, nil)

	if shouldConsumeRadar and guidance then
		local radarItem = itemManager:getItemById(guidance.radarItemId)
		if radarItem then
			radarItem:reduceCount(1)
		end
	end
end

function RadarManager.beginGuidance(self: RadarManager, player: Player, egg: Types.DragonEgg, targetRarity: number, range: number, guidanceDurationSec: number, radarItemId: number)
	local expiresAt = workspace:GetServerTimeNow() + guidanceDurationSec

	local byRarity = self.guidanceByPlayer[player]
	if not byRarity then
		byRarity = {}
		self.guidanceByPlayer[player] = byRarity
	end

	byRarity[targetRarity] = {
		eggItemId = egg:getItemId(),
		radarItemId = radarItemId,
		targetRarity = targetRarity,
		range = range,
		expiresAt = expiresAt,
	}

	RemoteEvents.NotifyRadarTarget:FireClient(player, targetRarity, egg:getObj():GetPivot().Position, expiresAt)
end

function RadarManager.tickGuidance(self: RadarManager, player: Player, guidance: GuidanceState)
	if workspace:GetServerTimeNow() >= guidance.expiresAt then
		self:clearGuidance(player, guidance.targetRarity, true)
		gameController:sendSystemMessageToPlayer(player, "Your radar has expired")
		return
	end

	local egg = itemManager:getItemById(guidance.eggItemId)
	if egg and egg:getUserId() == Constants.UNOWNED_USER_ID and not egg:getObj():GetAttribute(Attributes.CARRY_EXPIRES_TIME) then
		-- still sitting untouched, nothing to do
		return
	end

	-- the tracked egg is no longer sitting available -- did this player pick it up themselves?
	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if dragon and dragon:getObj():GetAttribute(Attributes.CARRIED_EGG_ITEM_ID) == guidance.eggItemId then
		self:clearGuidance(player, guidance.targetRarity, true)
		gameController:sendSystemMessageToPlayer(player, "You found the egg!")
		return
	end

	-- someone else took it, or it broke -- redirect to another matching-rarity egg
	local character = player.Character
	local humanoidRootPart = character and (character :: any):FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local position = (humanoidRootPart :: BasePart).Position
	local newEgg = self:findNearestAvailableEgg(position, guidance.targetRarity, guidance.range)

	if not newEgg then
		self:clearGuidance(player, guidance.targetRarity)
		gameController:sendSystemMessageToPlayer(
			player,
			string.format("Your %s egg was taken and no others are in range", enums.getPublicName(enums.Rarity, guidance.targetRarity))
		)
		return
	end

	guidance.eggItemId = newEgg:getItemId()

	RemoteEvents.NotifyRadarTarget:FireClient(player, guidance.targetRarity, newEgg:getObj():GetPivot().Position, guidance.expiresAt)

	gameController:sendSystemMessageToPlayer(
		player,
		string.format("Your target egg was taken -- redirecting to another %s egg", enums.getPublicName(enums.Rarity, guidance.targetRarity))
	)
end

function RadarManager.tickPlayer(self: RadarManager, player: Player)
	local byRarity = self.guidanceByPlayer[player]
	if not byRarity then
		return
	end

	-- snapshot first -- tickGuidance can mutate/remove entries from byRarity mid-loop
	local guidances = {}
	for _, guidance in byRarity do
		table.insert(guidances, guidance)
	end

	for _, guidance in guidances do
		self:tickGuidance(player, guidance)
	end
end

function RadarManager.notifyRemovePlayer(self: RadarManager, player: Player)
	self.guidanceByPlayer[player] = nil
end

function RadarManager.new(): RadarManager
	local self: RadarManager = setmetatable({
		guidanceByPlayer = {},
	} :: RadarManagerFields, RadarManager)

	return self
end

function RadarManager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

local singleton = RadarManager.new()

return singleton
