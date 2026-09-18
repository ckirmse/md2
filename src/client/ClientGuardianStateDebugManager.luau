--!strict

local ClientGuardianStateDebugManager = {}
ClientGuardianStateDebugManager.__index = ClientGuardianStateDebugManager

local collectionService = game:GetService("CollectionService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local player = game:GetService("Players").LocalPlayer :: Player

type IndicatorData = {
	billboard: BillboardGui,
	textLabel: TextLabel,
	stateChangedConnect: RBXScriptConnection,
}

type ClientGuardianStateDebugManagerFields = {
	indicatorMap: { [Instance]: IndicatorData },
}

export type ClientGuardianStateDebugManager = typeof(setmetatable({} :: ClientGuardianStateDebugManagerFields, ClientGuardianStateDebugManager))

function ClientGuardianStateDebugManager.updateText(self: ClientGuardianStateDebugManager, guardian: Instance, textLabel: TextLabel)
	local state = guardian:GetAttribute(Attributes.GUARDIAN_STATE) :: number?
	textLabel.Text = enums.getName(enums.GuardianState, state) or "?"
end

function ClientGuardianStateDebugManager.notifyNewInstance(self: ClientGuardianStateDebugManager, guardian: Instance)
	if self.indicatorMap[guardian] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuardianStateDebug"
	billboard.Size = UDim2.new(7.8, 0, 1.95, 0)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = guardian

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	textLabel.TextStrokeTransparency = 0
	textLabel.Parent = billboard

	billboard.Parent = player:WaitForChild("PlayerGui")

	local stateChangedConnect = guardian:GetAttributeChangedSignal(Attributes.GUARDIAN_STATE):Connect(function()
		self:updateText(guardian, textLabel)
	end)

	self.indicatorMap[guardian] = {
		billboard = billboard,
		textLabel = textLabel,
		stateChangedConnect = stateChangedConnect,
	}

	self:updateText(guardian, textLabel)
end

function ClientGuardianStateDebugManager.notifyRemoveInstance(self: ClientGuardianStateDebugManager, guardian: Instance)
	local indicatorData = self.indicatorMap[guardian]
	if not indicatorData then
		return
	end

	indicatorData.stateChangedConnect:Disconnect()
	indicatorData.billboard:Destroy()
	self.indicatorMap[guardian] = nil
end

function ClientGuardianStateDebugManager.new(): ClientGuardianStateDebugManager
	local self: ClientGuardianStateDebugManager = setmetatable({
		indicatorMap = {},
	} :: ClientGuardianStateDebugManagerFields, ClientGuardianStateDebugManager)

	return self
end

function ClientGuardianStateDebugManager.init(self: ClientGuardianStateDebugManager)
	collectionService:GetInstanceAddedSignal(Tags.GUARDIAN):Connect(function(guardian)
		self:notifyNewInstance(guardian)
	end)
	collectionService:GetInstanceRemovedSignal(Tags.GUARDIAN):Connect(function(guardian)
		self:notifyRemoveInstance(guardian)
	end)

	for _, guardian in collectionService:GetTagged(Tags.GUARDIAN) do
		self:notifyNewInstance(guardian)
	end
end

local singleton = ClientGuardianStateDebugManager.new()

return singleton
