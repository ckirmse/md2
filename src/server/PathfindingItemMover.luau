--!strict

local ItemMover = require("./ItemMover")
local super = ItemMover

local Types = require("./Types")

local PathfindingItemMover = {}
PathfindingItemMover.__index = setmetatable(PathfindingItemMover, super)

local pathfindingService = game:GetService("PathfindingService")
local tweenService = game:GetService("TweenService")

type PathfindingItemMoverFields = {
	-- ItemMover fields
	itemId: number,
	beginCFrame: CFrame,
	endCFrame: CFrame,
	stepCallbackFunc: ((CFrame) -> ())?,
	-- PathfindingItemMover fields
	waypoints: { PathWaypoint },
	waypointIndex: number,
	currentTween: Tween?,
	tweenCompletedConnect: RBXScriptConnection?,
}


export type PathfindingItemMover = Types.PathfindingItemMover

function PathfindingItemMover.beginMovingToNextWaypoint(self: PathfindingItemMover)
	if self.waypointIndex > #self.waypoints then
		self:notifyDone()
		return
	end

	local currentWaypointIndex = self.waypointIndex
	while true do
		if self.waypointIndex > #self.waypoints then
			self:beginMovingToNextWaypoint()
			return
		end

		local moveVector = self.waypoints[self.waypointIndex].Position - self.waypoints[currentWaypointIndex].Position
		if moveVector.Magnitude > 0.5 then
			break
		end

		self.waypointIndex += 1

		--print("skipping", self.waypointIndex, self.waypoints[self.waypointIndex])
	end

	--print("moving to next waypoint", self.waypointIndex, self.waypoints[self.waypointIndex])

	local waypoint = self.waypoints[self.waypointIndex]
	local diffPosition = waypoint.Position - self:getPart().Position
	local duration = diffPosition.Magnitude / 10
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Linear
	)

	local goal = {}
	goal.CFrame = CFrame.lookAlong(waypoint.Position, diffPosition)
	--print("looking along", waypoint.Position, waypoint.Position - self:getPart().Position)

	--print("tweening starting", self:getPart().Position, goal.Position)
	local tween = tweenService:Create(self:getPart(), tweenInfo, goal)
	self.currentTween = tween
	self.tweenCompletedConnect = tween.Completed:Connect(
		function ()
			self.currentTween = nil;

			(self.tweenCompletedConnect :: RBXScriptConnection):Disconnect()
			self.tweenCompletedConnect = nil

			self.waypointIndex += 1
			self:beginMovingToNextWaypoint()
		end
	)
	tween:Play()

end

function PathfindingItemMover.tryBegin(self: PathfindingItemMover): boolean

    local path = pathfindingService:CreatePath(
		{
			AgentRadius = 2,
			AgentHeight = 10,
			AgentCanJump = true,
		}
	)

    -- Compute the path from the item's current position to the destination
	local success, error = pcall(
		function()
			path:ComputeAsync(self:getPart().Position, self.endCFrame.Position)
		end
	)

    if not success then
        warn("Path computation failed:", error)

		return false
    end

    if path.Status ~= Enum.PathStatus.Success then
        warn("Path could not be found from", self:getPart().Position, "to", self.endCFrame.Position, "Status:", tostring(path.Status))

		return false
	end

	self.waypoints = path:GetWaypoints()
	self.waypointIndex = 1
	self.currentTween = nil
	self.tweenCompletedConnect = nil

	--[[
	print("got path", tostring(path))
	for _, waypoint in self.waypoints do
		print("waypoint", tostring(waypoint))
	end
	]]

	self:beginMovingToNextWaypoint()

	return true
end

function PathfindingItemMover.destroy(self: PathfindingItemMover)
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

function PathfindingItemMover.new(itemId: number, endCFrame: CFrame): PathfindingItemMover
	local self = (setmetatable(super.new(itemId, endCFrame), PathfindingItemMover) :: any) :: PathfindingItemMover

	return self
end

return PathfindingItemMover
