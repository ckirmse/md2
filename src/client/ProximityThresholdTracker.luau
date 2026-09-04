--!strict

local ProximityThresholdTracker = {}
ProximityThresholdTracker.__index = ProximityThresholdTracker

local player = game:GetService("Players").LocalPlayer :: Player

-- absent = no character/root part that frame (before first spawn, between death and respawn)
type ProximityState = "inside" | "outside" | "absent"

type ProximityThresholdTrackerFields = {
	position: Vector3,
	thresholdDistance: number,
	prevState: ProximityState?,
	enterEvent: BindableEvent?,
	leaveEvent: BindableEvent?,
	runConnect: RBXScriptConnection?,
}

export type ProximityThresholdTracker = typeof(setmetatable({} :: ProximityThresholdTrackerFields, ProximityThresholdTracker))

function ProximityThresholdTracker.getDistance(self: ProximityThresholdTracker): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not root then
		return nil
	end

	return (root.Position - self.position).Magnitude
end

function ProximityThresholdTracker.isInProximity(self: ProximityThresholdTracker): boolean
	local distance = self:getDistance()
	if distance == nil then
		return false
	end

	return distance <= self.thresholdDistance
end

-- valid until destroy(); the cast records that callers only use a live tracker
function ProximityThresholdTracker.getEnterEvent(self: ProximityThresholdTracker): RBXScriptSignal
	return (self.enterEvent :: BindableEvent).Event
end

function ProximityThresholdTracker.getLeaveEvent(self: ProximityThresholdTracker): RBXScriptSignal
	return (self.leaveEvent :: BindableEvent).Event
end

function ProximityThresholdTracker.destroy(self: ProximityThresholdTracker)
	local enterEvent = self.enterEvent
	if enterEvent then
		enterEvent:Destroy()
		self.enterEvent = nil
	end

	local leaveEvent = self.leaveEvent
	if leaveEvent then
		leaveEvent:Destroy()
		self.leaveEvent = nil
	end

	local runConnect = self.runConnect
	if runConnect then
		runConnect:Disconnect()
		self.runConnect = nil
	end

end

function ProximityThresholdTracker.new(position: Vector3, distance: number): ProximityThresholdTracker
	local self = setmetatable({} :: ProximityThresholdTrackerFields, ProximityThresholdTracker)

	self.position = position
	self.thresholdDistance = distance

	self.prevState = nil

	self.enterEvent = Instance.new("BindableEvent")
	self.leaveEvent = Instance.new("BindableEvent")

	self.runConnect = game:GetService("RunService").PostSimulation:Connect(
		function(deltaTime)
			local distance = self:getDistance()

			local state: ProximityState

			if distance == nil then
				state = "absent"
			elseif distance <= self.thresholdDistance then
				state = "inside"
			else
				state = "outside"
			end

			local prevState = self.prevState
			self.prevState = state

			if prevState == nil or prevState == state then
				return
			end

			if prevState == "inside" then
				local leaveEvent = self.leaveEvent
				if leaveEvent then
					leaveEvent:Fire()
				end
			elseif state == "inside" then
				local enterEvent = self.enterEvent
				if enterEvent then
					enterEvent:Fire()
				end
			end

		end
	)

	return self
end

return ProximityThresholdTracker
