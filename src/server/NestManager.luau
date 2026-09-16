--!strict

local NestManager = {}
NestManager.__index = NestManager

local collectionService = game:GetService("CollectionService")

local Nest = require("./Nest")
local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

type NestManagerFields = {
	nestMap: { [number]: Types.Nest },
}

export type NestManager = typeof(setmetatable({} :: NestManagerFields, NestManager))

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

local function pickRandomNestName(): string?
	local nestNames = objectDataStore:getAllObjectNamesByDataKeyValue("type", "nest")
	if #nestNames == 0 then
		return nil
	end
	return nestNames[math.random(1, #nestNames)]
end

function NestManager.createNestFromMarker(self: NestManager, marker: Instance)
	local nestName = marker:GetAttribute(Attributes.NEST_NAME) :: string?
	if not nestName or nestName == "" then
		-- no explicit override -- pick randomly from every registered nest type
		nestName = pickRandomNestName()
	end
	if not nestName then
		warn("nest spawn marker has no NestName override and no nest types are registered", marker)
		return
	end

	local objectData = objectDataStore:getObjectDataByName(nestName)
	if not objectData then
		warn("nest spawn marker references unknown nest", nestName, marker)
		return
	end

	local objectDataType = objectDataStore:getObjectDataTypeByName(nestName) :: any
	local template = objectDataType:getTemplate()
	if not template then
		warn("nest", nestName, "has no template", marker)
		return
	end

	local cframe = getMarkerCFrame(marker)
	if not cframe then
		warn("nest spawn marker is not an Attachment, BasePart, or Model", marker)
		return
	end

	local objectId = gameController:getNextObjectId()
	local nest = Nest.new(objectData, cframe, objectId)
	self.nestMap[objectId] = nest

	local obj = nest:getObj()
	obj.Parent = workspace
end

function NestManager.getNestByObjectId(self: NestManager, objectId: number): Types.Nest?
	return self.nestMap[objectId]
end

function NestManager.getAllNests(self: NestManager): { Types.Nest }
	local nests = {}
	for _, nest in self.nestMap do
		table.insert(nests, nest)
	end
	return nests
end

function NestManager.new(): NestManager
	local self: NestManager = setmetatable({
		nestMap = {},
	} :: NestManagerFields, NestManager)

	return self
end

function NestManager.initClass(deps: any)
	gameController = deps.gameController
end

function NestManager.init(self: NestManager)
	for _, marker in collectionService:GetTagged(Tags.NEST_SPAWN) do
		self:createNestFromMarker(marker)
	end
end

local singleton = NestManager.new()

return singleton
