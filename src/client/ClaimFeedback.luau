--!strict

-- The celebration shared by the reward dialogs (playtime, daily login): the claim sound, which respects the main
-- sound-effects option, and confetti over the dialog's gui.
local ClaimFeedback = {}

local SoundService = game:GetService("SoundService")

local PlayerOptionKeys = require("@game/ReplicatedStorage/Shared/PlayerOptionKeys")

local clientOptionsManager = require("./ClientOptionsManager")
local Confetti = require("./Confetti")

local CLAIM_SOUND_ID = "rbxassetid://135192579587427"

local claimSound: Sound? = nil

local function playClaimSound()
	if not clientOptionsManager:getOption(PlayerOptionKeys.MAIN_SOUND_EFFECTS_ENABLED) then
		return
	end

	local sound = claimSound
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.Name = "RewardClaim"
		newSound.SoundId = CLAIM_SOUND_ID
		newSound.Parent = SoundService
		claimSound = newSound
		sound = newSound
	end

	SoundService:PlayLocalSound(sound :: Sound)
end

-- gui is the ScreenGui the confetti falls across
function ClaimFeedback.play(gui: Instance, random: Random)
	playClaimSound()
	Confetti.play(gui, random)
end

return ClaimFeedback
