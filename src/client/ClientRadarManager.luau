--!strict

local ClientRadarManager = {}
ClientRadarManager.__index = ClientRadarManager

local runService = game:GetService("RunService")
local playersService = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the templates' shapes only exist in Studio, so they are untyped here
local Arrow3D: any = UX:WaitForChild("Arrow3D")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = playersService.LocalPlayer :: Player

local ARROW_HEIGHT_OFFSET = 3
local ARROW_TRANSPARENCY = 0.25
local ARROW_SCALE = Vector3.new(1.5, 3, 0.25)

local ARROW_BOB_AMPLITUDE = 0.5
local ARROW_BOB_SPEED = 2

local ARROW_CORRECTION_PITCH_DEG = 90
local ARROW_CORRECTION_YAW_DEG = 0
local ARROW_CORRECTION_ROLL_DEG = 0

local METERS_PER_STUD = 0.28

local ON_TARGET_ANGLE_DEG = 30
local OFF_TARGET_ANGLE_DEG = 150

local COLOR_ON_TARGET = Color3.fromRGB(16, 240, 16)
local COLOR_PARTLY_OFF = Color3.fromRGB(240, 220, 16)
local COLOR_OFF_TARGET = Color3.fromRGB(240, 16, 16)
local COLOR_TIME_REMAINING = Color3.fromRGB(240, 16, 16)

type TargetState = {
	position: Vector3,
	expiresAt: number?,
}

type ClientRadarManagerFields = {
	arrow: any?, -- Arrow3D clone
	billboard: BillboardGui?,
	distanceLabel: TextLabel?,
	timeLabel: TextLabel?,
	targetsByRarity: { [number]: TargetState },
}

export type ClientRadarManager = typeof(setmetatable({} :: ClientRadarManagerFields, ClientRadarManager))

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function getColorForAngleDeg(angleDeg: number): Color3
	if angleDeg <= ON_TARGET_ANGLE_DEG then
		return COLOR_ON_TARGET
	elseif angleDeg >= OFF_TARGET_ANGLE_DEG then
		return COLOR_OFF_TARGET
	end
	return COLOR_PARTLY_OFF
end

local function applyLabelStroke(label: TextLabel)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
end

function ClientRadarManager.hasActiveGuidanceForRarity(self: ClientRadarManager, rarity: number): boolean
	return self.targetsByRarity[rarity] ~= nil
end

function ClientRadarManager.ensureArrow(self: ClientRadarManager)
	if self.arrow then
		return
	end

	local arrow = Arrow3D:Clone()
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Transparency = ARROW_TRANSPARENCY
	arrow.Parent = nil

	arrow.Size = Vector3.new(ARROW_SCALE.X, ARROW_SCALE.Y, ARROW_SCALE.Z)

	self.arrow = arrow
end

function ClientRadarManager.ensureBillboard(self: ClientRadarManager)
	if self.billboard then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RadarStatusBillboard"
	billboard.Size = UDim2.fromOffset(200, 70)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = true
	billboard.Parent = nil

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "DistanceLabel"
	distanceLabel.Position = UDim2.fromOffset(0, 0)
	distanceLabel.Size = UDim2.fromOffset(200, 30)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.TextTransparency = 0
	distanceLabel.TextScaled = true
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.TextColor3 = COLOR_PARTLY_OFF
	distanceLabel.Text = ""
	distanceLabel.Parent = billboard
	applyLabelStroke(distanceLabel)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.Position = UDim2.fromOffset(0, 34)
	timeLabel.Size = UDim2.fromOffset(200, 30)
	timeLabel.BackgroundTransparency = 1
	timeLabel.TextTransparency = 0
	timeLabel.TextScaled = true
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.TextColor3 = COLOR_TIME_REMAINING
	timeLabel.Text = ""
	timeLabel.Parent = billboard
	applyLabelStroke(timeLabel)

	self.billboard = billboard
	self.distanceLabel = distanceLabel
	self.timeLabel = timeLabel
end

function ClientRadarManager.hideIndicators(self: ClientRadarManager)
	local arrow = self.arrow
	if arrow and arrow.Parent then
		arrow.Parent = nil
	end

	local billboard = self.billboard
	if billboard and billboard.Parent then
		billboard.Parent = nil
	end
end

function ClientRadarManager.update(self: ClientRadarManager)
	local character = player.Character
	if not character then
		self:hideIndicators()
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		self:hideIndicators()
		return
	end

	local tool = utils.getHoldingToolWithHandle(player)
	local isHoldingRadar = tool ~= nil and tool:GetAttribute(Attributes.ITEM_TYPE) == "radar"
	if not isHoldingRadar then
		self:hideIndicators()
		return
	end

	local heldRarity = (tool :: any):GetAttribute(Attributes.RARITY) :: number?
	local target = heldRarity and self.targetsByRarity[heldRarity]
	if not target then
		self:hideIndicators()
		return
	end

	local targetPosition = target.position
	local rootPart = humanoidRootPart :: BasePart

	self:ensureArrow()
	local arrow = self.arrow :: any

	local head = character:FindFirstChild("Head") :: BasePart?
	local bobOffset = math.sin(os.clock() * ARROW_BOB_SPEED) * ARROW_BOB_AMPLITUDE
	local originPosition = (head or rootPart).Position + Vector3.new(0, ARROW_HEIGHT_OFFSET + bobOffset, 0)

	local toTargetVector = targetPosition - originPosition
	local toTargetFull = if toTargetVector.Magnitude > 1e-3 then toTargetVector.Unit else rootPart.CFrame.LookVector

	arrow.CFrame = CFrame.lookAt(originPosition, originPosition + toTargetFull)
		* CFrame.Angles(
			math.rad(ARROW_CORRECTION_PITCH_DEG),
			math.rad(ARROW_CORRECTION_YAW_DEG),
			math.rad(ARROW_CORRECTION_ROLL_DEG)
		)

	local toTargetFlat = flatten(targetPosition - originPosition)
	if toTargetFlat.Magnitude < 1e-3 then
		toTargetFlat = flatten(rootPart.CFrame.LookVector)
	end
	toTargetFlat = toTargetFlat.Unit

	local currentColor = COLOR_PARTLY_OFF
	local facing = flatten(rootPart.CFrame.LookVector)
	if facing.Magnitude > 1e-3 then
		facing = facing.Unit
		local dot = math.clamp(facing:Dot(toTargetFlat), -1, 1)
		local angleDeg = math.deg(math.acos(dot))
		currentColor = getColorForAngleDeg(angleDeg)
	end
	arrow.Color = currentColor

	if arrow.Parent ~= workspace then
		arrow.Parent = workspace
	end

	self:ensureBillboard()
	local billboard = self.billboard :: BillboardGui
	local handle = (tool :: any):FindFirstChild("Handle")
	if handle then
		if billboard.Adornee ~= handle then
			billboard.Adornee = handle
		end
		if billboard.Parent ~= handle then
			billboard.Parent = handle
		end
	end

	local distanceMeters = (targetPosition - rootPart.Position).Magnitude * METERS_PER_STUD
	local distanceLabel = self.distanceLabel :: TextLabel
	distanceLabel.Text = string.format("%d m", distanceMeters)
	distanceLabel.TextColor3 = currentColor

	local expiresAt = target.expiresAt
	local remainingSec = expiresAt and math.max(0, expiresAt - workspace:GetServerTimeNow()) or 0
	local timeLabel = self.timeLabel :: TextLabel
	timeLabel.Text = utils.convertDurationSecToString(math.ceil(remainingSec))
end

function ClientRadarManager.notifyRadarTarget(
	self: ClientRadarManager,
	targetRarity: number,
	position: Vector3?,
	expiresAt: number?
)
	if not position then
		self.targetsByRarity[targetRarity] = nil
		return
	end

	self.targetsByRarity[targetRarity] = {
		position = position,
		expiresAt = expiresAt,
	}
end

function ClientRadarManager.init(self: ClientRadarManager)
	runService.RenderStepped:Connect(function()
		self:update()
	end)

	RemoteEvents.NotifyRadarTarget.OnClientEvent:Connect(
		function(targetRarity: number, position: Vector3?, expiresAt: number?)
			self:notifyRadarTarget(targetRarity, position, expiresAt)
		end
	)
end

function ClientRadarManager.new(): ClientRadarManager
	local self = setmetatable({} :: ClientRadarManagerFields, ClientRadarManager)

	self.arrow = nil
	self.billboard = nil
	self.distanceLabel = nil
	self.timeLabel = nil
	self.targetsByRarity = {}

	return self
end

local singleton = ClientRadarManager.new()

return singleton
