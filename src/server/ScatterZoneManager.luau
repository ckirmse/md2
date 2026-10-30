--!strict

local ScatterZoneManager = {}
ScatterZoneManager.__index = ScatterZoneManager

local ScatterZone = require("./ScatterZone")
local objectDataStore = require("./ObjectDataStore")
local Timer = require("./Timer")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local eggSpawningData = require("@game/ServerScriptService/GameData/Control/EggSpawning")

type ScatterZoneManagerFields = {
	zoneMap: { [number]: Types.ScatterZone },
	refreshTimer: Timer.Timer?,
	nextRefreshTime: number, -- server time of the next global refresh
}

export type ScatterZoneManager = typeof(setmetatable({} :: ScatterZoneManagerFields, ScatterZoneManager))

local function pickRandomScatterZoneName(): string?
	local zoneNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", "scatterZone")
	if #zoneNames == 0 then
		return nil
	end
	return zoneNames[math.random(1, #zoneNames)]
end

function ScatterZoneManager.createZoneFromMarker(self: ScatterZoneManager, marker: Instance, isIslandZone: boolean?): Types.ScatterZone?
	if not marker:IsA("BasePart") then
		warn("egg scatter zone marker must be a BasePart, its Size defines the zone bounds", marker)
		return nil
	end

	local zoneName = marker:GetAttribute(Attributes.SCATTER_ZONE_NAME) :: string?
	if not zoneName or zoneName == "" then
		-- no explicit override -- pick randomly from every registered scatter zone type
		zoneName = pickRandomScatterZoneName()
	end
	if not zoneName then
		warn("egg scatter zone marker has no ScatterZoneName override and no zone types are registered", marker)
		return nil
	end

	local objectData = objectDataStore:getObjectDataByName(zoneName)
	if not objectData then
		warn("egg scatter zone marker references unknown zone type", zoneName, marker)
		return nil
	end

	local objectId = gameController:getNextObjectId()
	local zone = ScatterZone.new(objectData, marker :: BasePart, objectId, isIslandZone)
	self.zoneMap[objectId] = zone
	return zone
end

-- the number of eggs the whole world should hold, from Control/EggSpawning; 0 means island zones are off
function ScatterZoneManager.getTargetTotalEggs(self: ScatterZoneManager): number
	local target = eggSpawningData.targetTotalEggs
	if type(target) ~= "number" or target <= 0 then
		return 0
	end
	return math.floor(target)
end

-- splits the egg target over the island markers by area; the largest remainders get the leftover eggs,
-- so the total is exactly the target (a marker may get 0)
function ScatterZoneManager.planIslandZoneEggs(self: ScatterZoneManager, markers: { BasePart }): { { marker: BasePart, count: number } }
	local target = self:getTargetTotalEggs()
	local plan: { { marker: BasePart, count: number } } = {}
	if target <= 0 or #markers == 0 then
		return plan
	end

	local totalArea = 0
	for _, marker in markers do
		totalArea += marker.Size.X * marker.Size.Z
	end
	if totalArea <= 0 then
		return plan
	end

	local fractions: { { index: number, fraction: number } } = {}
	local assigned = 0
	for index, marker in markers do
		local exact = target * (marker.Size.X * marker.Size.Z) / totalArea
		local whole = math.floor(exact)
		plan[index] = { marker = marker, count = whole }
		assigned += whole
		table.insert(fractions, { index = index, fraction = exact - whole })
	end

	table.sort(fractions, function(a, b)
		return a.fraction > b.fraction
	end)
	for rank = 1, math.min(target - assigned, #fractions) do
		local entry = plan[fractions[rank].index]
		entry.count += 1
	end

	return plan
end

-- turns an island's EggZone marker into a scatter zone holding `count` eggs
function ScatterZoneManager.registerIslandZone(self: ScatterZoneManager, marker: BasePart, count: number, lootTableName: string?)
	if count <= 0 or not marker:IsDescendantOf(workspace) then
		return
	end

	-- the marker is only an area: keep it out of the ground raycasts and out of the way
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1

	marker:SetAttribute(Attributes.MAX_EGGS_IN_ZONE, count)
	if lootTableName then
		marker:SetAttribute(Attributes.LOOT_TABLE_NAME, lootTableName)
	end

	self:createZoneFromMarker(marker, true)
end

-- removes the zone built on this marker, with the eggs it still holds
function ScatterZoneManager.removeZoneForMarker(self: ScatterZoneManager, marker: Instance)
	for objectId, zone in self.zoneMap do
		if zone:getObj() == marker then
			zone:clearEggs()
			self.zoneMap[objectId] = nil
			return
		end
	end
end

function ScatterZoneManager.getZoneByObjectId(self: ScatterZoneManager, objectId: number): Types.ScatterZone?
	return self.zoneMap[objectId]
end

function ScatterZoneManager.getAllZones(self: ScatterZoneManager): { Types.ScatterZone }
	local zones = {}
	for _, zone in self.zoneMap do
		table.insert(zones, zone)
	end
	return zones
end

function ScatterZoneManager.pickCosmicEggSite(self: ScatterZoneManager): (number?, Vector3?)
	local zones = self:getAllZones()
	local totalArea = 0
	local areas: { number } = {}
	for index, zone in zones do
		local size = (zone:getObj() :: BasePart).Size
		areas[index] = size.X * size.Z
		totalArea += areas[index]
	end
	if totalArea <= 0 then
		return nil, nil
	end

	local roll = math.random() * totalArea
	for index, zone in zones do
		roll -= areas[index]
		if roll <= 0 or index == #zones then
			return zone:getObjectId(), zone:findSpawnPosition()
		end
	end
	return nil, nil
end

function ScatterZoneManager.spawnCosmicEggAt(self: ScatterZoneManager, zoneId: number, position: Vector3, eggName: string): number?
	local zone = self.zoneMap[zoneId]
	if not zone then
		return nil
	end
	return zone:spawnEggAt(eggName, position, false)
end

function ScatterZoneManager.refreshAllZones(self: ScatterZoneManager)
	for _, zone in self.zoneMap do
		for _, itemId in zone:getSpawnedEggItemIds() do
			local item = itemManager:getItemById(itemId)
			if item then
				itemManager:destroyItem(item)
			end
			zone:notifyEggTaken(itemId)
		end
		zone:topUp()
	end

	for _, item in itemManager:getItemsOnGroundByUserId(Constants.UNOWNED_USER_ID) do
		if item:getType() == "dragonEgg" and item:getObj():GetAttribute(Attributes.FREE_FOR_PICKUP) then
			itemManager:destroyItem(item)
		end
	end

	self:stampNextRefreshTime()
end

function ScatterZoneManager.stampNextRefreshTime(self: ScatterZoneManager)
	self.nextRefreshTime = workspace:GetServerTimeNow() + eggSpawningData.globalRefreshSec
end

function ScatterZoneManager.getNextRefreshTime(self: ScatterZoneManager): number
	return self.nextRefreshTime
end

function ScatterZoneManager.getEggWorldCounts(self: ScatterZoneManager): { any }
	local counts: { [string]: number } = {}

	for _, item in itemManager:getItemsOnGroundByUserId(Constants.UNOWNED_USER_ID) do
		if item:getType() ~= "dragonEgg" then
			continue
		end
		if item:getObj():GetAttribute(Attributes.CARRY_EXPIRES_TIME) then
			continue
		end

		local itemName = item:getItemName()
		counts[itemName] = (counts[itemName] or 0) + 1
	end

	local result = {}
	for itemName, count in counts do
		local itemData = objectDataStore:getObjectDataByName(itemName)
		table.insert(result, {
			itemName = itemName,
			count = count,
			eggBaseLuck = (itemData and itemData.eggBaseLuck) or 1,
		})
	end

	return result
end

function ScatterZoneManager.beginGlobalRefreshLoop(self: ScatterZoneManager)
	self.refreshTimer = Timer.new(eggSpawningData.globalRefreshSec, function()
		self.refreshTimer = nil
		self:refreshAllZones()
		self:beginGlobalRefreshLoop()
	end)
end

function ScatterZoneManager.new(): ScatterZoneManager
	local self: ScatterZoneManager = setmetatable({
		zoneMap = {},
		refreshTimer = nil,
		nextRefreshTime = 0,
	} :: ScatterZoneManagerFields, ScatterZoneManager)

	return self
end

function ScatterZoneManager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

function ScatterZoneManager.init(self: ScatterZoneManager)
	for _, marker in utils.getTaggedInWorkspace(Tags.EGG_SCATTER_ZONE) do
		self:createZoneFromMarker(marker)
	end

	self:stampNextRefreshTime()
	self:beginGlobalRefreshLoop()
end

local singleton = ScatterZoneManager.new()

return singleton
