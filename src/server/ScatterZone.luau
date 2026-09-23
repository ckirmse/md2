--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local ScatterZone = {}
ScatterZone.__index = setmetatable(ScatterZone, super)

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local Timer = require("./Timer")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local eggLootTablesData = require("@game/ServerScriptService/GameData/Control/EggLootTables")

export type ScatterZoneFields = Types.ScatterZoneFields
export type ScatterZone = Types.ScatterZone

local function pickWeightedEggName(biomeIndex: number): string?
	local weights = eggLootTablesData.standardLootByBiome[biomeIndex] or eggLootTablesData.standardLootByBiome[1]
	if not weights then
		return nil
	end
	return utils.pickWeightedRandom(weights)
end

function ScatterZone.getBiomeIndex(self: ScatterZone): number
	return (self:getObj():GetAttribute(Attributes.BIOME_INDEX) :: number?) or 1
end

function ScatterZone.getMaxEggsInZone(self: ScatterZone): number
	local override = self:getObj():GetAttribute(Attributes.MAX_EGGS_IN_ZONE) :: number?
	return override or self:getObjectData().maxEggsInZone
end

function ScatterZone.getRespawnSec(self: ScatterZone): number
	local override = self:getObj():GetAttribute(Attributes.RESPAWN_SEC) :: number?
	return override or self:getObjectData().respawnSec
end

function ScatterZone.getMinEggSpacing(self: ScatterZone): number
	local override = self:getObj():GetAttribute(Attributes.MIN_EGG_SPACING) :: number?
	return override or self:getObjectData().minEggSpacing
end

function ScatterZone.getCurrentEggCount(self: ScatterZone): number
	local count = 0
	for _ in self.spawnedEggItemIds do
		count += 1
	end
	return count
end

function ScatterZone.getRandomPositionInBounds(self: ScatterZone): Vector3
	local part = self:getObj() :: BasePart
	local halfSize = part.Size / 2
	local localOffset = Vector3.new(
		(math.random() * 2 - 1) * halfSize.X,
		0,
		(math.random() * 2 - 1) * halfSize.Z
	)
	local worldPosition = (part.CFrame * CFrame.new(localOffset)).Position
	return utils.getGroundPositionForLocation(worldPosition)
end

function ScatterZone.getDistanceToNearestEgg(self: ScatterZone, position: Vector3): number
	local nearestDistance = math.huge
	for itemId in self.spawnedEggItemIds do
		local item = itemManager:getItemById(itemId)
		if not item then
			continue
		end
		local distance = (item:getObj():GetPivot().Position - position).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
		end
	end
	return nearestDistance
end

-- keeps the best of a few random candidates, farthest from any existing egg in the zone
function ScatterZone.findSpawnPosition(self: ScatterZone): Vector3
	local minSpacing = self:getMinEggSpacing()

	local bestPosition = self:getRandomPositionInBounds()
	local bestDistance = self:getDistanceToNearestEgg(bestPosition)

	for _ = 2, Constants.SCATTER_ZONE_MAX_POSITION_ATTEMPTS do
		if bestDistance >= minSpacing then
			break
		end

		local candidatePosition = self:getRandomPositionInBounds()
		local candidateDistance = self:getDistanceToNearestEgg(candidatePosition)
		if candidateDistance > bestDistance then
			bestPosition = candidatePosition
			bestDistance = candidateDistance
		end
	end

	return bestPosition
end

function ScatterZone.trySpawnOneEgg(self: ScatterZone): boolean
	local biomeIndex = self:getBiomeIndex()
	local eggItemName = pickWeightedEggName(biomeIndex)
	if not eggItemName then
		warn("scatter zone has no loot table entries for its biome", biomeIndex, self:getObjectName())
		return false
	end

	local item = itemManager:createItem(eggItemName, Constants.UNOWNED_USER_ID)
	if not item then
		warn("scatter zone failed to create egg item", eggItemName, self:getObjectName())
		return false
	end

	local groundPosition = self:findSpawnPosition() + Vector3.new(0, item:getPart().Size.Y / 2, 0)
	item:getObj():PivotTo(CFrame.new(groundPosition))
	item:setPreventSettling()
	item:getObj().Parent = workspace
	item:getObj():SetAttribute(Attributes.SOURCE_BIOME_INDEX, biomeIndex)
	item:getObj():SetAttribute(Attributes.SOURCE_SCATTER_ZONE_ID, self:getObjectId())

	self.spawnedEggItemIds[item:getItemId()] = true

	return true
end

function ScatterZone.topUp(self: ScatterZone): boolean
	local didSpawnAny = false
	local maxCount = self:getMaxEggsInZone()
	while self:getCurrentEggCount() < maxCount do
		if not self:trySpawnOneEgg() then
			break
		end
		didSpawnAny = true
	end
	return didSpawnAny
end

function ScatterZone.notifyEggTaken(self: ScatterZone, itemId: number)
	self.spawnedEggItemIds[itemId] = nil
end

function ScatterZone.beginRefillLoop(self: ScatterZone)
	local respawnSec = self:getRespawnSec()
	self.refillTimer = Timer.new(respawnSec, function()
		if self:topUp() then
			gameController:sendSystemMessageToAllPlayers(self:getObjectName() .. " eggs have respawned!")
		end
		self:beginRefillLoop()
	end)
end

function ScatterZone.destroy(self: ScatterZone)
	if self.refillTimer then
		self.refillTimer:cancel()
		self.refillTimer = nil
	end
	-- self.obj is the original Studio-placed marker, never a clone -- it must never be destroyed here
end

function ScatterZone.new(objectData: any, marker: BasePart, objectId: number): ScatterZone
	local self: ScatterZone = setmetatable({
		objectName = objectData.name,
		objectId = objectId,
		obj = marker,
		spawnedEggItemIds = {},
	} :: ScatterZoneFields, ScatterZone) :: any

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())

	self:topUp()
	self:beginRefillLoop()

	return self
end

function ScatterZone.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

return ScatterZone
