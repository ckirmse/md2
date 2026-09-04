--!strict

local TweenService = game:GetService("TweenService")

local function ScaleToTween(inst: Model, tweenInfo: TweenInfo, endScale: number): Tween
	local startScale = inst:GetScale()

	--print("scaletotween endcframe", endCFrame)

	local nv = Instance.new("NumberValue")
	nv.Value = 0
	nv:GetPropertyChangedSignal("Value"):Connect(
		function()
			local value = nv.Value
			local scale = startScale + (endScale - startScale) * value
			--print("scaling based on value", value, startScale, "to", endScale, "current", scale)
			inst:ScaleTo(scale)
		end
	)

	local tween = TweenService:Create(nv, tweenInfo, {Value = 1})

	return tween
end

return ScaleToTween
