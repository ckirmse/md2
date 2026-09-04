--!strict

local ItemMover = require("./ItemMover")
local super = ItemMover

local Types = require("./Types")

local UpAndOverItemMover = {}
UpAndOverItemMover.__index = setmetatable(UpAndOverItemMover, super)

local utils = require("@game/ReplicatedStorage/Shared/utils")

local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")

-- in studs per sec
local RISE_SPEED = 40
local MOVE_SPEED = 20

type UpAndOverItemMoverFields = {
	-- ItemMover fields
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
	-- UpAndOverItemMover fields
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
}


export type UpAndOverItemMover = Types.UpAndOverItemMover

function UpAndOverItemMover.beginMoveOver(self: UpAndOverItemMover)
	local diff = self.endCFrame.Position - self:getPart().Position
	local duration = diff.Magnitude / MOVE_SPEED
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	-- go to destination but keep current orientation (looking at destination)
	--local destCFrame = CFrame.new(self.endCFrame.Position) * self:getPart().CFrame.Rotation

	--self.currentTween = tweenService:Create(self:getPart(), tweenInfo, goal)
	local tween = PivotToTween(self:getObj(), tweenInfo, self.endCFrame, self:getStepCallback())
	self.currentTween = tween
	self.tweenCompletedConnect = tween.Completed:Connect(
		function ()
			--print("up and over tween done")
			self.currentTween = nil;

			(self.tweenCompletedConnect :: RBXScriptConnection):Disconnect()
			self.tweenCompletedConnect = nil

			self:notifyDone()
		end
	)
	tween:Play()

end

function UpAndOverItemMover.beginMoveUp(self: UpAndOverItemMover)
	local destY = self.endCFrame.Position.Y

	-- we scale how high the item goes by how far it is from the destination
	local distance = utils.getMagnitudeXZ(self.endCFrame.Position - self.beginCFrame.Position)
	local clampedDistance = math.clamp(distance, 3, 15)

	-- add up amount we NEED to move up/down, then add a factor of clamped distance so we come to the destination from above
	local diffY = (destY - self.beginCFrame.Position.Y) + clampedDistance * 1.3

	local endUpPosition = self.beginCFrame.Position + Vector3.new(0, diffY, 0)
	local diff = endUpPosition - self.beginCFrame.Position
	local duration = diff.Magnitude / RISE_SPEED
	local endUpCFrame = CFrame.lookAlong(endUpPosition, self.endCFrame.Position - endUpPosition)

	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	-- move up and turn towards goal

	local tween = PivotToTween(self:getObj(), tweenInfo, endUpCFrame, self:getStepCallback())
	self.currentTween = tween
	self.tweenCompletedConnect = tween.Completed:Connect(
		function ()
			self.currentTween = nil;

			(self.tweenCompletedConnect :: RBXScriptConnection):Disconnect()
			self.tweenCompletedConnect = nil

			self:beginMoveOver()
		end
	)
	tween:Play()
end

function UpAndOverItemMover.beginMoving(self: UpAndOverItemMover)
	-- start by moving up to at least y = 20
	-- then tween to the end

	self:beginMoveUp()
end

function UpAndOverItemMover.tryBegin(self: UpAndOverItemMover): boolean

	self:beginMoving()

	return true
end

function UpAndOverItemMover.destroy(self: UpAndOverItemMover)
	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end

	if self.tweenCompletedConnect then
		self.tweenCompletedConnect:Disconnect()
		self.tweenCompletedConnect = nil
	end

	super.destroy(self)
end

function UpAndOverItemMover.new(itemId: number, endCFrame: CFrame): UpAndOverItemMover
	local self = (setmetatable(super.new(itemId, endCFrame), UpAndOverItemMover) :: any) :: UpAndOverItemMover

	return self
end

return UpAndOverItemMover
