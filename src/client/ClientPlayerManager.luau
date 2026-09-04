--!strict

local ClientPlayerManager = {}
ClientPlayerManager.__index = ClientPlayerManager

local playersService = game:GetService("Players")

local utils = require("@game/ReplicatedStorage/Shared/utils")

type IndicatorData = {
	player: Player,
}

type ClientPlayerManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	runningSound: Sound?,
	runningSoundDefaultSoundId: string?,
}

export type ClientPlayerManager = typeof(setmetatable({} :: ClientPlayerManagerFields, ClientPlayerManager))

function ClientPlayerManager.removeIndicators(self: ClientPlayerManager, userId: number)
	local indicatorData = self.indicatorMap[userId]
	if not indicatorData then
		return
	end

	self.indicatorMap[userId] = nil
end

function ClientPlayerManager.notifyNewInstance(self: ClientPlayerManager, player: Player)

	local userId = player.UserId

	self.indicatorMap[userId] = {
		player = player,
	}

end

function ClientPlayerManager.notifyRemoveInstance(self: ClientPlayerManager, player: Player)
	self:removeIndicators(player.UserId)
end

-- as of 2026-august-11 these two methods have no callers and self.runningSound is never
-- assigned, so they would have crashed if called; guarded rather than removed
function ClientPlayerManager.setRunningSoundToFlying(self: ClientPlayerManager)
	--print("running sound setting to flying")
	if not self.runningSound then
		return
	end
	self.runningSound.SoundId = "rbxassetid://80323355151711"
end

function ClientPlayerManager.setRunningSoundToDefault(self: ClientPlayerManager)
	--print("running sound setting to default")
	if not self.runningSound or not self.runningSoundDefaultSoundId then
		return
	end
	self.runningSound.SoundId = self.runningSoundDefaultSoundId
end

function ClientPlayerManager.notifyUserRidingStatus(self: ClientPlayerManager, userId: number, isRiding: boolean)
	--print("player is riding", userId, isRiding)

	local indicatorData = self.indicatorMap[userId]
	if not indicatorData then
		return
	end

	local character = indicatorData.player.Character or indicatorData.player.CharacterAdded:Wait()
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local runningSound = humanoidRootPart:WaitForChild("Running") :: Sound

	if isRiding then
		runningSound.SoundId = "rbxassetid://80323355151711"
	else
		runningSound.SoundId = self.runningSoundDefaultSoundId or runningSound.SoundId
	end

end

function ClientPlayerManager.getMapSize(self: ClientPlayerManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientPlayerManager.init(self: ClientPlayerManager)

	-- save off the default running sound id
	local localPlayer = playersService.LocalPlayer :: Player
	local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local runningSound = humanoidRootPart:WaitForChild("Running") :: Sound
	self.runningSoundDefaultSoundId = runningSound.SoundId

	playersService.PlayerAdded:Connect(
		function(player)
			--print("new player exists", player)
			self:notifyNewInstance(player)
		end
	)

	playersService.PlayerRemoving:Connect(
		function(player)
			--print("player is gone", player)
			self:notifyRemoveInstance(player)
		end
	)

	for _, player in playersService:GetPlayers() do
		--print("existing player exists", player)
		self:notifyNewInstance(player)
	end

end

function ClientPlayerManager.new(): ClientPlayerManager
	local self = setmetatable({} :: ClientPlayerManagerFields, ClientPlayerManager)

	self.indicatorMap = {}

	return self
end

local singleton = ClientPlayerManager.new()

return singleton
