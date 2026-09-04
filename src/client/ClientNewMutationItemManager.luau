--!strict

local ClientNewMutationItemManager = {}
ClientNewMutationItemManager.__index = ClientNewMutationItemManager

local tweenService = game:GetService("TweenService")

local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = game:GetService("Players").LocalPlayer :: Player
local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local MutationGachaFanfare: any = PlayerGui:WaitForChild("MutationGachaFanfare")

local GROW_SEC = 0.2
local DEFAULT_CAMERA_POSITION = Vector3.new(0, 2, 5)

-- server-sent payload (NotifyMutationStorePurchase and friends); genuinely dynamic
type MutationItemData = {
	text: any,
	templatePath: any,
	mutation: any,
	mutationSurfaceAppearanceName: any,
	cameraPosition: any,
}

type ClientNewMutationItemManagerFields = {
	mutationItemQueue: { MutationItemData },
	inFanfare: boolean,
}

export type ClientNewMutationItemManager = typeof(setmetatable({} :: ClientNewMutationItemManagerFields, ClientNewMutationItemManager))

function ClientNewMutationItemManager.showNewMutationItem(self: ClientNewMutationItemManager)
	self.inFanfare = true

	local itemData = table.remove(self.mutationItemQueue, 1) :: MutationItemData

	local Main = MutationGachaFanfare:FindFirstChild("Main")
	local UnlockInfo = Main:FindFirstChild("UnlockInfo")
	local MutationAsset = Main:FindFirstChild("MutationAsset")

	UnlockInfo.Text = itemData.text

	for _, child in MutationAsset:GetChildren() do
		child:Destroy()
	end

	local inst = utils.getGameAssetPathReference(itemData.templatePath)
	if inst then
		local obj: any = inst:Clone()
		obj:PivotTo(obj:GetPivot().Rotation + Vector3.zero)
		obj.Parent = MutationAsset

		utils.applyMutationToObj(obj, itemData.mutation, itemData.mutationSurfaceAppearanceName)

		local viewportCamera = Instance.new("Camera")
		MutationAsset.CurrentCamera = viewportCamera
		viewportCamera.Parent = MutationAsset
		local cameraOffset
		if itemData.cameraPosition then
			cameraOffset = Vector3.new(itemData.cameraPosition[1], itemData.cameraPosition[2], itemData.cameraPosition[3])
		else
			cameraOffset = DEFAULT_CAMERA_POSITION
		end

		viewportCamera.CFrame = CFrame.new(obj:GetPivot().Position + cameraOffset, obj:GetPivot().Position)
	end

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
	tweenService:Create(Main, tweenInfo, goal):Play()

	MutationGachaFanfare.Enabled = true

	task.wait(GROW_SEC + 3)

	MutationGachaFanfare.Enabled = false

	self.inFanfare = false

	self:showNewMutationItemIfNeeded()
end

function ClientNewMutationItemManager.showNewMutationItemIfNeeded(self: ClientNewMutationItemManager)
	if #self.mutationItemQueue >= 1 then
		task.defer(
			function()
				self:showNewMutationItem()
			end
		)
	end
end

function ClientNewMutationItemManager.notifyNewMutationItem(self: ClientNewMutationItemManager, text: any, templatePath: any, mutation: any, mutationSurfaceAppearanceName: any, cameraPosition: any)
	table.insert(self.mutationItemQueue,
		{
			text = text,
			templatePath = templatePath,
			mutation = mutation,
			mutationSurfaceAppearanceName = mutationSurfaceAppearanceName,
			cameraPosition = cameraPosition
		}
	)

	if not self.inFanfare then
		self:showNewMutationItemIfNeeded()
	end
end

function ClientNewMutationItemManager.init(self: ClientNewMutationItemManager)
end

function ClientNewMutationItemManager.new(): ClientNewMutationItemManager
	local self = setmetatable({} :: ClientNewMutationItemManagerFields, ClientNewMutationItemManager)

	self.mutationItemQueue = {}
	self.inFanfare = false

	return self
end

local singleton = ClientNewMutationItemManager.new()

return singleton
