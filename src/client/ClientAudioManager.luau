--!strict

local ClientAudioManager = {}
ClientAudioManager.__index = ClientAudioManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the audio templates' shapes only exist in Studio, so they are untyped here
local BackgroundAudioParent: any = Effects:WaitForChild("BackgroundAudioParent")

local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")

local clientOptionsManager = require("./ClientOptionsManager")
-- vendored library (out of scope per CLAUDE.md); crosses this boundary untyped
local Rain: any = require("./Libs/Rain/Rain") :: any

local player = game:GetService("Players").LocalPlayer :: Player

type ClientAudioManagerFields = {
	audioBackgroundMusic: any?, -- AudioPlayer instances authored in Studio
	audioBackgroundSoundEffects: any?,
	volumeMap: { [any]: number },
	destroyingConnectMap: { [RBXScriptConnection]: boolean },
	instanceAddedConnect: RBXScriptConnection?,
}

export type ClientAudioManager = typeof(setmetatable({} :: ClientAudioManagerFields, ClientAudioManager))

function ClientAudioManager.updateBackgroundMusicEnabled(self: ClientAudioManager)
	local audioBackgroundMusic = self.audioBackgroundMusic
	if not audioBackgroundMusic then
		return
	end

	if clientOptionsManager:getOption(PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED) then
		audioBackgroundMusic:Play()
	else
		audioBackgroundMusic:Stop()
	end
end

function ClientAudioManager.updateBackgroundSoundEffectsEnabled(self: ClientAudioManager)
	local audioBackgroundSoundEffects = self.audioBackgroundSoundEffects
	if not audioBackgroundSoundEffects then
		return
	end

	if clientOptionsManager:getOption(PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED) then
		audioBackgroundSoundEffects:Play()
	else
		audioBackgroundSoundEffects:Stop()
	end
end

function ClientAudioManager.trackAndSilenceSoundEffect(self: ClientAudioManager, inst: any)
	self.volumeMap[inst] = inst.Volume
	inst.Volume = 0

	local destroyingConnect: RBXScriptConnection
	destroyingConnect = inst.Destroying:Connect(
		function()
			self.volumeMap[inst] = nil

			self.destroyingConnectMap[destroyingConnect] = nil
		end
	)
	self.destroyingConnectMap[destroyingConnect] = true
end

function ClientAudioManager.beginForceNoSoundEffects(self: ClientAudioManager)
	self.volumeMap = {}

	self.instanceAddedConnect = workspace.DescendantAdded:Connect(
		function(inst)
			if not inst:IsA("AudioPlayer") then
				return
			end
			self:trackAndSilenceSoundEffect(inst)
		end
	)

	for _, inst in (workspace :: any):QueryDescendants("AudioPlayer") do
		self:trackAndSilenceSoundEffect(inst)
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local inst

	inst = humanoidRootPart:WaitForChild("Running")
	self:trackAndSilenceSoundEffect(inst)

	inst = humanoidRootPart:WaitForChild("Jumping")
	self:trackAndSilenceSoundEffect(inst)

	inst = humanoidRootPart:WaitForChild("Landing")
	self:trackAndSilenceSoundEffect(inst)

	inst = humanoidRootPart:WaitForChild("GettingUp")
	self:trackAndSilenceSoundEffect(inst)

	Rain:SetVolume(0)
end

function ClientAudioManager.cleanupForceNoSoundEffects(self: ClientAudioManager)
	local instanceAddedConnect = self.instanceAddedConnect
	if instanceAddedConnect then
		instanceAddedConnect:Disconnect()
		self.instanceAddedConnect = nil
	end

	for inst, volume in self.volumeMap do
		--print("setting volume", inst, volume)
		inst.Volume = volume
	end
	self.volumeMap = {}

	for destroyingConnect, _ in self.destroyingConnectMap do
		destroyingConnect:Disconnect()
	end
	self.destroyingConnectMap = {}

	-- this is the default
	Rain:SetVolume(0.2)

end


function ClientAudioManager.updateMainSoundEffectsEnabled(self: ClientAudioManager)
	self:cleanupForceNoSoundEffects()

	if clientOptionsManager:getOption(PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED) then
		--print("sound effects enabled, restored as needed")
	else
		--print("sound effects getting disabled")
		self:beginForceNoSoundEffects()
	end

end

function ClientAudioManager.init(self: ClientAudioManager)
	local backgroundAudioParent = BackgroundAudioParent:Clone()
	backgroundAudioParent.Parent = workspace

	local audioBackgroundSoundEffects = backgroundAudioParent:FindFirstChild("AudioBackground")
	audioBackgroundSoundEffects.Looping = true
	self.audioBackgroundSoundEffects = audioBackgroundSoundEffects

	local audioBackgroundMusic = backgroundAudioParent:FindFirstChild("AudioBackgroundMusic")
	audioBackgroundMusic.Looping = true
	self.audioBackgroundMusic = audioBackgroundMusic

end

function ClientAudioManager.new(): ClientAudioManager
	local self = setmetatable({} :: ClientAudioManagerFields, ClientAudioManager)

	self.volumeMap = {}
	self.destroyingConnectMap = {}

	return self
end


local singleton = ClientAudioManager.new()

return singleton
