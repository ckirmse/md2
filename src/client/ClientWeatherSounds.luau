--!strict

-- Audio-API (AudioPlayer / AudioEmitter / Wire) player for the weather sounds, ported from the imported WeatherEvents package.
-- Loops follow the background-music option, one-shots the main sound-effects option.
local ClientWeatherSounds = {}
ClientWeatherSounds.__index = ClientWeatherSounds

local SoundService = game:GetService("SoundService")

local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")

local clientOptionsManager = require("./ClientOptionsManager")

type SoundDef = {
	assetId: string,
	volume: number?,
}

export type LoopHandle = {
	stop: (self: LoopHandle) -> (),
}

local SOUND_DEFS: { [string]: SoundDef } = {
	Thunderstorm = { assetId = "rbxassetid://132152136", volume = 0.3 },
	LightningStrikes = { assetId = "rbxassetid://140089926923698" },
	ShootingStars = { assetId = "rbxassetid://1841595283" },
	StarDescends = { assetId = "rbxassetid://120822746678209" },
}

type ClientWeatherSoundsFields = {
	masterOutput: AudioDeviceOutput?,
}

export type ClientWeatherSounds = typeof(setmetatable({} :: ClientWeatherSoundsFields, ClientWeatherSounds))

function ClientWeatherSounds.getMasterOutput(self: ClientWeatherSounds): AudioDeviceOutput
	local existing = self.masterOutput
	if existing and existing.Parent then
		return existing
	end

	local output = SoundService:FindFirstChildWhichIsA("AudioDeviceOutput")
	if not output then
		output = Instance.new("AudioDeviceOutput")
		output.Name = "WeatherMasterOutput"
		output.Parent = SoundService
	end
	self.masterOutput = output

	-- only created when missing, so a host already on the Audio API is not heard twice
	local camera = workspace.CurrentCamera
	if camera and not camera:FindFirstChildWhichIsA("AudioListener") then
		local listener = Instance.new("AudioListener")
		listener.Parent = camera
		local wire = Instance.new("Wire")
		wire.SourceInstance = listener
		wire.TargetInstance = output
		wire.Parent = listener
	end
	return output :: AudioDeviceOutput
end

local function buildPlayer(name: string): AudioPlayer
	local def = SOUND_DEFS[name]
	local audioPlayer = Instance.new("AudioPlayer")
	audioPlayer.Name = "Audio" .. name
	audioPlayer.Asset = def.assetId
	audioPlayer.Volume = def.volume or 1
	return audioPlayer
end

function ClientWeatherSounds.playFrom(self: ClientWeatherSounds, name: string, host: Instance, isLooping: boolean)
	if not clientOptionsManager:getOption(PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED) then
		return
	end
	if not host:IsDescendantOf(game) then
		return
	end

	self:getMasterOutput()

	local audioPlayer = buildPlayer(name)
	audioPlayer.Looping = isLooping
	local emitter = Instance.new("AudioEmitter")
	emitter.Parent = host

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = emitter
	wire.Parent = audioPlayer

	audioPlayer.Parent = host
	if not isLooping then
		audioPlayer.Ended:Once(function()
			emitter:Destroy()
			audioPlayer:Destroy()
		end)
	end
	audioPlayer:Play()
end

function ClientWeatherSounds.playAt(self: ClientWeatherSounds, name: string, host: Instance)
	self:playFrom(name, host, false)
end

function ClientWeatherSounds.startLoopAt(self: ClientWeatherSounds, name: string, host: Instance)
	self:playFrom(name, host, true)
end

-- a non-spatial loop until stopped; nil when background music is off
function ClientWeatherSounds.startLoop(self: ClientWeatherSounds, name: string): LoopHandle?
	if not clientOptionsManager:getOption(PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED) then
		return nil
	end

	local output = self:getMasterOutput()
	local audioPlayer = buildPlayer(name)
	audioPlayer.Looping = true

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = output
	wire.Parent = audioPlayer

	audioPlayer.Parent = SoundService
	audioPlayer:Play()

	local handle = {}
	function handle.stop(_self: LoopHandle)
		if audioPlayer:IsDescendantOf(game) then
			audioPlayer:Destroy()
		end
	end
	return (handle :: any) :: LoopHandle
end

function ClientWeatherSounds.new(): ClientWeatherSounds
	return setmetatable({ masterOutput = nil } :: ClientWeatherSoundsFields, ClientWeatherSounds)
end

local singleton = ClientWeatherSounds.new()

return singleton
