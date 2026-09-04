--!strict

local CameraManager = {}
CameraManager.__index = CameraManager

local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")

local player = game:GetService("Players").LocalPlayer :: Player

local character = player.Character or player.CharacterAdded:Wait()

type CameraState = {
	cameraType: Enum.CameraType,
	cameraCFrame: CFrame,
}

type CameraManagerFields = {
	states: { CameraState },
	baseCameraCFrame: CFrame?,
}

export type CameraManager = typeof(setmetatable({} :: CameraManagerFields, CameraManager))

function CameraManager.pushState(self: CameraManager)
	local camera = workspace.CurrentCamera
	local cameraType = camera.CameraType

	-- move camera where we want

	self.baseCameraCFrame = camera.CFrame

	table.insert(self.states,
		{
			cameraType = cameraType,
			cameraCFrame = camera.CFrame,
		}
	)
end

function CameraManager.popState(self: CameraManager)
	local cameraData = table.remove(self.states)
	if not cameraData then
		warn("can't pop camera state when have none")
		return
	end

	local camera = workspace.CurrentCamera

	local cameraDestCFrame = cameraData.cameraCFrame
	local duration = 1
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	local tween = PivotToTween(camera, tweenInfo, cameraDestCFrame)
	tween.Completed:Connect(
		function()
			-- let user control camera
			camera.CameraType = cameraData.cameraType
		end
	)

	tween:Play()
end

function CameraManager.getCameraLocationBehindPlayer(self: CameraManager): CFrame
	-- the character rig's children only exist at runtime, so they are untyped here
	local playerCFrame = (character :: any).HumanoidRootPart.CFrame :: CFrame
	local look = playerCFrame.LookVector
	local cameraPosition = playerCFrame.Position - 12 * look + Vector3.new(0, 3, 0)

	return CFrame.lookAt(cameraPosition, playerCFrame.Position, Vector3.yAxis)
end

function CameraManager.moveCameraBehindPlayer(self: CameraManager)
	local cframe = self:getCameraLocationBehindPlayer()

	local cameraType = workspace.CurrentCamera.CameraType

	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	workspace.CurrentCamera.CFrame = cframe

	-- without the defer, the system moves the camera to weird spots not as we intended, particularly noticeable on mobile
	task.defer(
		function()
			workspace.CurrentCamera.CameraType = cameraType
		end
	)
end

function CameraManager.init(self: CameraManager)

end


function CameraManager.new(): CameraManager
	local self = setmetatable({} :: CameraManagerFields, CameraManager)

	self.states = {}

	return self
end

local singleton = CameraManager.new()

return singleton
