--!strict

local ClientStarlightEffects = {}
ClientStarlightEffects.__index = ClientStarlightEffects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local WeatherStrike = require("@game/ReplicatedStorage/Shared/WeatherStrike")

local clientWeatherSounds = require("./ClientWeatherSounds")

local EFFECTS_FOLDER_NAME = "StarlightEffects"
local AMBIENT_ASSET_NAMES = {
	"Beam01",
	"Beam02",
	"Beam03",
	"Beam04",
	"GroundParticlesShootingStarsEvent",
	"SkyParticlesShootingStarsEvent",
}

local STAR_START_HEIGHT = 170
local STAR_FALL_SEC = WeatherStrike.TRAIT_DELAY_SEC[Enums.Weather.STARLIGHT]
local IMPACT_PARTICLES_SEC = 1

type ClientStarlightEffectsFields = {
	effectsFolder: Folder?,
	starsLoop: clientWeatherSounds.LoopHandle?,
}

export type ClientStarlightEffects = typeof(setmetatable({} :: ClientStarlightEffectsFields, ClientStarlightEffects))

local function setTreeBasePartProperty(root: Instance, propertyName: string, value: any)
	if root:IsA("BasePart") then
		(root :: any)[propertyName] = value
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			(descendant :: any)[propertyName] = value
		end
	end
end

local function getWeatherFolder(): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local weather = gameAssets and gameAssets:FindFirstChild("Weather")
	local folder = weather and weather:FindFirstChild("ShootingStars")
	if not folder then
		warn("ClientStarlightEffects: ReplicatedStorage.GameAssets.Weather.ShootingStars not found")
	end
	return folder
end

local function getAlignmentOffset(star: Model): CFrame
	for _, descendant in star:GetDescendants() do
		if descendant:IsA("Attachment") then
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") and parent.Name == "Ball" then
				return star:GetPivot():Inverse() * descendant.WorldCFrame
			end
		end
	end
	return CFrame.new()
end

function ClientStarlightEffects.onStart(self: ClientStarlightEffects, _startTime: number, _endTime: number)
	self.starsLoop = clientWeatherSounds:startLoop("ShootingStars")

	local weatherFolder = getWeatherFolder()
	if not weatherFolder then
		return
	end

	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = EFFECTS_FOLDER_NAME
	self.effectsFolder = effectsFolder

	for _, assetName in AMBIENT_ASSET_NAMES do
		local template = weatherFolder:FindFirstChild(assetName, true)
		if not template then
			warn("ClientStarlightEffects: missing weather asset", assetName)
			continue
		end
		local clone = template:Clone()
		setTreeBasePartProperty(clone, "CanQuery", false)
		setTreeBasePartProperty(clone, "CanTouch", false)
		clone.Parent = effectsFolder
	end
	effectsFolder.Parent = workspace
end

function ClientStarlightEffects.onEnd(self: ClientStarlightEffects)
	if self.starsLoop then
		self.starsLoop:stop()
		self.starsLoop = nil
	end
	if self.effectsFolder then
		self.effectsFolder:Destroy()
		self.effectsFolder = nil
	end
end

local function playImpact(targetPart: BasePart)
	local weatherFolder = getWeatherFolder()
	local template = weatherFolder and weatherFolder:FindFirstChild("StarImpact", true)
	if not template or not template:IsA("Attachment") then
		warn("ClientStarlightEffects: StarImpact (an Attachment) not found")
		return
	end

	local impact = template:Clone()
	impact.Parent = targetPart
	task.delay(IMPACT_PARTICLES_SEC, function()
		impact:Destroy()
	end)
end

function ClientStarlightEffects.playStrike(self: ClientStarlightEffects, targetPart: BasePart)
	local weatherFolder = getWeatherFolder()
	local starTemplate = weatherFolder and weatherFolder:FindFirstChild("ShootingStar")
	if not starTemplate or not starTemplate:IsA("Model") then
		warn("ClientStarlightEffects: ShootingStar (a Model) not found")
		return
	end

	local star = starTemplate:Clone()
	for _, descendant in star:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local alignmentOffset = getAlignmentOffset(star)
	local targetPosition = targetPart.Position
	local startCFrame = CFrame.new(targetPosition + Vector3.new(0, STAR_START_HEIGHT, 0)) * alignmentOffset:Inverse()
	local endCFrame = CFrame.new(targetPosition) * alignmentOffset:Inverse()
	star:PivotTo(startCFrame)
	star.Parent = workspace
	clientWeatherSounds:startLoopAt("StarDescends", star)

	local destroyingConnection = targetPart.Destroying:Connect(function()
		star:Destroy()
	end)

	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = startCFrame
	pivotValue.Changed:Connect(function(value: CFrame)
		star:PivotTo(value)
	end)
	local fallTween = TweenService:Create(pivotValue, TweenInfo.new(STAR_FALL_SEC, Enum.EasingStyle.Linear), { Value = endCFrame })

	task.spawn(function()
		fallTween:Play()
		fallTween.Completed:Wait()
		pivotValue:Destroy()
		destroyingConnection:Disconnect()
		if not star.Parent then
			return
		end
		star:Destroy()

		if targetPart.Parent then
			playImpact(targetPart)
		end
	end)
end

function ClientStarlightEffects.new(): ClientStarlightEffects
	return setmetatable({ effectsFolder = nil, starsLoop = nil } :: ClientStarlightEffectsFields, ClientStarlightEffects)
end

local singleton = ClientStarlightEffects.new()

return singleton
