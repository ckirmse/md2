--!strict

local ClientBiomeGateManager = {}
ClientBiomeGateManager.__index = ClientBiomeGateManager

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BiomeData = require("@game/ReplicatedStorage/Shared/BiomeData")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local clientRideController = require("./ClientRideController")

type IndicatorData = {
	marker: Instance,
	requiredSpeed: number,
	textLabel: TextLabel,
}

type ClientBiomeGateManagerFields = {
	indicatorMap: { [Instance]: IndicatorData },
}

export type ClientBiomeGateManager = typeof(setmetatable({} :: ClientBiomeGateManagerFields, ClientBiomeGateManager))

local function findGateForBiome(biomeIndex: number): BiomeData.BiomeGate?
	for _, gate in BiomeData.GATES do
		if gate.biomeIndex == biomeIndex then
			return gate
		end
	end
	return nil
end

function ClientBiomeGateManager.updateBillboard(self: ClientBiomeGateManager, indicatorData: IndicatorData)
	local color = BiomeData.SPEED_GATE_NEUTRAL_COLOR
	if clientRideController:isRiding() then
		local speedStat = clientRideController:getRidingObj():GetAttribute(Attributes.DRAGON_SPEED_STAT) :: number?
		if speedStat then
			color = if speedStat >= indicatorData.requiredSpeed then BiomeData.SPEED_GATE_PASS_COLOR else BiomeData.SPEED_GATE_FAIL_COLOR
		end
	end
	if color ~= indicatorData.textLabel.TextColor3 then
		indicatorData.textLabel.TextColor3 = color
	end
end

function ClientBiomeGateManager.notifyNewInstance(self: ClientBiomeGateManager, marker: Instance)
	if self.indicatorMap[marker] then
		return
	end

	local biomeIndex = marker:GetAttribute(Attributes.BIOME_INDEX) :: number?
	if not biomeIndex then
		warn("biome gate marker missing BiomeIndex attribute", marker)
		return
	end

	local gate = findGateForBiome(biomeIndex)
	if not gate or not gate.speedGate then
		warn("biome gate marker's biome has no speed gate", marker, biomeIndex)
		return
	end

	local surfaceGui = marker:FindFirstChild("SurfaceGui")
	local textLabel = surfaceGui and surfaceGui:FindFirstChild("RequiredSpeedText")
	if not textLabel then
		warn("biome gate marker is missing a SurfaceGui.RequiredSpeedText", marker)
		return
	end

	textLabel.Text = string.format("Speed %d Required", gate.speedGate)

	self.indicatorMap[marker] = {
		marker = marker,
		requiredSpeed = gate.speedGate,
		textLabel = textLabel :: TextLabel,
	}

	self:updateBillboard(self.indicatorMap[marker] :: IndicatorData)
end

function ClientBiomeGateManager.notifyRemoveInstance(self: ClientBiomeGateManager, marker: Instance)
	self.indicatorMap[marker] = nil
end

function ClientBiomeGateManager.new(): ClientBiomeGateManager
	local self: ClientBiomeGateManager = setmetatable({
		indicatorMap = {},
	} :: ClientBiomeGateManagerFields, ClientBiomeGateManager)

	return self
end

function ClientBiomeGateManager.init(self: ClientBiomeGateManager)
	collectionService:GetInstanceAddedSignal(Tags.BIOME_GATE_SPAWN):Connect(function(marker)
		self:notifyNewInstance(marker)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.BIOME_GATE_SPAWN):Connect(function(marker)
		self:notifyRemoveInstance(marker)
	end)

	for _, marker in collectionService:GetTagged(Tags.BIOME_GATE_SPAWN) do
		self:notifyNewInstance(marker)
	end

	runService.Heartbeat:Connect(function()
		for _, indicatorData in self.indicatorMap do
			self:updateBillboard(indicatorData)
		end
	end)
end

local singleton = ClientBiomeGateManager.new()

return singleton
