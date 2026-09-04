--!strict

local ClientNewBlueprintManager = {}
ClientNewBlueprintManager.__index = ClientNewBlueprintManager

local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
-- the audio template's shape only exists in Studio, so it is untyped here
local NewBlueprintAudioParent: any = Effects:WaitForChild("NewBlueprintAudioParent")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")


local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local NewBlueprintFanfare: any = PlayerGui:WaitForChild("NewBlueprintFanfare")

type BlueprintData = {
	itemName: string,
	rarity: number,
}

type ClientNewBlueprintManagerFields = {
	blueprintDataQueue: { BlueprintData },
	inFanfare: boolean,
	newBlueprintAudioParent: any?,
}

export type ClientNewBlueprintManager = typeof(setmetatable({} :: ClientNewBlueprintManagerFields, ClientNewBlueprintManager))

function ClientNewBlueprintManager.showNewBlueprint(self: ClientNewBlueprintManager)
	self.inFanfare = true

	local blueprintData = table.remove(self.blueprintDataQueue, 1) :: BlueprintData

	local rarity = blueprintData.rarity
	local rarityName = enums.getPublicName(enums.Rarity, rarity) :: string
	local iconName = string.format("BlueprintIcon%s", rarityName)

	local Main = NewBlueprintFanfare:FindFirstChild("Main")

	local icon: any

	local allIcons = Main:QueryDescendants("ImageLabel")
	for _, thisIcon in allIcons do
		if thisIcon.Name == iconName then
			icon = thisIcon
			thisIcon.Visible = true
		else
			thisIcon.Visible = false
		end
	end

	local UnlockInfo = Main:FindFirstChild("UnlockInfo")

	UnlockInfo.Text = string.format("You received %s", blueprintData.itemName)
	UnlockInfo.TextColor3 = utils.getColorForRarity(rarity)

	local GROW_SEC = 0.2

	do
		-- grow from zero height to desired height
		local baseMainSize = Main.Size
		Main.Size = UDim2.new(Main.Size.X.Scale, Main.Size.X.Offset, 0, 0)
		local tweenInfo = TweenInfo.new(
			GROW_SEC,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In,
			0,
			false,
			0
		)
		local goal = {}
		goal.Size = baseMainSize

		local tween = tweenService:Create(Main, tweenInfo, goal)
		tween:Play()
	end

	NewBlueprintFanfare.Enabled = true;

	(self.newBlueprintAudioParent :: any):FindFirstChild("AudioNewBlueprint"):Play()

	task.wait(GROW_SEC)

	local MAX_DEGREES = 25
	local STEP_SEC = 0.08
	local NUM_STEPS = 2

	local tweenInfo
	tweenInfo = TweenInfo.new(
		STEP_SEC / 2,
		Enum.EasingStyle.Linear
	)
	local goal: { [string]: any } = {}
	goal.Rotation = MAX_DEGREES
	tweenService:Create(icon, tweenInfo, goal):Play()
	task.wait(STEP_SEC / 2)

	tweenInfo = TweenInfo.new(
		STEP_SEC,
		Enum.EasingStyle.Linear
	)
	for i = 1, NUM_STEPS do
		goal.Rotation = -MAX_DEGREES
		tweenService:Create(icon, tweenInfo, goal):Play()
		task.wait(STEP_SEC)

		goal.Rotation = MAX_DEGREES
		tweenService:Create(icon, tweenInfo, goal):Play()
		task.wait(STEP_SEC)
	end

	tweenInfo = TweenInfo.new(
		STEP_SEC / 2,
		Enum.EasingStyle.Linear
	)
	goal.Rotation = 0
	tweenService:Create(icon, tweenInfo, goal):Play()
	task.wait(STEP_SEC / 2)

	task.wait(3)

	NewBlueprintFanfare.Enabled = false

	self.inFanfare = false

	self:showNewBlueprintIfNeeded()
end

function ClientNewBlueprintManager.showNewBlueprintIfNeeded(self: ClientNewBlueprintManager)
	if #self.blueprintDataQueue >= 1 then
		task.defer(
			function()
				--print("showing new blueprint")
				self:showNewBlueprint()
			end
		)
	end
end

function ClientNewBlueprintManager.notifyNewBlueprint(self: ClientNewBlueprintManager, itemName: string, rarity: number)
	table.insert(self.blueprintDataQueue,
		{
			itemName = itemName,
			rarity = rarity,
		}
	)

	if not self.inFanfare then
		self:showNewBlueprintIfNeeded()
	end
end

function ClientNewBlueprintManager.initWorldInterface(self: ClientNewBlueprintManager)
	local newBlueprintAudioParent = NewBlueprintAudioParent:Clone()
	newBlueprintAudioParent.Parent = workspace
	self.newBlueprintAudioParent = newBlueprintAudioParent

end

function ClientNewBlueprintManager.init(self: ClientNewBlueprintManager)
	self:initWorldInterface()
end

function ClientNewBlueprintManager.new(): ClientNewBlueprintManager
	local self = setmetatable({} :: ClientNewBlueprintManagerFields, ClientNewBlueprintManager)

	self.blueprintDataQueue = {}

	self.inFanfare = false

	return self
end

local singleton = ClientNewBlueprintManager.new()

return singleton
