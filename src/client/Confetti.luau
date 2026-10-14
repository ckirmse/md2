--!strict

-- Full-screen confetti: coloured pieces falling from above the top edge to below the bottom edge of a gui.
local Confetti = {}

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local CONFETTI_COUNT = 40
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(90, 160, 255),
	Color3.fromRGB(220, 110, 255),
}
local CONFETTI_MIN_FALL_SEC = 1.2
local CONFETTI_MAX_FALL_SEC = 2.0
local CONFETTI_SIZE_PX = 42

-- gui is the parent the pieces fill (a ScreenGui or a full-size frame)
function Confetti.play(gui: Instance, random: Random)
	local container = Instance.new("Frame")
	container.Name = "Confetti"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = 10
	container.Parent = gui

	for pieceIndex = 1, CONFETTI_COUNT do
		local piece = Instance.new("Frame")
		piece.BackgroundColor3 = CONFETTI_COLORS[(pieceIndex - 1) % #CONFETTI_COLORS + 1]
		piece.BorderSizePixel = 0
		piece.Size = UDim2.fromOffset(CONFETTI_SIZE_PX, CONFETTI_SIZE_PX // 2)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(random:NextNumber(), -0.1 - 0.3 * random:NextNumber())
		piece.Rotation = random:NextInteger(-180, 180)
		piece.ZIndex = 10
		piece.Parent = container

		local fallSec = CONFETTI_MIN_FALL_SEC + (CONFETTI_MAX_FALL_SEC - CONFETTI_MIN_FALL_SEC) * random:NextNumber()
		TweenService:Create(piece, TweenInfo.new(fallSec, Enum.EasingStyle.Linear), {
			Position = UDim2.fromScale(piece.Position.X.Scale, 1.15),
			Rotation = piece.Rotation + random:NextInteger(-360, 360),
		}):Play()
	end

	Debris:AddItem(container, CONFETTI_MAX_FALL_SEC + 0.1)
end

return Confetti
