--!strict

local TargetBase = {}
TargetBase.__index = TargetBase

local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
local ItemGroundCircle = Effects:WaitForChild("ItemGroundCircle") :: BasePart

type TargetBaseFields = {
	obj: BasePart?, -- nil only after destroy()
	itemGroundCircleSize: Vector3,
	itemGroundCircleBaseTransparency: number,
	itemGroundCircleInteriorSize: Vector3,
	itemGroundCircleInteriorBaseTransparency: number,
	isShown: boolean,
}

export type TargetBase = typeof(setmetatable({} :: TargetBaseFields, TargetBase))

function TargetBase.getObj(self: TargetBase): BasePart?

	return self.obj

end

function TargetBase.animateShowOrHide(self: TargetBase, doShow: boolean)
	if doShow == self.isShown then
		return
	end

	-- valid until destroy(); callers only animate a live target
	local itemGroundCircle = self.obj :: BasePart

	local duration = 0.2
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local circleGoal: { [string]: any } = {}
	local interiorGoal: { [string]: any } = {}
	if doShow then
		--print("animate showing circles")
		circleGoal.Size = self.itemGroundCircleSize
		circleGoal.Transparency = self.itemGroundCircleBaseTransparency
		interiorGoal.Size = self.itemGroundCircleInteriorSize
		interiorGoal.Transparency = self.itemGroundCircleInteriorBaseTransparency
	else
		--print("animate hiding circles")
		circleGoal.Size = Vector3.zero
		circleGoal.Transparency = 1
		interiorGoal.Size = Vector3.zero
		interiorGoal.Transparency = 1
	end

	local tweenCircle = tweenService:Create(itemGroundCircle, tweenInfo, circleGoal)
	tweenCircle:Play()

	local interior = itemGroundCircle:FindFirstChild("TransparentInterior") :: BasePart
	local tweenInterior = tweenService:Create(interior, tweenInfo, interiorGoal)
	tweenInterior:Play()

	self.isShown = doShow
end

function TargetBase.show(self: TargetBase)
	local itemGroundCircle = self.obj :: BasePart

	itemGroundCircle.Size = self.itemGroundCircleSize
	itemGroundCircle.Transparency = self.itemGroundCircleBaseTransparency

	local interior = itemGroundCircle:FindFirstChild("TransparentInterior") :: BasePart

	interior.Size = self.itemGroundCircleInteriorSize
	interior.Transparency = self.itemGroundCircleInteriorBaseTransparency

	self.isShown = true
end

function TargetBase.hide(self: TargetBase)
	local itemGroundCircle = self.obj :: BasePart

	itemGroundCircle.Size = Vector3.zero
	itemGroundCircle.Transparency = 1

	local interior = itemGroundCircle:FindFirstChild("TransparentInterior") :: BasePart

	interior.Size = Vector3.zero
	interior.Transparency = 1

	self.isShown = false
end

function TargetBase.animateShow(self: TargetBase)
	local doShow = true
	self:animateShowOrHide(doShow)
end

function TargetBase.animateHide(self: TargetBase)
	local doShow = false
	self:animateShowOrHide(doShow)
end

function TargetBase.setPosition(self: TargetBase, position: Vector3)
	(self.obj :: BasePart):PivotTo(CFrame.fromEulerAnglesXYZ(0, math.rad(90), math.rad(90)) + (position + Vector3.new(0, 0.01, 0)))
end

function TargetBase.getParent(self: TargetBase): Instance?
	return (self.obj :: BasePart).Parent
end

function TargetBase.setParent(self: TargetBase, parent: Instance?)
	local obj = self.obj :: BasePart
	if parent == obj.Parent then
		return
	end

	self:hide()

	obj.Parent = parent

	self:animateShow()
end

function TargetBase.destroy(self: TargetBase)
	local obj = self.obj
	if obj then
		obj:Destroy()
	end
	self.obj = nil
end

function TargetBase.new(parent: Instance, size: number, color: Color3?): TargetBase
	local self = setmetatable({} :: TargetBaseFields, TargetBase)

	local itemGroundCircle = ItemGroundCircle:Clone()
	itemGroundCircle.Name = "TargetBase"
	local baseSize = itemGroundCircle.Size.Z

	-- cylinder is on its side (that's just how it needs to be), so the thin height we think of as the Y coordinate is actually the X

	-- store the standard data for later use
	self.itemGroundCircleSize = Vector3.new(itemGroundCircle.Size.X, size, size)
	self.itemGroundCircleBaseTransparency = ItemGroundCircle.Transparency

	local interior = itemGroundCircle:FindFirstChild("TransparentInterior") :: BasePart
	self.itemGroundCircleInteriorSize = Vector3.new(interior.Size.X, interior.Size.Y * (size / baseSize), interior.Size.Z * (size / baseSize))
	self.itemGroundCircleInteriorBaseTransparency = interior.Transparency

	-- start it not visible so it can animate in

	itemGroundCircle.Size = Vector3.zero
	interior.Size = Vector3.zero

	if color then
		itemGroundCircle.Color = color
	end

	itemGroundCircle.Parent = parent

	self.obj = itemGroundCircle

	self.isShown = false

	return self
end

return TargetBase
