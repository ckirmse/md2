--!strict

-- Rainbow gradient sweeping across a text label. start() returns a stop function; the UIGradient stays on the label
-- so a later start() reuses it.
local RainbowSweep = {}

local TweenService = game:GetService("TweenService")

local SWEEP_SEC = 1.2

local COLOR_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
	ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
	ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
	ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
	ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
	ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
})

function RainbowSweep.start(label: GuiObject): () -> ()
	local gradient = label:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Color = COLOR_SEQUENCE
		gradient.Rotation = 0
		gradient.Parent = label
	end
	local sweepGradient: UIGradient = assert(gradient)

	local running = true
	task.spawn(function()
		while running and sweepGradient.Parent do
			sweepGradient.Offset = Vector2.new(-1, 0)
			local sweep = TweenService:Create(sweepGradient, TweenInfo.new(SWEEP_SEC, Enum.EasingStyle.Linear), { Offset = Vector2.new(1, 0) })
			sweep:Play()
			sweep.Completed:Wait()
		end
	end)

	return function()
		running = false
	end
end

return RainbowSweep
