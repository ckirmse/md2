--!strict

local ClientPlotLuckManager = {}
ClientPlotLuckManager.__index = ClientPlotLuckManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Level = workspace:WaitForChild("Level")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local teleporters = require("./Teleporters")

local LUCK_SIGN_NAME = "LuckSign"
local RESOLVE_ATTEMPTS = 40
local RESOLVE_INTERVAL = 0.5

export type ClientPlotLuckManager = typeof(setmetatable({}, ClientPlotLuckManager))

function ClientPlotLuckManager.resolveLuckSign(self: ClientPlotLuckManager)
	local plotIndex: number?
	for _ = 1, RESOLVE_ATTEMPTS do
		plotIndex = teleporters:getPlotIndex()
		if plotIndex then
			break
		end
		task.wait(RESOLVE_INTERVAL)
	end

	if not plotIndex then
		warn("ClientPlotLuckManager: no plot index, plot luck upgrade disabled")
		return
	end

	local luckSign: Instance?
	for _ = 1, RESOLVE_ATTEMPTS do
		luckSign = utils.findFirstDescendantWithNameAndAttribute(Level, LUCK_SIGN_NAME, Attributes.INDEX, plotIndex)
		if luckSign then
			break
		end
		task.wait(RESOLVE_INTERVAL)
	end

	if not luckSign then
		warn("ClientPlotLuckManager: could not find LuckSign for plot", plotIndex)
		return
	end

	local upgradeButton: any = utils.findFirstDescendant(luckSign, "UpgradeButton")
	upgradeButton.Activated:Connect(function()
		RemoteEvents.TryUpgradePlotLuck:FireServer(false)
	end)

	local upgradeMaxButton: any = utils.findFirstDescendant(luckSign, "UpgradeMaxButton")
	upgradeMaxButton.Activated:Connect(function()
		RemoteEvents.TryUpgradePlotLuck:FireServer(true)
	end)
end

function ClientPlotLuckManager.init(self: ClientPlotLuckManager)
	task.spawn(function()
		self:resolveLuckSign()
	end)
end

function ClientPlotLuckManager.new(): ClientPlotLuckManager
	return setmetatable({}, ClientPlotLuckManager)
end

local singleton = ClientPlotLuckManager.new()

return singleton
