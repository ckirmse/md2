--!strict

local NumberLabelAnimator = {}
NumberLabelAnimator.__index = NumberLabelAnimator

local runService = game:GetService("RunService")

--local instanceCount = 0

type NumberLabelAnimatorFields = {
	obj: TextLabel,
	startValue: number,
	diffValue: number,
	duration: number,
	elapsedTime: number,
	event: BindableEvent?,
	Completed: RBXScriptSignal?,
	heartbeatConnect: RBXScriptConnection?,
}

export type NumberLabelAnimator = typeof(setmetatable({} :: NumberLabelAnimatorFields, NumberLabelAnimator))

function NumberLabelAnimator.destroy(self: NumberLabelAnimator)
	local heartbeatConnect = self.heartbeatConnect
	if heartbeatConnect then
		heartbeatConnect:Disconnect()
		self.heartbeatConnect = nil
	end

	local event = self.event
	if event then
		event:Destroy()
		self.event = nil
		self.Completed = nil
	end
end

function NumberLabelAnimator.new(obj: TextLabel, startValue: number, diffValue: number, duration: number): NumberLabelAnimator
	local self = setmetatable({} :: NumberLabelAnimatorFields, NumberLabelAnimator)

	--print("going from", startValue, "diff", diffValue)
	--instanceCount += 1
	--local ic = instanceCount

	self.obj = obj
	self.startValue = startValue
	self.diffValue = diffValue
	self.duration = duration

	self.elapsedTime = 0

	local event = Instance.new("BindableEvent")
	self.event = event
	self.Completed = event.Event

	local minValue = math.min(startValue, startValue + diffValue)
	local maxValue = math.max(startValue, startValue + diffValue)

	self.heartbeatConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			self.elapsedTime = math.min(self.duration, self.elapsedTime + deltaTime)
			local value = math.clamp(math.floor(startValue + diffValue * self.elapsedTime / self.duration), minValue, maxValue)
			--print("values", startValue, diffValue, self.elapsedTime, self.duration)
			--print("setting", obj, "to", value)
			self.obj.Text = tostring(value)

			if self.elapsedTime == self.duration then
				local heartbeatConnect = self.heartbeatConnect
				if heartbeatConnect then
					heartbeatConnect:Disconnect()
					self.heartbeatConnect = nil
				end

				event:Fire()
				if self.event then
					self.event = nil
					self.Completed = nil
				end
				event:Destroy()

				return
			end

		end
	)

	return self
end

return NumberLabelAnimator
