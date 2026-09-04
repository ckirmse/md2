--!strict

local ClientFtueManager = {}
ClientFtueManager.__index = ClientFtueManager

local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local FtueSteps = require("@game/ReplicatedStorage/Shared/FtueSteps")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local overlayTracker = require("./OverlayTracker")
local screenGuiManager = require("./ScreenGuiManager")
local Teleporters = require("./Teleporters")
local Types = require("./Types")
local clientBuyStore: Types.ClientBuyStore -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientSellStore = require("./ClientSellStore")
local customProximityPrompt = require("./CustomProximityPrompt")

local player = game:GetService("Players").LocalPlayer :: Player

type TrackMoveToLocation = {
	position: Vector3,
	maxDistance: number,
}

type ClientFtueManagerFields = {
	ftueProgress: any, -- server-sent progress record
	trackMoveToLocation: TrackMoveToLocation?,
	event: BindableEvent,
	runConnect: RBXScriptConnection?,
	beamWaitConnect: RBXScriptConnection?,
	activeBeamData: any?,
	billboardAnchor: BasePart?,
	frame: any?,
	stroke: any?,
}

export type ClientFtueManager = typeof(setmetatable({} :: ClientFtueManagerFields, ClientFtueManager))

function ClientFtueManager.beginTrackMoveToLocation(self: ClientFtueManager, position: Vector3, maxDistance: number, nextStepName: string)
	self.trackMoveToLocation = {
		position = position,
		maxDistance = maxDistance,
	}

	--print("tracking to", position, maxDistance, nextStepName)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	self.runConnect = runService.PostSimulation:Connect(
		function(deltaTime)

			local trackMoveToLocation = self.trackMoveToLocation
			if not trackMoveToLocation then
				return
			end

			if (humanoidRootPart.Position - trackMoveToLocation.position).Magnitude > trackMoveToLocation.maxDistance then
				return
			end

			self.trackMoveToLocation = nil

			RemoteEvents.TrySetFtueStep:FireServer(nextStepName)
		end
	)
end

-- configurations is the list of things that are about to be enabled
function ClientFtueManager.cleanupActiveFtue(self: ClientFtueManager, configurations: any)
	screenGuiManager:clearFtueMessage()

	local shouldEnableBuyStore = true
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.DISABLE_BUY_STORE then
			continue
		end

		shouldEnableBuyStore = false
		break
	end
	if shouldEnableBuyStore then
		clientBuyStore:setEnabled()
	end

	local shouldEnableSellStore = true
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.DISABLE_SELL_STORE then
			continue
		end

		shouldEnableSellStore = false
		break
	end
	if shouldEnableSellStore then
		clientSellStore:setEnabled()
	end

	local shouldShowTeleporters = true
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.HIDE_TELEPORTERS then
			continue
		end

		shouldShowTeleporters = false
		break
	end
	if shouldShowTeleporters then
		Teleporters:showTeleporters()
	end

	local shouldDisablePromptAnimations = true
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.ANIMATE_PROMPTS then
			continue
		end

		shouldDisablePromptAnimations = false
		break
	end
	if shouldDisablePromptAnimations then
		customProximityPrompt:setPromptAnimations(false)
	end
	customProximityPrompt:setPromptAnimations(false)

	local runConnect = self.runConnect
	if runConnect then
		runConnect:Disconnect()
		-- as of 2026-august-12 this clears runConnect; it previously wrote a misspelled
		-- runnConnect field, so the stale connection reference was kept around
		self.runConnect = nil
	end

	local beamWaitConnect = self.beamWaitConnect
	if beamWaitConnect then
		beamWaitConnect:Disconnect()
		self.beamWaitConnect = nil
	end

	local activeBeamData = self.activeBeamData
	if activeBeamData then
		if activeBeamData.beam then
			activeBeamData.beam:Destroy()
		end

		if activeBeamData.attachment1 then
			activeBeamData.attachment1:Destroy()
		end

		if activeBeamData.attachment2 then
			activeBeamData.attachment2:Destroy()
		end

		if activeBeamData.beamAnchor then
			activeBeamData.beamAnchor:Destroy()
		end
		self.activeBeamData = nil
	end

	local billboardAnchor = self.billboardAnchor
	if billboardAnchor then
		billboardAnchor:Destroy()
		self.billboardAnchor = nil
	end

	local frame = self.frame
	if frame then
		frame.Visible = false
		self.frame = nil
	end

	local stroke = self.stroke
	if stroke then
		stroke:Destroy()
		self.stroke = nil
	end

end

function ClientFtueManager.findNearestItemName(self: ClientFtueManager, itemName: any): any
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	local objs = utils.getAllDescendantsWithAttribute(workspace, Attributes.PICKUP_NAME, itemName) :: { any }
	local bestDistance = math.huge
	local bestObj: any = nil
	for _, obj in objs do
		if obj.Parent ~= workspace then
			continue
		end

		if obj:GetAttribute(Attributes.USER_ID) ~= player.UserId then
			continue
		end

		if not bestObj then
			bestObj = obj
			bestDistance = (bestObj:GetPivot().Position - humanoidRootPart.Position).Magnitude
			continue
		end

		local distance = (obj:GetPivot().Position - humanoidRootPart.Position).Magnitude
		if distance < bestDistance then
			bestObj = obj
			bestDistance = distance
		end
	end

	return bestObj

end

function ClientFtueManager.updateFtueMessage(self: ClientFtueManager, stepData: any)
	local primaryTransition: any
	for _, transition in stepData.transitions do
		if transition.isPrimary then
			primaryTransition = transition
		end
	end

	local parameters: { any } = {}
	if primaryTransition.type == enums.FtueTransitionType.GET_GEMS then
		local primaryElement = primaryTransition.primaryElement
		local playerAttributesKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)
		local playerGemCount = clientPlayerAttributesManager:get(playerAttributesKeyGems)
		table.insert(parameters, math.max(0, primaryTransition.count - playerGemCount))
	end

	if primaryTransition.type == enums.FtueTransitionType.GET_ITEMS then
		for _, itemDescriptor in primaryTransition.itemDescriptors do
			local itemName = itemDescriptor.itemName
			local count = itemDescriptor.count

			local needCount = count

			for _, tool in (player :: any).Backpack:GetChildren() do
				if not tool:IsA("Tool") then
					continue
				end

				local handle = tool:FindFirstChild("Handle")
				if not handle then
					continue
				end

				local part = handle
				local model: any = utils.tryGetModelForPlayerAndItemId(player, part:GetAttribute(Attributes.ITEM_ID))
				local inst
				if model then
					inst = model
				else
					inst = part
				end

				local haveItemName = inst:GetAttribute(Attributes.PICKUP_NAME)
				local haveCount = inst:GetAttribute(Attributes.COUNT)
				if haveItemName == itemName then
					needCount = math.max(0, count - haveCount)
					break
				end
			end
			table.insert(parameters, needCount)
		end
	end

	local configurations = stepData.configuration
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.MESSAGE then
			continue
		end

		local str = string.format(configuration.message, table.unpack(parameters))
		screenGuiManager:showFtueMessage(str)
	end
end

function ClientFtueManager.updateBuyItemMessage(self: ClientFtueManager, stepData: any)
	local configurations = stepData.configuration
	for _, configuration in configurations do
		if configuration.type ~= enums.FtueConfigurationType.BUY_ITEM then
			continue
		end

		local parameters: { any } = {}

		local itemName = configuration.itemName
		local count = configuration.count

		local needCount = count

		for _, tool in (player :: any).Backpack:GetChildren() do
			if not tool:IsA("Tool") then
				continue
			end

			local handle = tool:FindFirstChild("Handle")
			if not handle then
				continue
			end

			local part = handle
			local model: any = utils.tryGetModelForPlayerAndItemId(player, part:GetAttribute(Attributes.ITEM_ID))
			local inst
			if model then
				inst = model
			else
				inst = part
			end

			local haveItemName = inst:GetAttribute(Attributes.PICKUP_NAME)
			local haveCount = inst:GetAttribute(Attributes.COUNT)
			if haveItemName == itemName then
				needCount = math.max(0, count - haveCount)
				break
			end
		end
		table.insert(parameters, needCount)
		local message = utils.getMessageFromTable(configuration.messageTable, needCount)
		--print("have message", configuration.message, "parameters", parameters)
		local str = string.format(message, table.unpack(parameters))
		clientBuyStore:setFtueSingleItemMode(itemName, str)
	end
end

function ClientFtueManager.createBeamAnchorAtLocation(self: ClientFtueManager, location: Vector3): BasePart
	local position = utils.getGroundPositionForLocation(location) :: Vector3

	local beamAnchor = Instance.new("Part")
	beamAnchor.Name = "FtueBeamAnchor"
	beamAnchor.Anchored = true
	beamAnchor.CanCollide = false
	beamAnchor.CanQuery = false
	beamAnchor.CanTouch = false
	beamAnchor.Transparency = 1
	beamAnchor:PivotTo(CFrame.new(position))

	return beamAnchor
end

function ClientFtueManager.setupConfiguration(self: ClientFtueManager, configuration: any, stepData: any)
	if configuration.type == enums.FtueConfigurationType.MESSAGE then
		self:updateFtueMessage(stepData)
	elseif configuration.type == enums.FtueConfigurationType.SYSTEM_MESSAGE then
		screenGuiManager:showSystemMessage(configuration.message)
	elseif configuration.type == enums.FtueConfigurationType.BEAM then
		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "FtueAttachment1"
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
		attachment1.Parent = humanoidRootPart

		local attachment2 = Instance.new("Attachment")
		attachment2.Name = "FtueAttachment2"
		local beamAnchor: BasePart?
		if configuration.destination.type == "plotLocation" then
			local plotLocation = Vector3.new(configuration.destination.plotLocation[1], 0, configuration.destination.plotLocation[2])
			local plotCFrame = Teleporters:getPlotCFrame() :: CFrame
			local location = plotCFrame * plotLocation
			local anchor = self:createBeamAnchorAtLocation(location)
			beamAnchor = anchor
			attachment2.Parent = anchor
			anchor.Parent = workspace
		elseif configuration.destination.type == "item" then
			local itemName = configuration.destination.itemName
			local obj = self:findNearestItemName(itemName)
			if obj then
				-- as of 2026-august-12 this calls GetPivot (lowercase getPivot is not a member
				-- and would have thrown here)
				local anchor = self:createBeamAnchorAtLocation(obj:GetPivot().Position)
				beamAnchor = anchor
				attachment2.Parent = anchor
				anchor.Parent = workspace
			else
				print("ftue cannot find item by itemName for beam", itemName, "; will retry")
				-- race conditions between our ftue step updating and us being told about new objects being created by the server can cause this
				self.beamWaitConnect = workspace.DescendantAdded:Connect(
					function(inst)
						local foundObj = self:findNearestItemName(itemName)
						if foundObj then
							local beamWaitConnect = self.beamWaitConnect
							if beamWaitConnect then
								beamWaitConnect:Disconnect()
							end
							self.beamWaitConnect = nil

							-- have it go through the normal process
							self:setupConfiguration(configuration, stepData)
						end
					end
				)

			end
		elseif configuration.destination.type == "fixture" then
			local fixtureName = configuration.destination.fixtureName
			local obj: any = workspace:FindFirstChild(fixtureName)
			if obj then
				attachment2.Parent = obj
			else
				warn("ftue cannot find fixture by fixtureName for beam", fixtureName)
			end
		elseif configuration.destination.type == "home" then
			local plotCFrame = Teleporters:getPlotCFrame() :: CFrame
			local position = plotCFrame.Position
			local anchor = Instance.new("Part")
			anchor.Name = "FtueBeamAnchor"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.Transparency = 1
			anchor:PivotTo(CFrame.new(position))
			beamAnchor = anchor
			attachment2.Parent = anchor
			anchor.Parent = workspace
		else
			warn("unknown beam destination type", configuration.destination.type)
		end
		local beamTemplate: any = UX:WaitForChild("FtueBeam")
		local beam = beamTemplate:Clone()
		beam.Attachment0 = attachment1
		beam.Attachment1 = attachment2
		beam.Parent = workspace

		-- save some of these things on self, and later we clean them up appropriately
		self.activeBeamData = {
			beam = beam,
			attachment1 = attachment1,
			attachment2 = attachment2,
			beamAnchor = beamAnchor,
		}
	elseif configuration.type == enums.FtueConfigurationType.ANIMATE_PROMPTS then
		customProximityPrompt:setPromptAnimations(true)
	elseif configuration.type == enums.FtueConfigurationType.BILLBOARD then
		local name = configuration.name

		local billboardTemplate: any = UX:WaitForChild(name)
		local billboard = billboardTemplate:Clone()
		local textLabel = billboard:FindFirstChild("TextLabel")
		if userInputService.PreferredInput == Enum.PreferredInput.Touch then
			textLabel.Text = configuration.touchText
		else
			textLabel.Text = configuration.defaultText
		end

		local plotLocation = Vector3.new(configuration.plotLocation[1], 0, configuration.plotLocation[2])
		local plotCFrame = Teleporters:getPlotCFrame() :: CFrame
		local location = plotCFrame * plotLocation
		local position = utils.getGroundPositionForLocation(location) :: Vector3
		local billboardAnchor = Instance.new("Part")
		billboardAnchor.Name = "FtueBillboardAnchor"
		billboardAnchor.Anchored = true
		billboardAnchor.CanCollide = false
		billboardAnchor.CanQuery = false
		billboardAnchor.CanTouch = false
		billboardAnchor.Transparency = 1
		billboardAnchor:PivotTo(CFrame.new(position))
		billboardAnchor.Parent = workspace

		billboard.Parent = billboardAnchor

		self.billboardAnchor = billboardAnchor
	elseif configuration.type == enums.FtueConfigurationType.POINT_TO_BACKPACK_FRAME then
		local name = configuration.name

		local playerGui = player:FindFirstChild("PlayerGui") :: Instance
		local ScreenGui: any = playerGui:WaitForChild("ScreenGui")

		local frame = ScreenGui:WaitForChild(name)

		-- hack into satchel to find the hotbar

		local backpackGui = (playerGui :: any).BackpackGui
		local backpack = backpackGui:WaitForChild("Backpack")
		local hotbar = backpack:WaitForChild("Hotbar")

		local position = UDim2.fromOffset(hotbar.AbsolutePosition.X + hotbar.AbsoluteSize.X / 2, hotbar.AbsolutePosition.Y)
		frame.Position = position

		local textLabel = frame:FindFirstChild("TextLabel")
		if userInputService.PreferredInput == Enum.PreferredInput.Touch then
			textLabel.Text = configuration.touchText
		else
			textLabel.Text = configuration.defaultText
		end

		frame.Visible = true

		self.frame = frame
	elseif configuration.type == enums.FtueConfigurationType.BUY_ITEM then
		self:updateBuyItemMessage(stepData)
	elseif configuration.type == enums.FtueConfigurationType.CLOSE_OVERLAYS then
		overlayTracker:closeOverlayIfExists()
	elseif configuration.type == enums.FtueConfigurationType.STROKE_2D_ELEMENT then
		local playerGui = player:FindFirstChild("PlayerGui") :: Instance
		local strokeParent = utils.getPathReference(playerGui, configuration.elementPath)
		local strokeTemplate: any = playerGui:FindFirstChild(configuration.strokeName)
		local stroke = strokeTemplate:Clone()
		stroke.Parent = strokeParent

		local duration = 0.5
		local tweenInfo = TweenInfo.new(
			duration,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true, -- reverses afterwards
			0
		)
		local goal = {}
		goal.BorderOffset = UDim.new(0, 4)
		local tween = tweenService:Create(stroke, tweenInfo, goal)
		tween:Play()

		self.stroke = stroke
	elseif configuration.type == enums.FtueConfigurationType.HIDE_TELEPORTERS then
		Teleporters:hideTeleporters()
	elseif configuration.type == enums.FtueConfigurationType.ANIMATE_IN_TELEPORTERS then
		Teleporters:animateInTeleporters()
	elseif configuration.type == enums.FtueConfigurationType.DISABLE_BUY_STORE then
		clientBuyStore:setDisabled()
	elseif configuration.type == enums.FtueConfigurationType.DISABLE_SELL_STORE then
		clientSellStore:setDisabled()
	else
		warn("unknown ftue configuration type", stepData.stepName, configuration.type)
	end

end

function ClientFtueManager.setFtueProgress(self: ClientFtueManager, ftueProgress: any)
	local prevIsFtueEnabled = not not self.ftueProgress.isEnabled

	self.ftueProgress = ftueProgress

	local isFtueEnabled = not not self.ftueProgress.isEnabled
	if isFtueEnabled ~= prevIsFtueEnabled then
		self.event:Fire(isFtueEnabled)
	end

	-- now process the current step and set things as appropriate

	--print("client ftue manager told to set progress to", ftueProgress, ftueProgress.stepName)

	if not self.ftueProgress.isEnabled then
		self:cleanupActiveFtue({})
		return
	end

	if not self.ftueProgress.stepName then
		RemoteEvents.TrySetFtueStep:FireServer(FtueSteps.getFirstFtueStepName())
		return
	end

	--print("ftue now in step", ftueProgress.stepName)

	local stepData = FtueSteps.getStepDataForStepName(ftueProgress.stepName) :: any

	local haveBuyItemMessage = false

	-- configure as needed
	local configurations = stepData.configuration

	self:cleanupActiveFtue(configurations)

	for _, configuration in configurations do
		self:setupConfiguration(configuration, stepData)

		if configuration.type == enums.FtueConfigurationType.BUY_ITEM then
			haveBuyItemMessage = true
		end
	end

	if not haveBuyItemMessage then
		clientBuyStore:clearFtueSingleItemMode()
	end

	local primaryTransition: any
	for _, transition in stepData.transitions do
		if transition.isPrimary then
			primaryTransition = transition
		end
	end

	if primaryTransition.type == enums.FtueTransitionType.PICKUP then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.MOVE_TO_PLOT_LOCATION then
		local maxDistance = primaryTransition.maxDistance
		local plotLocation = Vector3.new(primaryTransition.plotLocation[1], 0, primaryTransition.plotLocation[2])
		local plotCFrame = Teleporters:getPlotCFrame() :: CFrame
		local location = plotCFrame * plotLocation
		local position = utils.getGroundPositionForLocation(location) :: Vector3
		--print("looking for player being near", position, maxDistance)
		self:beginTrackMoveToLocation(position, maxDistance, primaryTransition.stepName)
	elseif primaryTransition.type == enums.FtueTransitionType.MOVE_TO_WORLD_LOCATION then
		local maxDistance = primaryTransition.maxDistance
		local location = Vector3.new(primaryTransition.plotLocation[1], 0, primaryTransition.plotLocation[2])
		local position = utils.getGroundPositionForLocation(location) :: Vector3
		--print("looking for player being near", position, maxDistance)
		self:beginTrackMoveToLocation(position, maxDistance, primaryTransition.stepName)
	elseif primaryTransition.type == enums.FtueTransitionType.MOVE_TO_ITEM then
		local itemName = primaryTransition.itemName
		local obj = self:findNearestItemName(itemName)
		if obj then
			local position = utils.getGroundPositionForLocation(obj:GetPivot().Position) :: Vector3
			self:beginTrackMoveToLocation(position, primaryTransition.maxDistance, primaryTransition.stepName)
		else
			warn("ftue cannot find item to move to", itemName)
		end

	elseif primaryTransition.type == enums.FtueTransitionType.MERGE then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.PLACE_ON_BOARD then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.SUMMON_TO_EAT then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.GET_GEMS then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.GET_COINS then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.GET_ITEMS then
		-- server handles this
	elseif primaryTransition.type == enums.FtueTransitionType.EQUIP_ITEM then
		-- server handles this
	else
		warn("unknown ftue complete type", ftueProgress.stepName, primaryTransition.type)
	end

end

function ClientFtueManager.isFtueActive(self: ClientFtueManager): boolean
	return not not self.ftueProgress.isEnabled
end

function ClientFtueManager.getIsEnabledEvent(self: ClientFtueManager): RBXScriptSignal
	return self.event.Event
end


function ClientFtueManager.notifyGemsValueChange(self: ClientFtueManager, primaryElement: any, prevValue: any, value: any)
	if not self:isFtueActive() then
		return
	end

	local stepData = FtueSteps.getStepDataForStepName(self.ftueProgress.stepName) :: any
	self:updateFtueMessage(stepData)
end

function ClientFtueManager.notifyBuySuccessful(self: ClientFtueManager)
	if not self:isFtueActive() then
		return
	end

	local stepData = FtueSteps.getStepDataForStepName(self.ftueProgress.stepName) :: any
	self:updateBuyItemMessage(stepData)
end

function ClientFtueManager.init(self: ClientFtueManager)

end

function ClientFtueManager.new(): ClientFtueManager
	local self = setmetatable({} :: ClientFtueManagerFields, ClientFtueManager)

	self.ftueProgress = {}

	self.trackMoveToLocation = nil

	self.event = Instance.new("BindableEvent")


	return self
end


function ClientFtueManager.initClass(deps: any)
	clientBuyStore = deps.clientBuyStore
end

local singleton = ClientFtueManager.new()

return singleton
