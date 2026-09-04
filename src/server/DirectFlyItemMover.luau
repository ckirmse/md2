--!strict

local ItemMover = require("./ItemMover")
local super = ItemMover

local Types = require("./Types")

local DirectFlyItemMover = {}
DirectFlyItemMover.__index = setmetatable(DirectFlyItemMover, super)

local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")

type DirectFlyItemMoverFields = {
	-- ItemMover fields
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
	-- DirectFlyItemMover fields
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
}


-- this is pretty clunky and not very usable, but good simple test framework to move an item

export type DirectFlyItemMover = Types.DirectFlyItemMover

function DirectFlyItemMover.beginMoving(self: DirectFlyItemMover)
	local diff = self.endCFrame.Position - self.beginCFrame.Position
	local duration = diff.Magnitude / 10
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Linear
	)

	local tween = PivotToTween(self:getObj(), tweenInfo, self.endCFrame)
	self.currentTween = tween
	self.tweenCompletedConnect = tween.Completed:Connect(
		function ()
			self.currentTween = nil;

			(self.tweenCompletedConnect :: RBXScriptConnection):Disconnect()
			self.tweenCompletedConnect = nil

			self:notifyDone()
		end
	)
	tween:Play()
end

function DirectFlyItemMover.tryBegin(self: DirectFlyItemMover): boolean

	self:beginMoving()

	return true
end

function DirectFlyItemMover.destroy(self: DirectFlyItemMover)
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

function DirectFlyItemMover.new(itemId: number, endCFrame: CFrame): DirectFlyItemMover
	local self = (setmetatable(super.new(itemId, endCFrame), DirectFlyItemMover) :: any) :: DirectFlyItemMover

	return self
end

return DirectFlyItemMover
