--!strict

local VirtualTouchJoystick = {}
VirtualTouchJoystick.__index = VirtualTouchJoystick

local userInputService = game:GetService("UserInputService")

local MAX_MOVE_X_VIEWPORT_FRAC = 0.05
local MAX_MOVE_Y_VIEWPORT_FRAC = 0.05

local DEAD_ZONE_X_VIEWPORT_FRAC = 0.01
local DEAD_ZONE_Y_VIEWPORT_FRAC = 0.01

type VirtualTouchJoystickFields = {
	maxMoveXPixels: number,
	maxMoveYPixels: number,
	deadZoneXPixels: number,
	deadZoneYPixels: number,
	touchPosition: Vector3?,
	virtualJoystickVector: Vector3,
	inputObject: InputObject?,
	inputBeganConnect: RBXScriptConnection?,
	inputChangedConnect: RBXScriptConnection?,
	inputEndedConnect: RBXScriptConnection?,
}

export type VirtualTouchJoystick = typeof(setmetatable({} :: VirtualTouchJoystickFields, VirtualTouchJoystick))

function VirtualTouchJoystick.beginTouch(self: VirtualTouchJoystick, position: Vector3)
	self.touchPosition = position
	self.virtualJoystickVector = Vector3.zero
end

function VirtualTouchJoystick.changedTouch(self: VirtualTouchJoystick, position: Vector3)
	local touchPosition = self.touchPosition
	if not touchPosition then
		return
	end

	local diffPosition = position - touchPosition

	local x = 0
	local y = 0

	local signumX = math.clamp(diffPosition.X, -1, 1)
	local magnitudeX = math.abs(diffPosition.X)
	if magnitudeX > self.deadZoneXPixels then
		x = signumX * (math.min(self.maxMoveXPixels, magnitudeX) - self.deadZoneXPixels) / (self.maxMoveXPixels - self.deadZoneXPixels)
	end

	local signumY = math.clamp(diffPosition.Y, -1, 1)
	local magnitudeY = math.abs(diffPosition.Y)
	if magnitudeY > self.deadZoneYPixels then
		-- y axis is backwards up/down (touch pad larger y is down)
		y = - signumY * (math.min(self.maxMoveYPixels, magnitudeY) - self.deadZoneYPixels) / (self.maxMoveYPixels - self.deadZoneYPixels)
	end

	self.virtualJoystickVector = Vector3.new(x, y, 0)

	--print("vj at ", self.virtualJoystickVector)
end

function VirtualTouchJoystick.endTouch(self: VirtualTouchJoystick)
	self.touchPosition = nil
	self.virtualJoystickVector = Vector3.zero
end

function VirtualTouchJoystick.getVirtualJoystickVector(self: VirtualTouchJoystick): Vector3
	return self.virtualJoystickVector
end

function VirtualTouchJoystick.new(): VirtualTouchJoystick
	local self = setmetatable({} :: VirtualTouchJoystickFields, VirtualTouchJoystick)

	self.maxMoveXPixels = math.ceil(workspace.CurrentCamera.ViewportSize.X * MAX_MOVE_X_VIEWPORT_FRAC)
	self.maxMoveYPixels = math.ceil(workspace.CurrentCamera.ViewportSize.Y * MAX_MOVE_Y_VIEWPORT_FRAC)

	self.deadZoneXPixels = math.ceil(workspace.CurrentCamera.ViewportSize.X * DEAD_ZONE_X_VIEWPORT_FRAC)
	self.deadZoneYPixels = math.ceil(workspace.CurrentCamera.ViewportSize.Y * DEAD_ZONE_Y_VIEWPORT_FRAC)

	self.touchPosition = nil
	self.virtualJoystickVector = Vector3.zero

	-- To detect when it starts being moved
	self.inputBeganConnect = userInputService.InputBegan:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			--print("started", input, input.Delta, input.KeyCode, input.Position, input.UserInputState, input.UserInputType, gameProcessed)

			if gameProcessed then
				return
			end

			local viewportSize = workspace.CurrentCamera.ViewportSize
			if input.Position.X > viewportSize.X // 2 then
				return
			end

			self.inputObject = input

			--print("touch began at", input.Position)
			self:beginTouch(input.Position)
		end
	)

	self.inputChangedConnect = userInputService.InputChanged:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			if input ~= self.inputObject then
				--print("ignoring touch changed as it's not from a virtual joystick move")
				return
			end

			if not self.touchPosition then
				return
			end

			--print("touch moved to", input.Position)
			self:changedTouch(input.Position)
		end
	)

	-- To detect when it stops (returns to center)
	self.inputEndedConnect = userInputService.InputEnded:Connect(
		function(input: InputObject, gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end

			if input ~= self.inputObject then
				--print("ignoring touch ended as it's not from a virtual joystick move")
				return
			end

			self.inputObject = nil

			--print("ended", input, input.Delta, input.KeyCode, input.Position, input.UserInputState, input.UserInputType, gameProcessed)

			if not self.touchPosition then
				return
			end

			--print("touch ended")
			self:endTouch()
		end
	)

	return self
end

local singleton = VirtualTouchJoystick.new()

return singleton
