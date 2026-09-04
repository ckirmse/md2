--!strict

local TweenService = game:GetService("TweenService")

-- based on help from https://devforum.roblox.com/t/tweening-models/60545/20
local function PivotToTween(inst: PVInstance, tweenInfo: TweenInfo, endCFrame: CFrame, stepCallbackFunc: ((CFrame) -> ())?): Tween
	local startCFrame = inst:GetPivot()

	--print("pivottotween endcframe", endCFrame)

	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv:GetPropertyChangedSignal("Value"):Connect(
		function()
			local value = nv.Value
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

return PivotToTween
