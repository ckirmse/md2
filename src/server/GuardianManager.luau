--!strict

local GuardianManager = {}
GuardianManager.__index = GuardianManager

local collectionService = game:GetService("CollectionService")

local Guardian = require("./Guardian")
local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Tags = require("@game/ReplicatedStorage/Shared/Tags")

type GuardianManagerFields = {
	guardianMap: { [number]: Types.Guardian },
}

export type GuardianManager = typeof(setmetatable({} :: GuardianManagerFields, GuardianManager))

local function getMarkerCFrame(marker: Instance): CFrame?
	if marker:IsA("Attachment") then
		return (marker :: Attachment).WorldCFrame
	elseif marker:IsA("BasePart") then
		return (marker :: BasePart).CFrame
	elseif marker:IsA("Model") then
		return (marker :: Model):GetPivot()
	end
	return nil
end

function GuardianManager.createGuardianFromData(self: GuardianManager, guardianName: string, markersByName: { [string]: Instance })
	local objectData = objectDataStore:getObjectDataByName(guardianName)
	if not objectData then
		warn("unknown guardian data", guardianName)
		return
	end

	local marker = markersByName[objectData.spawnMarkerName]
	if not marker then
		warn("guardian", guardianName, "references spawn marker", objectData.spawnMarkerName, "which was not found tagged GuardianSpawn")
		return
	end

	local objectDataType = objectDataStore:getObjectDataTypeByName(guardianName) :: any
	local template = objectDataType:getTemplate()
	if not template then
		warn("guardian", guardianName, "has no template")
		return
	end

	local cframe = getMarkerCFrame(marker)
	if not cframe then
		warn("guardian spawn marker is not an Attachment, BasePart, or Model", marker)
		return
	end

	local objectId = gameController:getNextObjectId()
	local guardian = Guardian.new(objectData, cframe, objectId)
	self.guardianMap[objectId] = guardian

	local obj = guardian:getObj()
	obj.Parent = workspace
end

function GuardianManager.getGuardianByObjectId(self: GuardianManager, objectId: number): Types.Guardian?
	return self.guardianMap[objectId]
end

function GuardianManager.getAllGuardians(self: GuardianManager): { Types.Guardian }
	local guardians = {}
	for _, guardian in self.guardianMap do
		table.insert(guardians, guardian)
	end
	return guardians
end

function GuardianManager.new(): GuardianManager
	local self: GuardianManager = setmetatable({
		guardianMap = {},
	} :: GuardianManagerFields, GuardianManager)

	return self
end

function GuardianManager.initClass(deps: any)
	gameController = deps.gameController
end

function GuardianManager.init(self: GuardianManager)
	local markersByName: { [string]: Instance } = {}
	for _, marker in collectionService:GetTagged(Tags.GUARDIAN_SPAWN) do
		markersByName[marker.Name] = marker
	end

	for _, guardianName in objectDataStore:getAllObjectNamesByDataKeyValue("type", "guardian") do
		self:createGuardianFromData(guardianName, markersByName)
	end
end

local singleton = GuardianManager.new()

return singleton
