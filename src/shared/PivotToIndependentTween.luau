--!strict

local TweenService = game:GetService("TweenService")

local tween = require("./tween")

-- this eses the tween library (tween.lua) for the independent tweens, for better control by us
-- might need to further customize to add more possibilities!

type Easing = (string | tween.EasingFn)?

local function PivotToIndependentTween(inst: PVInstance, duration: number, rotationEasing: Easing, xEasing: Easing, yEasing: Easing, zEasing: Easing, endCFrame: CFrame, stepCallbackFunc: ((CFrame) -> ())?): Tween
	local startCFrame = inst:GetPivot()

	--print("pivottoindependenttween endcframe", endCFrame)

	local values = {rotation = 0, x = 0, y = 0, z = 0}
	local rotationTween = tween.new(1, values, {rotation = 1}, rotationEasing)
	local xTween = tween.new(1, values, {x = 1}, xEasing)
	local yTween = tween.new(1, values, {y = 1}, yEasing)
	local zTween = tween.new(1, values, {z = 1}, zEasing)

	local latestUpdate = 0

	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv:GetPropertyChangedSignal("Value"):Connect(
		function()
			local delta = nv.Value - latestUpdate
			latestUpdate = nv.Value
			--print("piit value", nv.Value, "delta", delta)

			rotationTween:update(delta)
			xTween:update(delta)
			yTween:update(delta)
			zTween:update(delta)

			--print("rot", values.rotation, "x", values.x, "y", values.y, "z", values.z)

			local cframe = startCFrame.Rotation:Lerp(endCFrame.Rotation, values.rotation)
			local x = startCFrame.Position.X + (values.x * (endCFrame.Position.X - startCFrame.Position.X))
			local y = startCFrame.Position.Y + (values.y * (endCFrame.Position.Y - startCFrame.Position.Y))
			local z = startCFrame.Position.Z + (values.z * (endCFrame.Position.Z - startCFrame.Position.Z))

			cframe = cframe + Vector3.new(x, y, z)
			--print("setting to position", cframe.Position)
			inst:PivotTo(cframe)

			if stepCallbackFunc then
				stepCallbackFunc(cframe)
			end
		end
	)

	local robloxTween = TweenService:Create(nv, TweenInfo.new(duration), {Value = 1})
	robloxTween.Completed:Connect(
		function()
			nv:Destroy()
		end
	)
	return robloxTween
end

return PivotToIndependentTween
