--!strict

local ClientOptionsManager = {}
ClientOptionsManager.__index = ClientOptionsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")
local clientAudioManager: Types.ClientAudioManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientDragonManager: Types.ClientDragonManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientFtueManager: Types.ClientFtueManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local screenGuiManager: Types.ScreenGuiManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local Options: any = PlayerGui:WaitForChild("Options")

type ClientOptionsManagerFields = {
	-- as of 2026-august-11 options is always a table plus an isLoaded flag; it was previously
	-- nil until loaded, and the unguarded option-button handlers could crash before load
	options: { [string]: any },
	isLoaded: boolean,
	event: BindableEvent,
}

export type ClientOptionsManager = typeof(setmetatable({} :: ClientOptionsManagerFields, ClientOptionsManager))

function ClientOptionsManager.getGuiRoot(self: ClientOptionsManager): Instance
	return Options
end

function ClientOptionsManager.notifyForceEnd(self: ClientOptionsManager)
	self:cleanupOptions()
end

function ClientOptionsManager.notifyClickOutside(self: ClientOptionsManager)
	self:notifyForceEnd()
end

function ClientOptionsManager.getHudElements(self: ClientOptionsManager): { number }
	return {}
end

function ClientOptionsManager.beginOptions(self: ClientOptionsManager)
	Options.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientOptionsManager.cleanupOptions(self: ClientOptionsManager)
	Options.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientOptionsManager.haveOptionsLoaded(self: ClientOptionsManager): boolean
	return self.isLoaded
end

function ClientOptionsManager.getOption(self: ClientOptionsManager, playerOptionKey: string): any
	if not self:haveOptionsLoaded() then
		return true
	end

	return self.options[playerOptionKey]
end

-- some options (e.g. receive trade requests) are managed elsewhere and set data here
function ClientOptionsManager.setOption(self: ClientOptionsManager, playerOptionKey: string, value: any)
	if not self:haveOptionsLoaded() then
		warn("cannot set option when not loaded yet", playerOptionKey, value)
		return
	end

	self.options[playerOptionKey] = value
	RemoteEvents.TrySetOption:FireServer(playerOptionKey, value)
end

function ClientOptionsManager.setData(self: ClientOptionsManager, options: { [string]: any })
	self.isLoaded = true

	for key, value in options do
		self.options[key] = value
	end

	self:updateInterfaceFromOptions()

	-- xxx should change these to just wait for the event
	clientAudioManager:updateBackgroundSoundEffectsEnabled()
	clientAudioManager:updateBackgroundSoundEffectsEnabled()
	clientAudioManager:updateMainSoundEffectsEnabled()
	clientDragonManager:updatePotatoModeEnabled()

	self.event:Fire()
end

function ClientOptionsManager.updateInterfaceFromOptions(self: ClientOptionsManager)
	local OptionsScroll = Options:WaitForChild("DialogBack"):WaitForChild("OptionsScroll")

	local isBackgroundMusicEnabled = self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED]

	local backgroundMusicButton: any = utils.findFirstDescendant(OptionsScroll, "BackgroundMusicButton")
	local backgroundMusicImageLabel = backgroundMusicButton:FindFirstChild("CheckImage")
	backgroundMusicImageLabel.Visible = isBackgroundMusicEnabled

	local isBackgroundSoundFxEnabled = self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED]

	local backgroundSoundFxButton: any = utils.findFirstDescendant(OptionsScroll, "BackgroundSoundFxButton")
	local backgroundSoundFxImageLabel = backgroundSoundFxButton:FindFirstChild("CheckImage")
	backgroundSoundFxImageLabel.Visible = isBackgroundSoundFxEnabled

	local isMainSoundFxEnabled = self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED]
	local mainSoundFxButton: any = utils.findFirstDescendant(OptionsScroll, "SoundFxButton")
	local mainSoundFxImageLabel = mainSoundFxButton:FindFirstChild("CheckImage")
	mainSoundFxImageLabel.Visible = isMainSoundFxEnabled

	local isPotatoModeEnabled = self.options[PlayerOptionKeys.POTATO_MODE_ENABLED]

	local potatoModeButton: any = utils.findFirstDescendant(OptionsScroll, "PotatoModeButton")
	local potatoModeImageLabel = potatoModeButton:FindFirstChild("CheckImage")
	potatoModeImageLabel.Visible = isPotatoModeEnabled


end

function ClientOptionsManager.initWorldInterface(self: ClientOptionsManager)
	local playerGui = player:FindFirstChild("PlayerGui") :: Instance
	local ScreenGui: any = playerGui:WaitForChild("ScreenGui")
	local OptionButtonFrame = ScreenGui:FindFirstChild("OptionButtonFrame")
	local OptionButton = OptionButtonFrame:FindFirstChild("OptionButton")
	OptionButton.Activated:Connect(
		function()
			if not self:haveOptionsLoaded() then
				return
			end

			if Options.Enabled then
				self:cleanupOptions()
			else
				self:beginOptions()
			end
		end
	)

	Options:WaitForChild("DialogBack"):WaitForChild("Header"):WaitForChild("ExitButton").Activated:Connect(
		function()
			self:cleanupOptions()
		end
	)

	local OptionsScroll = Options:WaitForChild("DialogBack"):WaitForChild("OptionsScroll")
	local backgroundMusicButton: any = utils.findFirstDescendant(OptionsScroll, "BackgroundMusicButton")
	backgroundMusicButton.Activated:Connect(
		function()
			self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED] = not self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED]
			clientAudioManager:updateBackgroundMusicEnabled()

			self:updateInterfaceFromOptions()

			RemoteEvents.TrySetOption:FireServer(PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED, self.options[PlayerOptionKeys.BACKGROUND_MUSIC_ENABLED])
		end
	)

	local backgroundSoundFxButton: any = utils.findFirstDescendant(OptionsScroll, "BackgroundSoundFxButton")
	backgroundSoundFxButton.Activated:Connect(
		function()
			self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED] = not self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED]
			clientAudioManager:updateBackgroundSoundEffectsEnabled()

			self:updateInterfaceFromOptions()

			RemoteEvents.TrySetOption:FireServer(PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED, self.options[PlayerOptionKeys.BACKGROUND_SOUND_EFFECTS_ENABLED])
		end
	)

	local mainSoundFxButton: any = utils.findFirstDescendant(OptionsScroll, "SoundFxButton")
	mainSoundFxButton.Activated:Connect(
		function()
			self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED] = not self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED]
			clientAudioManager:updateMainSoundEffectsEnabled()

			self:updateInterfaceFromOptions()

			RemoteEvents.TrySetOption:FireServer(PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED, self.options[PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED])
		end
	)

	local potatoModeButton: any = utils.findFirstDescendant(OptionsScroll, "PotatoModeButton")
	potatoModeButton.Activated:Connect(
		function()
			self.options[PlayerOptionKeys.POTATO_MODE_ENABLED] = not self.options[PlayerOptionKeys.POTATO_MODE_ENABLED]
			clientDragonManager:updatePotatoModeEnabled()

			self:updateInterfaceFromOptions()

			RemoteEvents.TrySetOption:FireServer(PlayerOptionKeys.POTATO_MODE_ENABLED, self.options[PlayerOptionKeys.POTATO_MODE_ENABLED])
		end
	)

	local CodeInput: any = utils.findFirstDescendant(OptionsScroll, "CodeInput")
	local CodeInputSubmit: any = utils.findFirstDescendant(CodeInput, "Submit")
	local CodeInputSubmitDisabled: any = utils.findFirstDescendant(CodeInput, "SubmitDisabled")
	local CodeInputTextBox: any = utils.findFirstDescendant(CodeInput, "TextBox")
	CodeInputTextBox:GetPropertyChangedSignal("Text"):Connect(
		function()
			local rawText = CodeInputTextBox.Text
			local text = utils.trimString(rawText)
			if string.len(text) > 0 then
				CodeInputSubmit.Visible = true
				CodeInputSubmitDisabled.Visible = false
			else
				CodeInputSubmit.Visible = false
				CodeInputSubmitDisabled.Visible = true
			end
		end
	)
	local function codeInputSubmitActivate()
		local rawText = CodeInputTextBox.Text
		CodeInputTextBox.Text = ""
		if clientFtueManager:isFtueActive() then
			screenGuiManager:showSystemMessage("You cannot submit codes yet")
			return
		end

		RemoteEvents.TrySubmitCode:FireServer(rawText)
	end

	CodeInputTextBox.FocusLost:Connect(
		function(enterPressed: boolean, inputObject: InputObject?)
			if not enterPressed then
				return
			end

			codeInputSubmitActivate()
		end
	)

	CodeInputSubmit.Activated:Connect(codeInputSubmitActivate)


end

function ClientOptionsManager.getEvent(self: ClientOptionsManager): RBXScriptSignal
	return self.event.Event
end


function ClientOptionsManager.init(self: ClientOptionsManager)
	self:initWorldInterface()
end

function ClientOptionsManager.new(): ClientOptionsManager
	local self = setmetatable({} :: ClientOptionsManagerFields, ClientOptionsManager)

	self.options = {}
	self.isLoaded = false

	self.event = Instance.new("BindableEvent")

	return self
end

function ClientOptionsManager.initClass(deps: any)
	clientAudioManager = deps.clientAudioManager
	clientDragonManager = deps.clientDragonManager
	clientFtueManager = deps.clientFtueManager
	screenGuiManager = deps.screenGuiManager
end

local singleton = ClientOptionsManager.new()

return singleton
