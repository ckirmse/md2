--!strict

local ClientExpansionTeleporter = {}
ClientExpansionTeleporter.__index = ClientExpansionTeleporter

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlotHelpers = require("@game/ReplicatedStorage/Shared/PlotHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local cameraManager = require("./CameraManager")
local clientFtueManager = require("./ClientFtueManager")
local clientRideController = require("./ClientRideController")

local player = game:GetService("Players").LocalPlayer :: Player

-- Studio-authored templates and clones; their shapes only exist at runtime
local burstTemplate: any
local signboardTemplate: any
local teleportAudio: any
local localExpansionElements: Folder?

local VANITY_AREA_TO_EDGE_NAME: { [number]: string } = {
	[enums.VanityAreas.EXPANSION_1] = "ExpansionEdge_1",
	[enums.VanityAreas.EXPANSION_2] = "ExpansionEdge_2",
	[enums.VanityAreas.EXPANSION_3] = "ExpansionEdge_3",
	[enums.VanityAreas.EXPANSION_4] = "ExpansionEdge_4",
}

type ClientExpansionTeleporterFields = {
	expansionPrompts: { [number]: ProximityPrompt },
	expansionSignboards: { [number]: any },
}

export type ClientExpansionTeleporter = typeof(setmetatable({} :: ClientExpansionTeleporterFields, ClientExpansionTeleporter))

function ClientExpansionTeleporter.shouldPromptsBeEnabled(self: ClientExpansionTeleporter): boolean
	return not clientFtueManager:isFtueActive() and not clientRideController:isRiding()
end

function ClientExpansionTeleporter.refreshPromptVisibility(self: ClientExpansionTeleporter)
	local enabled = self:shouldPromptsBeEnabled()
	for _, prompt in self.expansionPrompts do
		prompt.Enabled = enabled
	end
	for _, signboard in self.expansionSignboards do
		signboard.Parent = if enabled then localExpansionElements else nil
	end
end

function ClientExpansionTeleporter.setupExpansion(self: ClientExpansionTeleporter, vanityArea: number, plotIndex: number)
	self:removeExpansion(vanityArea)

	local edgeName = VANITY_AREA_TO_EDGE_NAME[vanityArea]
	if not edgeName then
		warn("ClientExpansionTeleporter: no edge name for vanityArea", vanityArea)
		return
	end

	local level = workspace:FindFirstChild("Level")
	local clonedPlotElements = level and level:FindFirstChild("ClonedPlotElements")
	if not clonedPlotElements then
		warn("ClientExpansionTeleporter: ClonedPlotElements not found in workspace.Level")
		return
	end

	local edgePart: any =
		utils.findFirstDescendantWithNameAndAttribute(clonedPlotElements, edgeName, Attributes.INDEX, plotIndex)
	if not edgePart then
		warn("ClientExpansionTeleporter: edgePart not found", edgeName, "plotIndex", plotIndex)
		return
	end

	local innerPlacement = PlotHelpers.getInnerVanityPlacementByVanityArea(vanityArea) :: number
	local placementName = enums.getName(enums.VanityPlacements, innerPlacement) :: string

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ExpansionTeleportPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.RequiresLineOfSight = false
	prompt.ActionText = "Teleport"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Constants.EXPANSION_TELEPORT_ACTIVATION_DISTANCE
	prompt.Enabled = self:shouldPromptsBeEnabled()
	prompt.Parent = edgePart

	prompt.Triggered:Connect(function()
		if clientRideController:isRiding() then
			clientRideController:tryEndRiding()
			task.wait(0.1)
		end

		if not teleportAudio then
			local gameAssets = ReplicatedStorage:WaitForChild("GameAssets")
			local effects = gameAssets:WaitForChild("Effects")
			local audioParent: any = (effects:WaitForChild("TeleportAudioParent") :: any):Clone()
			audioParent.Parent = workspace
			teleportAudio = audioParent:FindFirstChild("AudioTeleport")
		end
		if teleportAudio then
			teleportAudio:Play()
		end

		local expansionModel: any = nil
		local mergePlot = level and level:FindFirstChild("MergePlot")
		if mergePlot then
			expansionModel = utils.findFirstDescendantWithNameAndAttribute(mergePlot, placementName, Attributes.INDEX, plotIndex)
		end
		if not expansionModel then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		-- the character rig's children only exist at runtime, so they are untyped here
		local hrp: any = character:FindFirstChild("HumanoidRootPart")
		local humanoid: any = character:FindFirstChild("Humanoid")
		if not hrp or not humanoid then
			return
		end

		local expansionCenter = expansionModel:GetPivot().Position
		local groundPos = utils.getGroundPositionForLocation(expansionCenter)
		if not groundPos then
			return
		end

		local teleportPos = groundPos
			+ Vector3.new(0, humanoid.HipHeight + hrp.Size.Y / 2 + Constants.EXPANSION_TELEPORT_DROP_HEIGHT, 0)
		hrp:PivotTo(CFrame.new(teleportPos) * hrp.CFrame.Rotation)
		cameraManager:moveCameraBehindPlayer()

		if not burstTemplate then
			local gameAssets = ReplicatedStorage:WaitForChild("GameAssets")
			local particleEffects = gameAssets:WaitForChild("ParticleEffects")
			burstTemplate = particleEffects:FindFirstChild("VanityUnlockParent")
		end

		local burst = burstTemplate:Clone()
		burst:PivotTo(CFrame.new(teleportPos))
		burst.Parent = workspace
		burst:FindFirstChild("Burst"):Emit(Constants.EXPANSION_TELEPORT_BURST_COUNT)
		utils.safelyDisposeOfParticleParent(burst, 0)
	end)

	self.expansionPrompts[vanityArea] = prompt

	if not signboardTemplate then
		local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
		local fixtures = gameAssets and gameAssets:FindFirstChild("Fixtures")
		signboardTemplate = fixtures and fixtures:FindFirstChild("ExpansionTeleportSign")
	end

	if signboardTemplate then
		local signboard = signboardTemplate:Clone()
		signboard:PivotTo(edgePart:GetPivot())
		signboard.Parent = localExpansionElements
		self.expansionSignboards[vanityArea] = signboard
	else
		warn("ClientExpansionTeleporter: ExpansionTeleportSign not found in GameAssets/Fixtures")
	end
end

function ClientExpansionTeleporter.removeExpansion(self: ClientExpansionTeleporter, vanityArea: number)
	local prompt = self.expansionPrompts[vanityArea]
	if prompt then
		prompt:Destroy()
		self.expansionPrompts[vanityArea] = nil
	end

	local signboard = self.expansionSignboards[vanityArea]
	if signboard then
		signboard:Destroy()
		self.expansionSignboards[vanityArea] = nil
	end
end

function ClientExpansionTeleporter.handleNotifyInit(self: ClientExpansionTeleporter, plotIndex: number)
	print("ClientExpansionTeleporter: handleNotifyInit started, plotIndex", plotIndex)

	local splendidData = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityFolder = splendidData:WaitForChild("Vanity")
	local vanityAreasFolder = vanityFolder:WaitForChild(Constants.VANITY_AREAS_NAME)

	local level = workspace:WaitForChild("Level")
	local clonedPlotElements = level:WaitForChild("ClonedPlotElements")

	for _, vanityArea in PlotHelpers.getExpansionVanityAreas() do
		local vanityAreaName = enums.getName(enums.VanityAreas, vanityArea) :: string
		local areaInst = vanityAreasFolder:FindFirstChild(vanityAreaName)
		if not areaInst then
			continue
		end

		if areaInst:GetAttribute(Attributes.VANITY_AREA_STATE) == enums.VanityAreaState.UNLOCKED then
			local edgeName = VANITY_AREA_TO_EDGE_NAME[vanityArea] :: string
			local edgePart = utils.findFirstDescendantWithNameAndAttribute(clonedPlotElements, edgeName, Attributes.INDEX, plotIndex)

			while not edgePart do
				print("ClientExpansionTeleporter: waiting for", edgeName, "to replicate")
				clonedPlotElements.DescendantAdded:Wait()
				edgePart = utils.findFirstDescendantWithNameAndAttribute(
					clonedPlotElements,
					edgeName,
					Attributes.INDEX,
					plotIndex
				)
			end

			self:setupExpansion(vanityArea, plotIndex)
		end

		areaInst:GetAttributeChangedSignal(Attributes.VANITY_AREA_STATE):Connect(function()
			local newState = areaInst:GetAttribute(Attributes.VANITY_AREA_STATE)
			if newState == enums.VanityAreaState.UNLOCKED then
				self:setupExpansion(vanityArea, plotIndex)
			else
				self:removeExpansion(vanityArea)
			end
		end)
	end

	clientFtueManager:getIsEnabledEvent():Connect(function()
		self:refreshPromptVisibility()
	end)

	clientRideController:getEvent():Connect(function()
		self:refreshPromptVisibility()
	end)
end

function ClientExpansionTeleporter.init(self: ClientExpansionTeleporter)
	local Level = workspace:WaitForChild("Level")
	local folder = Instance.new("Folder")
	folder.Name = "LocalExpansionElements"
	folder.Parent = Level
	localExpansionElements = folder
end

function ClientExpansionTeleporter.new(): ClientExpansionTeleporter
	local self = setmetatable({} :: ClientExpansionTeleporterFields, ClientExpansionTeleporter)
	self.expansionPrompts = {}
	self.expansionSignboards = {}
	return self
end

local singleton = ClientExpansionTeleporter.new()

return singleton
