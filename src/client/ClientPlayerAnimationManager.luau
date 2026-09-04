--!strict

local ClientPlayerAnimationManager = {}
ClientPlayerAnimationManager.__index = ClientPlayerAnimationManager

local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Animations = GameAssets:WaitForChild("Animations")

local clientRideController = require("./ClientRideController")

local player = game:GetService("Players").LocalPlayer :: Player

local character = player.Character or player.CharacterAdded:Wait()
-- the character rig's children only exist at runtime, so these are untyped here
local humanoid: any = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

type ClientPlayerAnimationManagerFields = {
	sitDragonTrack: AnimationTrack?,
	rideDragonTrack: AnimationTrack?,
	jumpTrack: AnimationTrack?,
	fallTrack: AnimationTrack?,
}

export type ClientPlayerAnimationManager = typeof(setmetatable({} :: ClientPlayerAnimationManagerFields, ClientPlayerAnimationManager))

function ClientPlayerAnimationManager.disableBuiltInAnimations(self: ClientPlayerAnimationManager)
	local animateScript: any = character:WaitForChild("Animate")
	animateScript.Enabled = false
end

function ClientPlayerAnimationManager.enableBuiltInAnimations(self: ClientPlayerAnimationManager)
	local animateScript: any = character:WaitForChild("Animate")
	animateScript.Enabled = true
end

function ClientPlayerAnimationManager.stopAllAnimations(self: ClientPlayerAnimationManager)
	for _, track in humanoid.Animator:GetPlayingAnimationTracks() do
		--print("stopping an animation", track)
		track:Stop()
	end
end

function ClientPlayerAnimationManager.stopWalkingRunningAnimations(self: ClientPlayerAnimationManager)
	for _, track in humanoid.Animator:GetPlayingAnimationTracks() do
		if track.Name ~= "WalkAnim" and track.Name ~= "RunAnim" then
			--print("letting continue animation", track)
			continue
		end

		--print("stopping an animation", track)
		track:Stop()
	end
end

function ClientPlayerAnimationManager.playSitAndRide(self: ClientPlayerAnimationManager)

	-- set in init(); the casts record that these are only played after startup
	local sitDragonTrack = self.sitDragonTrack :: AnimationTrack
	local rideDragonTrack = self.rideDragonTrack :: AnimationTrack

	local sitDragonStoppedConnect: RBXScriptConnection
	sitDragonStoppedConnect = sitDragonTrack.Stopped:Connect(
		function()
			--print("sit stopped")

			sitDragonStoppedConnect:Disconnect()

			if not clientRideController:isRiding() then
				return
			end

			--print("playing ride")
			rideDragonTrack:Play()
		end
	)

	sitDragonTrack:Play()

end

function ClientPlayerAnimationManager.playFall(self: ClientPlayerAnimationManager)

	local fallTrack = self.fallTrack :: AnimationTrack

	local fallStoppedConnect: RBXScriptConnection
	fallStoppedConnect = fallTrack.Stopped:Connect(
		function()
			--print("stopping fall track")
			fallStoppedConnect:Disconnect()
		end
	)

	--print("playing fall track")
	fallTrack:Play()

	local prevVelocity = -1

	local runConnect: RBXScriptConnection
	runConnect = runService.PostSimulation:Connect(
		function()
			local velocity = humanoidRootPart.AssemblyLinearVelocity.Y
			if prevVelocity < 0 and velocity >= 0 then
				--print("bottom of fall reached, enabling built in animations")
				runConnect:Disconnect()

				fallTrack:Stop()
				self:enableBuiltInAnimations()

				return
			end

			prevVelocity = velocity
		end
	)
end

function ClientPlayerAnimationManager.playJumpAndFall(self: ClientPlayerAnimationManager)
	local jumpTrack = self.jumpTrack :: AnimationTrack
	local fallTrack = self.fallTrack :: AnimationTrack

	local jumpStoppedConnect: RBXScriptConnection
	jumpStoppedConnect = jumpTrack.Stopped:Connect(
		function()
			jumpStoppedConnect:Disconnect()

			if fallTrack.IsPlaying then
				--print("jump track stopped, but fall track playing so bailing")
				return
			end

			--print("jump track stopped, trying to stay on last frame")
			jumpTrack:Play()
			jumpTrack:AdjustSpeed(0)
			jumpTrack.TimePosition = jumpTrack.Length - 0.01
		end
	)
	--print("playing jump track")
	jumpTrack:Play()

	local prevVelocity = 1

	local runConnect: RBXScriptConnection
	runConnect = runService.PostSimulation:Connect(
		function()
			local velocity = humanoidRootPart.AssemblyLinearVelocity.Y
			if prevVelocity >= 0 and velocity < 0 then
				--print("top of jump reached")
				runConnect:Disconnect()

				self:playFall()
				return
			end

			prevVelocity = velocity
		end
	)
end

function ClientPlayerAnimationManager.init(self: ClientPlayerAnimationManager)
	local jumpAnimation = Animations:WaitForChild("Jump") :: Animation
	local fallAnimation = Animations:WaitForChild("Fall") :: Animation
	local sitDragonAnimation = Animations:WaitForChild("SitDragon") :: Animation
	local rideDragonAnimation = Animations:WaitForChild("RideDragon") :: Animation

	local animator = humanoid:WaitForChild("Animator") :: Animator

	self.sitDragonTrack = animator:LoadAnimation(sitDragonAnimation)
	local rideDragonTrack = animator:LoadAnimation(rideDragonAnimation)
	rideDragonTrack.Looped = true
	self.rideDragonTrack = rideDragonTrack

	self.jumpTrack = animator:LoadAnimation(jumpAnimation)
	local fallTrack = animator:LoadAnimation(fallAnimation)
	fallTrack.Looped = true
	self.fallTrack = fallTrack
end


function ClientPlayerAnimationManager.new(): ClientPlayerAnimationManager
	local self = setmetatable({} :: ClientPlayerAnimationManagerFields, ClientPlayerAnimationManager)

	return self
end

local singleton = ClientPlayerAnimationManager.new()

return singleton
