--!strict

local ClientXpDisplayManager = {}
ClientXpDisplayManager.__index = ClientXpDisplayManager

local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
local XpGrantBillboard = UX:WaitForChild("XpGrantBillboard")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local DURATION_SEC = 2.5
local FADE_SEC = 1

export type ClientXpDisplayManager = typeof(setmetatable({}, ClientXpDisplayManager))

function ClientXpDisplayManager.addXpTextDisplay(self: ClientXpDisplayManager, primaryElement: number, xpDiff: number, position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "XpTextAnchor"
	anchor.CFrame = CFrame.new(position)
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Parent = workspace

	-- the billboard template's shape only exists in Studio, so it is untyped here
	local billboard: any = XpGrantBillboard:Clone()
	billboard.Name = "XpBillboard"
	billboard.Adornee = anchor
	--billboard.StudsOffsetWorldSpace = Vector3.new(0, height + 1, 0)

	local elementColor = utils.get2DColorForPrimaryElement(primaryElement)

	local label = billboard:FindFirstChild("TextLabel")
	label.TextColor3 = elementColor

	label.Text = string.format("+%i XP", xpDiff)

	local uistroke = label:FindFirstChild("UIStroke")
	uistroke.Color = utils.getContrastingColor(elementColor)

	billboard.Parent = workspace

	local tweenInfo = TweenInfo.new(
		DURATION_SEC
	)
	local goal: { [string]: any } = {StudsOffset = Vector3.new(0, 1, 0)}
	local tween
	tween = tweenService:Create(billboard, tweenInfo, goal)

	tween.Completed:Connect(
		function()
			--print("destroying xp billboard")
			billboard:Destroy()
			anchor:Destroy()
		end
	)

	task.delay(DURATION_SEC - FADE_SEC,
		function()
			local tweenInfo = TweenInfo.new(
				FADE_SEC,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			local goal: { [string]: any } = {TextTransparency = 1}
			local tween
			tween = tweenService:Create(label, tweenInfo, goal)
			tween:Play()

			goal = {Transparency = 1}
			tween = tweenService:Create(uistroke, tweenInfo, goal)
			tween:Play()
		end
	)

	tween:Play()
end

function ClientXpDisplayManager.new(): ClientXpDisplayManager
	local self = setmetatable({}, ClientXpDisplayManager)


	return self
end

local singleton = ClientXpDisplayManager.new()

return singleton
