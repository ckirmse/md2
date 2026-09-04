--!strict

local ClientLuckBillboardManager = {}
ClientLuckBillboardManager.__index = ClientLuckBillboardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")

local screenGuiManager = require("./ScreenGuiManager")
local teleporters = require("./Teleporters")

local localPlotElements: Folder? = nil
-- the billboard template's shape only exists in Studio, so it is untyped here
local localBillboard: any = nil

export type ClientLuckBillboardManager = typeof(setmetatable({}, ClientLuckBillboardManager))

function ClientLuckBillboardManager.showBillboard(self: ClientLuckBillboardManager)
	if localBillboard then
		return
	end

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local fixtures = gameAssets and gameAssets:FindFirstChild("Fixtures")
	local template: any = fixtures and fixtures:FindFirstChild("LuckBillboard")
	if not template then
		warn("ClientLuckBillboardManager: LuckBillboard template not found in GameAssets/Fixtures")
		return
	end

	local plotIndex = teleporters:getPlotIndex()
	if not plotIndex then
		warn("ClientLuckBillboardManager: plot index not yet assigned")
		return
	end

	localBillboard = template:Clone()
	localBillboard:SetAttribute(Attributes.INDEX, plotIndex)

	local plotRelCFrame = PlotHelpers.translateCFrameWorldToPlot(template:GetPivot(), 1)
	localBillboard:PivotTo(PlotHelpers.translateCFramePlotToWorld(plotRelCFrame, plotIndex))
	localBillboard.Parent = localPlotElements

	local claimButton: any = utils.findFirstDescendant(localBillboard, "ClaimButton")
	if not claimButton then
		warn("ClientLuckBillboardManager: ClaimButton not found in LuckBillboard")
		return
	end

	claimButton.Activated:Connect(function()
		RemoteEvents.TryClaimLuckBillboard:FireServer()
	end)
end

function ClientLuckBillboardManager.removeBillboard(self: ClientLuckBillboardManager)
	if localBillboard then
		localBillboard:Destroy()
		localBillboard = nil
	end
end

function ClientLuckBillboardManager.notifyLuckBillboardResult(self: ClientLuckBillboardManager, isInGroup: boolean)
	if isInGroup then
		screenGuiManager:showSystemMessage("Thank you for like and join. You are provided +30% Mutation Luck.")
		task.delay(3, function()
			self:removeBillboard()
		end)
	else
		screenGuiManager:showSystemMessage("Like the game and join the group first.")
	end
end

function ClientLuckBillboardManager.init(self: ClientLuckBillboardManager)
	local Level = workspace:WaitForChild("Level")
	local folder = Instance.new("Folder")
	folder.Name = "LocalPlotElements"
	folder.Parent = Level
	localPlotElements = folder
end

function ClientLuckBillboardManager.new(): ClientLuckBillboardManager
	return setmetatable({}, ClientLuckBillboardManager)
end

local singleton = ClientLuckBillboardManager.new()
return singleton
