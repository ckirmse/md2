--!strict

local ScatterZoneManager = {}
ScatterZoneManager.__index = ScatterZoneManager

local collectionService = game:GetService("CollectionService")

local ScatterZone = require("./ScatterZone")
local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

type ScatterZoneManagerFields = {
	zoneMap: { [number]: Types.ScatterZone },
}

export type ScatterZoneManager = typeof(setmetatable({} :: ScatterZoneManagerFields, ScatterZoneManager))

local function pickRandomScatterZoneName(): string?
	local zoneNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", "scatterZone")
	if #zoneNames == 0 then
		return nil
	end
	return zoneNames[math.random(1, #zoneNames)]
end

function ScatterZoneManager.createZoneFromMarker(self: ScatterZoneManager, marker: Instance)
	if not marker:IsA("BasePart") then
		warn("egg scatter zone marker must be a BasePart, its Size defines the zone bounds", marker)
		return
	end

	local zoneName = marker:GetAttribute(Attributes.SCATTER_ZONE_NAME) :: string?
	if not zoneName or zoneName == "" then
		-- no explicit override -- pick randomly from every registered scatter zone type
		zoneName = pickRandomScatterZoneName()
	end
	if not zoneName then
		warn("egg scatter zone marker has no ScatterZoneName override and no zone types are registered", marker)
		return
	end

	local objectData = objectDataStore:getObjectDataByName(zoneName)
	if not objectData then
		warn("egg scatter zone marker references unknown zone type", zoneName, marker)
		return
	end

	local objectId = gameController:getNextObjectId()
	local zone = ScatterZone.new(objectData, marker :: BasePart, objectId)
	self.zoneMap[objectId] = zone
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

function ScatterZoneManager.new(): ScatterZoneManager
	local self: ScatterZoneManager = setmetatable({
		zoneMap = {},
	} :: ScatterZoneManagerFields, ScatterZoneManager)

	return self
end

function ScatterZoneManager.initClass(deps: any)
	gameController = deps.gameController
end

function ScatterZoneManager.init(self: ScatterZoneManager)
	for _, marker in collectionService:GetTagged(Tags.EGG_SCATTER_ZONE) do
		self:createZoneFromMarker(marker)
	end
end

local singleton = ScatterZoneManager.new()

return singleton
