--!strict

-- Thunderstorm visuals, ported from the imported WeatherEvents package: the ambient effects while the weather runs (beams,
-- particles, two spinning cloud rings, a music loop) and the strike cinematic over one dragon or egg. Lighting is not
-- here: the weather's `lighting` in Control/Weather goes through ClientDayNightManager. The art lives only in Studio under
-- ReplicatedStorage.GameAssets (Weather/Thunderstorm and ParticleEffects); a missing piece only warns.
local ClientThunderstormEffects = {}
ClientThunderstormEffects.__index = ClientThunderstormEffects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local clientWeatherSounds = require("./ClientWeatherSounds")

local EFFECTS_FOLDER_NAME = "ThunderstormEffects"
local AMBIENT_ASSET_NAMES = {
	"Beam01",
	"Beam02",
	"Beam03",
	"Beam04",
	"GroundParticlesThunderstormEvent",
	"SkyParticlesThunderstormEvent",
	"SmallCloudsSpin01",
	"SmallCloudsSpin02",
}
-- clockwise about the y axis seen from above is a negative angle
local SPIN_RADIANS_PER_SEC_BY_NAME: { [string]: number } = {
	SmallCloudsSpin01 = -math.rad(3),
	SmallCloudsSpin02 = math.rad(3),
}

local CLOUD_FADE_IN_SEC = 2
local LIGHTNING_DELAY_SEC = 1
local LIGHTNING_COLOR_TWEEN_SEC = 0.25
local LIGHTNING_FADE_OUT_SEC = 1.5
local LIGHTNING_PARTICLES_SEC = 4
local SPARKS_PARTICLES_SEC = 2
local CLOUD_FADE_OUT_SEC = 3

type Spinner = {
	instance: PVInstance,
	basePivot: CFrame,
	radiansPerSec: number,
}

type ClientThunderstormEffectsFields = {
	effectsFolder: Folder?,
	spinConnection: RBXScriptConnection?,
	stormLoop: clientWeatherSounds.LoopHandle?,
}

export type ClientThunderstormEffects = typeof(setmetatable({} :: ClientThunderstormEffectsFields, ClientThunderstormEffects))

local function findDescendant(root: Instance, name: string, className: string): Instance?
	for _, descendant in root:GetDescendants() do
		if descendant.Name == name and descendant:IsA(className) then
			return descendant
		end
	end
	return nil
end

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
	local folder = weather and weather:FindFirstChild("Thunderstorm")
	if not folder then
		warn("ClientThunderstormEffects: ReplicatedStorage.GameAssets.Weather.Thunderstorm not found")
	end
	return folder
end

local function getParticleTemplate(name: string): Instance?
	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = gameAssets and gameAssets:FindFirstChild("ParticleEffects")
	local template = folder and folder:FindFirstChild(name)
	if not template then
		warn("ClientThunderstormEffects: GameAssets.ParticleEffects." .. name .. " not found")
	end
	return template
end

-- the ParticleEffects templates are Attachments carrying emitters; they play because the emitters are enabled, so the clone is
-- removed after durationSec
local function spawnParticleEffect(template: Instance, hostPart: BasePart, offset: CFrame, durationSec: number)
	local host: Instance
	if template:IsA("Attachment") then
		local attachment = template:Clone()
		attachment.CFrame = offset
		attachment.Parent = hostPart
		host = attachment
	elseif template:IsA("ParticleEmitter") then
		local attachment = Instance.new("Attachment")
		attachment.CFrame = offset
		attachment.Parent = hostPart
		template:Clone().Parent = attachment
		host = attachment
	else
		warn("ClientThunderstormEffects: unsupported particle template class", template.ClassName)
		return
	end
	task.delay(durationSec, function()
		host:Destroy()
	end)
end

-- the cloud's attachments are authored on the Model itself (pivot-relative); one parented to a part is converted
local function getAttachmentPivotOffset(cloud: PVInstance, attachment: Attachment): CFrame
	local parent = attachment.Parent
	if parent and parent:IsA("BasePart") then
		return cloud:GetPivot():Inverse() * attachment.WorldCFrame
	end
	return attachment.CFrame
end

-- each part fades to the transparency it was authored with
local function collectFadeParts(root: Instance, excludePart: BasePart?): { [BasePart]: number }
	local parts: { [BasePart]: number } = {}
	local function visit(instance: Instance)
		if instance:IsA("BasePart") and instance ~= excludePart then
			parts[instance] = instance.Transparency
		end
	end
	visit(root)
	for _, descendant in root:GetDescendants() do
		visit(descendant)
	end
	return parts
end

local function tweenTransparency(parts: { [BasePart]: number }, durationSec: number, toOriginal: boolean)
	local tweenInfo = TweenInfo.new(durationSec, Enum.EasingStyle.Linear)
	for part, original in parts do
		TweenService:Create(part, tweenInfo, { Transparency = if toOriginal then original else 1 }):Play()
	end
end

function ClientThunderstormEffects.onStart(self: ClientThunderstormEffects, _startTime: number, _endTime: number)
	self.stormLoop = clientWeatherSounds:startLoop("Thunderstorm")

	local weatherFolder = getWeatherFolder()
	if not weatherFolder then
		return
	end

	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = EFFECTS_FOLDER_NAME
	self.effectsFolder = effectsFolder

	local spinners: { Spinner } = {}
	for _, assetName in AMBIENT_ASSET_NAMES do
		-- the beams are authored inside a subfolder
		local template = weatherFolder:FindFirstChild(assetName, true)
		if not template then
			warn("ClientThunderstormEffects: missing weather asset", assetName)
			continue
		end
		-- the assets keep the world position they were authored at
		local clone = template:Clone()
		-- ambience parts must not swallow the raycasts SurfaceGui buttons rely on
		setTreeBasePartProperty(clone, "CanQuery", false)
		setTreeBasePartProperty(clone, "CanTouch", false)
		clone.Parent = effectsFolder
		local radiansPerSec = SPIN_RADIANS_PER_SEC_BY_NAME[assetName]
		if radiansPerSec and clone:IsA("PVInstance") then
			table.insert(spinners, {
				instance = clone,
				basePivot = clone:GetPivot(),
				radiansPerSec = radiansPerSec,
			})
		end
	end
	effectsFolder.Parent = workspace

	if #spinners > 0 then
		local elapsed = 0
		self.spinConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
			elapsed += deltaTime
			for _, spinner in spinners do
				spinner.instance:PivotTo(spinner.basePivot * CFrame.Angles(0, spinner.radiansPerSec * elapsed, 0))
			end
		end)
	end
end

function ClientThunderstormEffects.onEnd(self: ClientThunderstormEffects)
	if self.stormLoop then
		self.stormLoop:stop()
		self.stormLoop = nil
	end
	if self.spinConnection then
		self.spinConnection:Disconnect()
		self.spinConnection = nil
	end
	if self.effectsFolder then
		self.effectsFolder:Destroy()
		self.effectsFolder = nil
	end
end

-- the strike cinematic over a part: runs to the end even if the weather ends meanwhile, and stops if the part is destroyed
function ClientThunderstormEffects.playStrike(self: ClientThunderstormEffects, targetPart: BasePart)
	local weatherFolder = getWeatherFolder()
	local cloudTemplate = weatherFolder and weatherFolder:FindFirstChild("ThunderCloudMain")
	if not cloudTemplate then
		warn("ClientThunderstormEffects: ThunderCloudMain not found")
		return
	end

	local cloud = cloudTemplate:Clone()
	if not cloud:IsA("PVInstance") then
		warn("ClientThunderstormEffects: ThunderCloudMain is not a PVInstance")
		cloud:Destroy()
		return
	end

	local targetAttachment = findDescendant(cloud, "Pet", "Attachment") :: Attachment?
	local lightningAttachment = findDescendant(cloud, "Lightning", "Attachment") :: Attachment?
	local lightningMesh = findDescendant(cloud, "Lightning", "BasePart") :: BasePart?
	local hostPart = if cloud:IsA("Model") then cloud.PrimaryPart or cloud:FindFirstChildWhichIsA("BasePart") else cloud :: BasePart
	if not targetAttachment or not hostPart then
		warn("ClientThunderstormEffects: ThunderCloudMain has no Pet attachment or parts")
		cloud:Destroy()
		return
	end

	local targetOffset = getAttachmentPivotOffset(cloud, targetAttachment)
	local lightningOffset = lightningAttachment and getAttachmentPivotOffset(cloud, lightningAttachment)
	cloud:PivotTo(CFrame.new(targetPart.Position) * targetOffset:Inverse())

	for _, descendant in cloud:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	task.spawn(function()
		-- the bolt sits out the fade-in and gets its own reveal
		local cloudParts = collectFadeParts(cloud, lightningMesh)
		local lightningOriginalColor = lightningMesh and lightningMesh.Color
		local lightningOriginalTransparency = if lightningMesh then lightningMesh.Transparency else 0
		if lightningMesh then
			lightningMesh.Transparency = 1
		end
		for part in cloudParts do
			part.Transparency = 1
		end
		cloud.Parent = workspace

		local destroyingConnection = targetPart.Destroying:Connect(function()
			cloud:Destroy()
		end)

		tweenTransparency(cloudParts, CLOUD_FADE_IN_SEC, true)
		task.wait(CLOUD_FADE_IN_SEC + LIGHTNING_DELAY_SEC)
		if not cloud.Parent then
			destroyingConnection:Disconnect()
			return
		end

		if lightningMesh then
			lightningMesh.Transparency = lightningOriginalTransparency
			lightningMesh.Color = Color3.new(1, 1, 1)
			if lightningOriginalColor then
				TweenService:Create(
					lightningMesh,
					TweenInfo.new(LIGHTNING_COLOR_TWEEN_SEC, Enum.EasingStyle.Linear),
					{ Color = lightningOriginalColor }
				):Play()
			end
			TweenService:Create(
				lightningMesh,
				TweenInfo.new(LIGHTNING_FADE_OUT_SEC, Enum.EasingStyle.Linear),
				{ Transparency = 1 }
			):Play()
		else
			warn("ClientThunderstormEffects: ThunderCloudMain has no Lightning mesh")
		end

		-- offsets re-expressed in host-part space (normally the identity transform)
		local pivotToHost = hostPart.CFrame:Inverse() * cloud:GetPivot()
		local lightningTemplate = getParticleTemplate("ThunderstormLightning")
		if lightningTemplate and lightningOffset then
			spawnParticleEffect(lightningTemplate, hostPart, pivotToHost * lightningOffset, LIGHTNING_PARTICLES_SEC)
		end
		clientWeatherSounds:playAt("LightningStrikes", hostPart)
		local sparksTemplate = getParticleTemplate("ThunderstormSparks")
		if sparksTemplate then
			spawnParticleEffect(sparksTemplate, hostPart, pivotToHost * targetOffset, SPARKS_PARTICLES_SEC)
		end

		task.wait(LIGHTNING_PARTICLES_SEC)
		if not cloud.Parent then
			destroyingConnection:Disconnect()
			return
		end

		tweenTransparency(cloudParts, CLOUD_FADE_OUT_SEC, false)
		task.wait(CLOUD_FADE_OUT_SEC)
		destroyingConnection:Disconnect()
		cloud:Destroy()
	end)
end

function ClientThunderstormEffects.new(): ClientThunderstormEffects
	return setmetatable(
		{ effectsFolder = nil, spinConnection = nil, stormLoop = nil } :: ClientThunderstormEffectsFields,
		ClientThunderstormEffects
	)
end

local singleton = ClientThunderstormEffects.new()

return singleton
