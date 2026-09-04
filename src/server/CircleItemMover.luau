--!strict

local ItemMover = require("./ItemMover")
local super = ItemMover

local CircleItemMover = {}
CircleItemMover.__index = setmetatable(CircleItemMover, super)

local tweenService = game:GetService("TweenService")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local Dubins = require("./Dubins")
local Types = require("./Types")
local itemManager = require("./ItemManager")

local DUBINS_STEP_SIZE = 0.05

type CircleItemMoverFields = {
	-- ItemMover fields
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
	-- CircleItemMover fields
	radius: number,
	speed: number,
	heartbeatConnect: RBXScriptConnection?,
	planIndex: number,
	plan: Dubins.Plan?,
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
}


export type CircleItemMover = Types.CircleItemMover

function CircleItemMover.tryApplyDubinsStepCount(self: CircleItemMover, count: number): boolean
	-- the plan is always set before the heartbeat connection starts stepping, so the assert cannot fire
	local plan = assert(self.plan)
	self.planIndex += count
	if self.planIndex > #plan.path then
		--print("at end of dubins, at", self:getPart().Position, "goal was", self.endCFrame)
		self:notifyDone()
		return false
	end

	--print("now on step", self.planIndex)
	local cframe = plan.path[self.planIndex]

	self:getPart():pivotTo(cframe)
	return true
end

function CircleItemMover.runHeartbeat(self: CircleItemMover, deltaTime: number)
	local stepsPerSec = self.speed / DUBINS_STEP_SIZE
	local count = math.max(1, math.round(stepsPerSec * deltaTime))
	if not self:tryApplyDubinsStepCount(count) then
		return
	end
end

function CircleItemMover.beginDubins(self: CircleItemMover): boolean
	--print("part now at", self:getPart().CFrame.Position)
	--print("part now at angles", self:getPart().CFrame:ToEulerAnglesXYZ())

	--print("starting dubins, current look vector is", self.beginCFrame.LookVector)

	--print("want to go to", self.endCFrame.Position)

	local stepSize = DUBINS_STEP_SIZE
	local minRadius = self.radius
	local plan = Dubins.tryCalculatePlan(self:getPart().CFrame, self.endCFrame, minRadius, stepSize)

	if not plan then
		return false
	end

	--print("circle item mover have a plan", plan.path, plan.type)

	self.plan = plan
	self.planIndex = 1

	self.heartbeatConnect = game:GetService("RunService").Heartbeat:Connect(
		function(deltaTime)
			self:runHeartbeat(deltaTime)
		end
	)

	return true
end

function CircleItemMover.beginLevel(self: CircleItemMover)
	--print("CircleItemMover part was at beginCFrame", self.beginCFrame, self.beginCFrame.Position)

	local angle = utils.getAngleFromVertical(self.beginCFrame)

	-- move slightly forward before calling dubins to make sure it actually moves us
	local nudge = self.beginCFrame.LookVector * 0.1
	--print("nudge is", nudge, "while look was", cframe.LookVector)

	local cframe = utils.getCFrameParallelToGround(self.beginCFrame) + nudge

	--print("CircleItemMover goal cframe", cframe, "position is", cframe.Position)

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

function CircleItemMover.beginMoving(self: CircleItemMover)
	-- start by leveling the part; our dubins only handles 2d
	-- then dubins to the end

	self:beginLevel()
end

function CircleItemMover.tryBegin(self: CircleItemMover): boolean

	self:beginMoving()

	return true
end

function CircleItemMover.destroy(self: CircleItemMover)
	self.plan = nil

	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end

	if self.tweenCompletedConnect then
		self.tweenCompletedConnect:Disconnect()
		self.tweenCompletedConnect = nil
	end

	if self.heartbeatConnect then
		self.heartbeatConnect:Disconnect()
		self.heartbeatConnect = nil
	end

	super.destroy(self)
end

function CircleItemMover.new(itemId: number, radius: number, speed: number): CircleItemMover
	-- movers are only created for live items, so the cast keeps the previous crash-on-missing behavior
	local item = itemManager:getItemById(itemId) :: Types.Item
	local endCFrame = item:getPart().CFrame
	local self = (setmetatable(super.new(itemId, endCFrame), CircleItemMover) :: any) :: CircleItemMover

	self.radius = radius
	self.speed = speed

	self.heartbeatConnect = nil
	self.planIndex = 0
	self.plan = nil

	return self
end

return CircleItemMover
