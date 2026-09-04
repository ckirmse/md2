--!strict

local TweenService = game:GetService("TweenService")

-- this follows an instance... and GETS THERE even if it's moving
local function PivotToTargetTween(inst: PVInstance, tweenInfo: TweenInfo, target: PVInstance, stepCallbackFunc: ((CFrame) -> ())?): Tween
	local startCFrame = inst:GetPivot()

	--print("pivottotargettween target", target)

	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv:GetPropertyChangedSignal("Value"):Connect(
		function()
			local value = nv.Value
			local endCFrame = target:GetPivot()
			local cframe = startCFrame:Lerp(endCFrame, value)
			--print("pivoting based on value", value, startCFrame.Position, "to", endCFrame.Position, "current", cframe.Position)
			inst:PivotTo(cframe)
			if stepCallbackFunc then
				stepCallbackFunc(cframe)
			end
		end
	)

	local tween = TweenService:Create(nv, tweenInfo, {Value = 1})
	tween.Completed:Connect(
		function()
			nv:Destroy()
		end
	)

	return tween
end

return PivotToTargetTween
