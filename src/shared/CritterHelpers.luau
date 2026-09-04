--!strict

local CritterHelpers = {}

function CritterHelpers.calculateCFrame(center: Vector3, radius: number, angle: number): CFrame
	-- Chain the CFrames (reads left-to-right)
	-- 1. CFrame.new(center) moves the pivot to the center of the circle.
	-- 2. CFrame.Angles(...) rotates that pivot over time around the Y axis.
	-- 3. CFrame.new(radius, 0, 0) slides the part out to the edge of the circle.
	-- finally, rotate 90 degrees so it's facing towards the direction of motion
	return CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
end

return CritterHelpers
