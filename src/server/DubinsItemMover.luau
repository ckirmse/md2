--!strict

local ItemMover = require("./ItemMover")
local super = ItemMover

local Types = require("./Types")

local DubinsItemMover = {}
DubinsItemMover.__index = setmetatable(DubinsItemMover, super)

local tweenService = game:GetService("TweenService")

local Dubins = require("./Dubins")

local DUBINS_STEP_SIZE = 0.05
local DUBINS_STEPS_PER_SEC = 300

type DubinsItemMoverFields = {
	-- ItemMover fields
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
	-- DubinsItemMover fields
	minRadius: number,
	runConnect: RBXScriptConnection?,
	planIndex: number,
	plan: Dubins.Plan?,
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
}


export type DubinsItemMover = Types.DubinsItemMover

function DubinsItemMover.tryApplyDubinsStep(self: DubinsItemMover): boolean
	-- the plan is always set before the run connection starts stepping, so the assert cannot fire
	local plan = assert(self.plan)
	self.planIndex += 1
	if self.planIndex > #plan.path then
		--print("at end of dubins, at", self:getPart().Position, "goal was", self.endCFrame.Position)
		self:notifyDone()
		return false
	end

	--print("now on step", self.planIndex)
	local cframe = plan.path[self.planIndex]
	local position = cframe.Position

	local desiredFlyingY = math.min(self.endCFrame.Position.Y * 3, self.endCFrame.Position.Y + 10)

	local currentY = self:getPart().Position.Y
	if self.planIndex < #plan.path - 400 then
		-- move up
		--print("move up if less", currentY, desiredFlyingY)
		if currentY < desiredFlyingY then
			local higherPosition = Vector3.new(position.X, currentY + (desiredFlyingY - currentY) * 0.005, position.Z)
			cframe = CFrame.new(higherPosition) * cframe.Rotation
		end
	else
		--print("move from", currentY, "towards", self.endCFrame.Position.Y)
		-- go to the intended Y
		local multiplier = 0.005
		if self.planIndex > #plan.path - 100 then
			multiplier = (100 - (#plan.path - self.planIndex)) * 0.005
		end
		local higherPosition = Vector3.new(position.X, currentY + (self.endCFrame.Position.Y - currentY) * multiplier, position.Z)
		cframe = CFrame.new(higherPosition) * cframe.Rotation
	end

	self:getObj():PivotTo(cframe)

	return true
end

function DubinsItemMover.run(self: DubinsItemMover, deltaTime: number)
	local count = math.max(1, math.round(DUBINS_STEPS_PER_SEC * deltaTime))
	for i = 1, count do
		-- perhaps should just have this do the calculation but not call the pivotTo(), and we do it once at the end
		if not self:tryApplyDubinsStep() then
			return
		end
	end

end

function DubinsItemMover.beginDubins(self: DubinsItemMover): boolean
	--print("part now at", self:getPart().CFrame.Position)
	--print("part now at angles", self:getPart().CFrame:ToEulerAnglesXYZ())

	--print("starting dubins, current look vector is", self.beginCFrame.LookVector)

	--print("want to go to", self.endCFrame)

	local stepSize = DUBINS_STEP_SIZE
	local plan = Dubins.tryCalculatePlan(self:getPart().CFrame, self.endCFrame, self.minRadius, stepSize)

	if not plan then
		return false
	end

	--print("dubins item mover have a plan", plan.path, plan.type)

	self.plan = plan
	self.planIndex = 1

	self.runConnect = game:GetService("RunService").PreSimulation:Connect(
		function(deltaTime)
			self:run(deltaTime)
		end
	)

	return true
end

function DubinsItemMover.beginLevel(self: DubinsItemMover)
	--print("DubinsItemMover part was at beginCFrame", self.beginCFrame, self.beginCFrame.Position)

	-- recreate the cframe with a new up vector of the y axis
	-- as gemini describes it:
	-- Get the current CFrame and the desired target upVector.
	-- Calculate the axis and angle needed to rotate the current upVector to the target upVector.
	-- Create a new CFrame by rotating the current CFrame by that axis and angle.
	local cframe = self.beginCFrame
	--print("dubinsitemmover beginlevel at", self.beginCFrame)
	local targetUpVector = Vector3.yAxis
	--print("targetUpVector", targetUpVector)
	local startUpVector = cframe.UpVector
	--print("startUpVector", cframe.UpVector)
	local axis = startUpVector:Cross(targetUpVector)
	if axis.Magnitude < 1e-5 then
		--print("dubins item mover skipping leveling, element is already essentially vertical")
		self:beginDubins()
		return
	end

	--print("axis", axis)
	local dot = startUpVector:Dot(targetUpVector)
	--print("vectors dotted is", dot)

	-- we need to clamp because due to some floating point issues, this dot product is sometimes just slightly more than 1 (or less than -1)
	-- (if we didn't clamp, math.acos would return math.nan)
	local clampedDot = math.clamp(dot, -1, 1)
	--print("clamped to", clampedDot)
	local angle = math.acos(clampedDot)
	--print("angle is", angle)
	--print("from axis angle is", CFrame.fromAxisAngle(axis, angle))

	cframe = CFrame.fromAxisAngle(axis, angle) * cframe.Rotation + cframe.Position

	--print("DubinsItemMover goal cframe", cframe, "position is", cframe.Position)

	-- slowly do the equivalent of this:
	--self:getObj():PivotTo(cframe)
	-- actually that's not what this does, because it's moving the part, not pivoting the whole obj

	-- angle is in radians
	local duration = angle

	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	local goal = {}
	goal.CFrame = cframe

	local tween = tweenService:Create(self:getPart(), tweenInfo, goal)
	self.currentTween = tween
	self.tweenCompletedConnect = tween.Completed:Connect(
		function ()
			self.currentTween = nil;

			(self.tweenCompletedConnect :: RBXScriptConnection):Disconnect()
			self.tweenCompletedConnect = nil

			self:beginDubins()
		end
	)
	tween:Play()
end

function DubinsItemMover.beginMoving(self: DubinsItemMover)
	-- start by leveling the part; our dubins only handles 2d
	-- then dubins to the end

	self:beginLevel()
end

function DubinsItemMover.tryBegin(self: DubinsItemMover): boolean

	self:beginMoving()

	return true
end

function DubinsItemMover.destroy(self: DubinsItemMover)
	self.plan = nil

	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end

	if self.tweenCompletedConnect then
		self.tweenCompletedConnect:Disconnect()
		self.tweenCompletedConnect = nil
	end

	if self.runConnect then
		self.runConnect:Disconnect()
		self.runConnect = nil
	end

	super.destroy(self)
end

function DubinsItemMover.new(itemId: number, endCFrame: CFrame, minRadius: number): DubinsItemMover
	local self = (setmetatable(super.new(itemId, endCFrame), DubinsItemMover) :: any) :: DubinsItemMover

	self.minRadius = minRadius

	self.runConnect = nil
	self.planIndex = 0
	self.plan = nil

	return self
end

return DubinsItemMover
