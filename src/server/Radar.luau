--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local Radar = {}
Radar.__index = setmetatable(Radar, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local radarManager = require("./RadarManager")
local weatherEventManager = require("./WeatherEventManager")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local RadarKind = require("@game/ReplicatedStorage/Shared/RadarKind")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")


export type RadarFields = Types.RadarFields
export type Radar = Types.Radar

function Radar.getDataDumpString(self: Radar): string
	local text = super.getDataDumpString(self)

	return text
end

function Radar.notifyParentWorkspace(self: Radar)
	if self:getIsParentingOnLoad() or self.doPreventSettling then
		self.doPreventSettling = false

		self:getPart().Anchored = true

		self:setVenueWorkspaceAvailable()
		return
	end

	self:settleOnGroundInWorkspace(
		function()
		end
	)
end

function Radar.notifyParentPlayer(self: Radar)
	super.notifyParentPlayer(self)
end

function Radar.canBePickedUp(self: Radar): boolean
	return true
end

function Radar.setPreventSettling(self: Radar)
	self.doPreventSettling = true
end

-- overridden without calling super: the base behavior for a held tool's Activated event is to
-- drop the item in the world (Item.notifyToolActivated -> Item.activate); Radar searches instead.
function Radar.notifyToolActivated(self: Radar)
	local player = self:getPlayer()
	if not player then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = (character :: any):FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local itemData = self:getItemData()
	local targetsCosmic = itemData.targetsCosmic == true
	local label = radarManager:getKindLabel(itemData.targetRarity, targetsCosmic)

	if targetsCosmic and not weatherEventManager:isWeatherActive(enums.Weather.STARLIGHT) then
		gameController:sendSystemMessageToPlayer(player, "The Cosmic radar only works during Starlight")
		return
	end

	if radarManager:hasActiveGuidance(player, RadarKind.get(itemData.targetRarity, targetsCosmic)) then
		gameController:sendSystemMessageToPlayer(player, string.format("Your %s radar is already active", label))
		return
	end

	local position = (humanoidRootPart :: BasePart).Position

	local egg = radarManager:findNearestAvailableEgg(position, itemData.targetRarity, targetsCosmic)

	if not egg then
		gameController:sendSystemMessageToPlayer(player, string.format("No %s eggs are on the map", label))
		return
	end

	radarManager:beginGuidance(player, egg, itemData, self:getItemId())
end

function Radar.getSaveData(self: Radar, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	return retval
end

function Radar.loadSaveData(self: Radar, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)
end

function Radar.init(self: Radar)
	collectionService:AddTag(self:getObj(), Tags.RADAR)
end

function Radar.notifyNewClone(self: Radar)
	super.notifyNewClone(self)

	self:init()
end

function Radar.new(itemId: number, itemName: string, userId: number): Radar
	local self = (setmetatable(super.new(itemId, itemName, userId), Radar) :: any) :: Radar

	self:init()

	return self
end

function Radar.initClass(deps: any)
	gameController = deps.gameController
end

return Radar
