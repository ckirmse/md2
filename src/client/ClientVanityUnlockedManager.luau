--!strict

local ClientVanityUnlockedManager = {}
ClientVanityUnlockedManager.__index = ClientVanityUnlockedManager

local collectionService = game:GetService("CollectionService")
local marketplaceService = game:GetService("MarketplaceService")
local tweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
-- the effect template's shape only exists in Studio, so it is untyped here
local VanityUnlockParent: any = ParticleEffects:WaitForChild("VanityUnlockParent")
local UX = GameAssets:WaitForChild("UX")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local cameraManager = require("./CameraManager")
local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local teleporters = require("./Teleporters")
local Types = require("./Types")
local clientVanityExpansionsManager: Types.ClientVanityExpansionsManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientVanityFencesManager: Types.ClientVanityFencesManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientVanityPlotsManager: Types.ClientVanityPlotsManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local GREETING_DISTANCE = 10
local GNOME_UP_DIFF_Y = 0
local GNOME_DOWN_DIFF_Y = -3

local UNLOCK_AREA_ANIMATION_SEC = 2

local PROMPT_NAME = "VanityUnlockedProxPrompt"

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("VanityMainTabs")

type IndicatorData = {
	instance: any, -- world gnome instance; its shape only exists at runtime
	prompt: ProximityPrompt?,
	proximityThresholdTracker: ProximityThresholdTracker.ProximityThresholdTracker?,
}

type BeamData = {
	beam: any, -- FtueBeam clone
	attachment1: Attachment,
	attachment2: Attachment,
	beamAnchor: BasePart?,
}

type RobuxProductInfo = {
	robuxPrice: number,
}

type ClientVanityUnlockedManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	connections: { RBXScriptConnection },
	robuxProductInfo: { [number]: RobuxProductInfo },
	beamData: BeamData?,
	dialogObjectId: number?,
	shouldRestoreCameraInCleanup: boolean?,
	baseCameraType: Enum.CameraType?,
}

export type ClientVanityUnlockedManager = typeof(setmetatable({} :: ClientVanityUnlockedManagerFields, ClientVanityUnlockedManager))

function ClientVanityUnlockedManager.getGuiRoot(self: ClientVanityUnlockedManager): Instance
	return GuiRoot
end

function ClientVanityUnlockedManager.notifyForceEnd(self: ClientVanityUnlockedManager)
	self:cleanupDialog()
end

function ClientVanityUnlockedManager.notifyClickOutside(self: ClientVanityUnlockedManager)
	self:notifyForceEnd()
end

function ClientVanityUnlockedManager.doZoomCamera(self: ClientVanityUnlockedManager): boolean
	return false
end

function ClientVanityUnlockedManager.getHudElements(self: ClientVanityUnlockedManager): { number }
	return {enums.HudElements.COINS}
end

function ClientVanityUnlockedManager.beginDialog(self: ClientVanityUnlockedManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	if self.dialogObjectId then
		return
	end

	self:destroyBeam()

	local prompt = indicatorData.prompt
	if prompt then
		prompt.Enabled = false
	end

	self.dialogObjectId = objectId

	self:updateMenuInterface()

	self.shouldRestoreCameraInCleanup = true

	cameraManager:pushState()

	-- prevent user from controlling camera
	local camera = workspace.CurrentCamera
	self.baseCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable

	-- move camera where we want

	local cameraDestCFrame = ((teleporters:getPlotCFrame() :: CFrame) + Vector3.new(0, 50, 0)) * CFrame.Angles(math.rad(-25), 0, 0)
	local duration = 1
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	local tween = PivotToTween(camera, tweenInfo, cameraDestCFrame)
	tween.Completed:Once(
		function()
			GuiRoot.Enabled = true

			overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

			local gnome: any = utils.findFirstDescendant(workspace, "Gnome")
			local audioOpenMainTabs = gnome:FindFirstChild("AudioOpenMainTabs")
			audioOpenMainTabs:Play()
		end
	)

	tween:Play()
end

function ClientVanityUnlockedManager.notifyVanityDialogClosed(self: ClientVanityUnlockedManager)
	local objectId, indicatorData = next(self.indicatorMap)
	if objectId == nil or indicatorData == nil then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt.Enabled = false
	end

	self.dialogObjectId = objectId

	self:updateMenuInterface()

	self.shouldRestoreCameraInCleanup = true

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityUnlockedManager.cleanupDialog(self: ClientVanityUnlockedManager)
	GuiRoot.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if self.shouldRestoreCameraInCleanup then
		cameraManager:popState()
	end

	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}

	local objectId = self.dialogObjectId
	if not objectId then
		return
	end

	self.dialogObjectId = nil

	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt.Enabled = true
	end
end

function ClientVanityUnlockedManager.tryBuyWithRobux(self: ClientVanityUnlockedManager, productId: number)
	local isSuccess, errorMessage = pcall(
		function()
			marketplaceService:PromptProductPurchase(player, productId)
		end
	)

	if isSuccess then
		--print("yes prompted")
	else
		warn("error prompting for robux purchase", errorMessage)
	end
end

function ClientVanityUnlockedManager.updateMenuInterface(self: ClientVanityUnlockedManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Tabs = Main:FindFirstChild("Tabs")
	local MainPlotButton = Tabs:FindFirstChild("MainPlotButton")
	MainPlotButton:FindFirstChild("NewCTA").Visible = false

	for _, inst in (Tabs :: any):GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
		if string.match(inst.Name, "Template$") then
			inst.Visible = false
		end
	end
	local ExpansionLockedTemplate = Tabs:FindFirstChild("ExpansionLockedTemplate")
	local ExpansionUnlockedButtonTemplate = Tabs:FindFirstChild("ExpansionUnlockedButtonTemplate")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")

	local vanityAreasDataFolder: any = vanityDataFolder:FindFirstChild(Constants.VANITY_AREAS_NAME)

	local layoutOrder = 3

	for _, vanityArea in enums.getAllValues(enums.VanityAreas) do
		if vanityArea == enums.VanityAreas.MAIN_PLOT then
			continue
		end
		if vanityArea == enums.VanityAreas.MAIN_PLOT_FENCE then
			continue
		end

		local vanityAreaName = enums.getName(enums.VanityAreas, vanityArea)
		local inst: any = vanityAreasDataFolder:FindFirstChild(vanityAreaName)
		if not inst then
			continue
		end

		local vanityAreaState = inst:GetAttribute(Attributes.VANITY_AREA_STATE)
		if vanityAreaState == enums.VanityAreaState.LOCKED then
			local coins = inst:GetAttribute(Attributes.COINS)
			local productId = inst:GetAttribute(Attributes.PRODUCT_ID)
			local capacityStr = inst:GetAttribute(Attributes.CAPACITY_STR) or ""

			local expansionLocked = ExpansionLockedTemplate:Clone()
			expansionLocked:FindFirstChild("Benefit").Text = capacityStr
			expansionLocked:FindFirstChild("TextLabel").Text = enums.getPublicName(enums.VanityAreas, vanityArea)
			local purchaseList = expansionLocked:FindFirstChild("PurchaseList")
			local buyButton = purchaseList:FindFirstChild("BuyButton")
			if coins then
				buyButton:FindFirstChild("Price").Text = utils.formatLargeInteger(coins)
				local buyConnection: RBXScriptConnection = buyButton.Activated:Connect(
					function()
						RemoteEvents.TryBuyVanityArea:FireServer(vanityArea)
					end
				)
				table.insert(self.connections, buyConnection)
			else
				buyButton.Visible = false
			end

			local buyRobuxButton = purchaseList:FindFirstChild("BuyRobuxButton")
			local robuxPrice: number?
			if productId and self.robuxProductInfo[productId] then
				robuxPrice = self.robuxProductInfo[productId].robuxPrice
			end

			if robuxPrice then
				buyRobuxButton:FindFirstChild("Price").Text = tostring(robuxPrice)
				local buyRobuxConnection: RBXScriptConnection = buyRobuxButton.Activated:Connect(
					function()
						self:tryBuyWithRobux(productId)
					end
				)
				table.insert(self.connections, buyRobuxConnection)
			else
				buyRobuxButton.Visible = false
			end

			expansionLocked.LayoutOrder = layoutOrder
			layoutOrder += 1

			expansionLocked.Visible = true
			expansionLocked.Parent = Tabs
		elseif vanityAreaState == enums.VanityAreaState.UNLOCKED then
			local expansionUnlockedButton = ExpansionUnlockedButtonTemplate:Clone()
			expansionUnlockedButton:FindFirstChild("NewCTA").Visible = false
			expansionUnlockedButton:FindFirstChild("TextLabel").Text = enums.getPublicName(enums.VanityAreas, vanityArea)
			local unlockedConnection: RBXScriptConnection = expansionUnlockedButton.Activated:Connect(
				function()
					self.shouldRestoreCameraInCleanup = false

					self:cleanupDialog()

					clientVanityExpansionsManager:beginDialog(vanityArea)
				end
			)
			table.insert(self.connections, unlockedConnection)

			expansionUnlockedButton.LayoutOrder = layoutOrder
			layoutOrder += 1

			expansionUnlockedButton.Visible = true
			expansionUnlockedButton.Parent = Tabs
		else
			warn("unknown vanity area state", inst, vanityAreaState)
			continue
		end

	end

end


function ClientVanityUnlockedManager.removeIndicators(self: ClientVanityUnlockedManager, objectId: number)
	local indicatorData = self.indicatorMap[objectId]
	if not indicatorData then
		return
	end

	local prompt = indicatorData.prompt
	if prompt then
		prompt:Destroy()
		indicatorData.prompt = nil
	end

	local proximityThresholdTracker = indicatorData.proximityThresholdTracker
	if proximityThresholdTracker then
		proximityThresholdTracker:destroy()
		indicatorData.proximityThresholdTracker = nil
	end

	self.indicatorMap[objectId] = nil
end


-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientVanityUnlockedManager.notifyNewInstance(self: ClientVanityUnlockedManager, inst: any)
	-- we track modifications of all vanity gnome unlocked

	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	if self.indicatorMap[objectId] then
		print("already have vanity gnome unlocked", inst, objectId)
		return
	end

	local indicatorData: IndicatorData = {
		instance = inst,
	}
	self.indicatorMap[objectId] = indicatorData

	if inst:GetAttribute(Attributes.USER_ID) ~= player.UserId then
		--print("someone else's vanity gnome locked was made", inst, inst:GetAttribute(Attributes.USER_ID))
		return
	end

	local objProximityPrompt = Instance.new("ProximityPrompt")
	objProximityPrompt.Name = PROMPT_NAME
	objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
	objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	objProximityPrompt.RequiresLineOfSight = false
	objProximityPrompt.UIOffset = Vector2.new(0, 15)
	objProximityPrompt.ActionText = "Customize"
	objProximityPrompt.HoldDuration = 0
	objProximityPrompt.Triggered:Connect(
		function(_player)
			--print("opening vanity top level menu", inst)
			self:beginDialog(objectId)
		end
	)

	objProximityPrompt.Parent = inst

	local proximityThresholdTracker = ProximityThresholdTracker.new(inst:GetPivot().Position, GREETING_DISTANCE)
	indicatorData.proximityThresholdTracker = proximityThresholdTracker

	local gnome = inst:FindFirstChild("Gnome")
	local gnomeBaseY = gnome:GetPivot().Position.Y
	local gnomeUpPosition = Vector3.new(gnome.Position.X, gnomeBaseY + GNOME_UP_DIFF_Y, gnome.Position.Z)
	local gnomeDownPosition = Vector3.new(gnome.Position.X, gnomeBaseY + GNOME_DOWN_DIFF_Y, gnome.Position.Z)

	if proximityThresholdTracker:isInProximity() then
		gnome.Position = gnomeUpPosition
	else
		gnome.Position = gnomeDownPosition
	end


	proximityThresholdTracker:getEnterEvent():Connect(
		function()
			tweenService:Create(gnome, TweenInfo.new(0.5), {Position = gnomeUpPosition}):Play()

			local audioGnome = gnome:FindFirstChild("AudioGnome")
			audioGnome:Play()
		end
	)

	proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			tweenService:Create(gnome, TweenInfo.new(0.5), {Position = gnomeDownPosition}):Play()

			if not GuiRoot.Enabled then
				return
			end

			self:cleanupDialog()
		end
	)

	indicatorData.prompt = objProximityPrompt
end

function ClientVanityUnlockedManager.notifyRemoveInstance(self: ClientVanityUnlockedManager, inst: any)
	local objectId = inst:GetAttribute(Attributes.OBJECT_ID)

	self:removeIndicators(objectId)
end

function ClientVanityUnlockedManager.getMapSize(self: ClientVanityUnlockedManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientVanityUnlockedManager.queryRobuxProductInfo(self: ClientVanityUnlockedManager)
	--print("querying robux product info")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")

	local vanityAreasDataFolder: any = vanityDataFolder:FindFirstChild(Constants.VANITY_AREAS_NAME)

	for _, inst in vanityAreasDataFolder:GetChildren() do
		local productId = inst:GetAttribute(Attributes.PRODUCT_ID)
		if not productId then
			continue
		end

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						self.robuxProductInfo[productId] = {
							robuxPrice = productInfo.PriceInRobux :: number
						}
					else
						print("product not for robux sale", productId, productInfo)
					end
				end
			end
		)
	end

	--print("querying robux product info kicked off")
end


function ClientVanityUnlockedManager.notifyItemEquipped(self: ClientVanityUnlockedManager, itemId: number)
	local obj: any = utils.tryGetObjByPlayerAndItemId(player, itemId)
	if not obj then
		return
	end

	if not collectionService:HasTag(obj, Tags.BLUEPRINT) then
		return
	end

	if self.beamData then
		return
	end

	local vanityComponentName = obj:GetAttribute(Attributes.VANITY_COMPONENT_NAME)

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")

	local vanityComponentInst = utils.findFirstDescendant(vanityDataFolder, vanityComponentName)

	if not vanityComponentInst then
		return
	end

	if not vanityComponentInst:GetAttribute(Attributes.UNLOCKABLE) then
		return
	end

	print("can unlock", vanityComponentName)

	local gnome = utils.findFirstDescendant(workspace, "Gnome")
	if not gnome then
		return
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "VanityBeamAttachment1"
	attachment1.Parent = humanoidRootPart

	local beamAnchor = Instance.new("Part")
	beamAnchor.Name = "VanityBeamAnchor"
	beamAnchor.Anchored = true
	beamAnchor.CanCollide = false
	beamAnchor.CanQuery = false
	beamAnchor.CanTouch = false
	beamAnchor.Transparency = 1
	beamAnchor:PivotTo((gnome :: any):GetPivot())
	beamAnchor.Parent = workspace

	local attachment2 = Instance.new("Attachment")
	attachment2.Name = "VanityBeamAttachment2"
	attachment2.Parent = beamAnchor

	local beam: any = (UX:WaitForChild("FtueBeam") :: any):Clone()
	beam.Attachment0 = attachment1
	beam.Attachment1 = attachment2
	beam.Parent = workspace

	local beamData: BeamData = {
		beam = beam,
		attachment1 = attachment1,
		attachment2 = attachment2,
		beamAnchor = beamAnchor,
	}
	self.beamData = beamData
end

function ClientVanityUnlockedManager.destroyBeam(self: ClientVanityUnlockedManager)
	local beamData = self.beamData
	if not beamData then
		return
	end

	beamData.beam:Destroy()
	beamData.attachment1:Destroy()
	beamData.attachment2:Destroy()
	if beamData.beamAnchor then
		beamData.beamAnchor:Destroy()
	end
	self.beamData = nil
end

function ClientVanityUnlockedManager.notifyItemUnequipped(self: ClientVanityUnlockedManager)
	self:destroyBeam()
end

function ClientVanityUnlockedManager.init(self: ClientVanityUnlockedManager)

	collectionService:GetInstanceAddedSignal(Tags.VANITY_GNOME_UNLOCKED):Connect(
		function(inst)
			--print("new vanity gnome unlocked exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.VANITY_GNOME_UNLOCKED):Connect(
		function(inst)
			--print("vanity gnome unlocked is gone", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.VANITY_GNOME_UNLOCKED) do
		--print("existing vanity gnome unlocked exists", inst)
		self:notifyNewInstance(inst)
	end

	local Main = GuiRoot:FindFirstChild("Main")
	local Tabs = Main:FindFirstChild("Tabs")
	local MainPlotButton = Tabs:FindFirstChild("MainPlotButton")
	MainPlotButton:FindFirstChild("NewCTA").Visible = false
	MainPlotButton.Activated:Connect(
		function()
			self.shouldRestoreCameraInCleanup = false

			--print("main plot")
			self:cleanupDialog()

			-- open main vanity
			clientVanityPlotsManager:beginDialog()
		end
	)
	local FencesButton = Tabs:FindFirstChild("FencesButton")
	FencesButton:FindFirstChild("NewCTA").Visible = false
	FencesButton.Activated:Connect(
		function()
			self.shouldRestoreCameraInCleanup = false

			--print("fences")
			self:cleanupDialog()

			-- open fences vanity
			clientVanityFencesManager:beginDialog()
		end
	)
	local exitButton: any = utils.findFirstDescendant(GuiRoot, "ExitButton")
	exitButton.Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")

	local vanityAreasDataFolder = vanityDataFolder:WaitForChild(Constants.VANITY_AREAS_NAME)
	for _, inst in vanityAreasDataFolder:GetChildren() do
		inst.AttributeChanged:Connect(
			function(attributeName)
				--print("attribute changed", inst, attributeName)

				if attributeName == Attributes.VANITY_AREA_STATE and inst:GetAttribute(Attributes.VANITY_AREA_STATE) == enums.VanityAreaState.UNLOCKED then
					--print("vanity area (expansion) just unlocked, we will celebrate it")
					local vanityDecorateName = inst:GetAttribute(Attributes.VANITY_DECORATE_NAME) :: string
					local plotIndex = teleporters:getPlotIndex()
					local decorateInst: any = utils.findFirstDescendantWithNameAndAttribute(workspace, vanityDecorateName, Attributes.INDEX, plotIndex)
					--print("have decorateInst", decorateInst)
					if decorateInst then
						local highlight = Instance.new("Highlight")
						highlight.DepthMode = Enum.HighlightDepthMode.Occluded
						highlight.FillColor = Color3.fromRGB(255, 255, 255)
						highlight.FillTransparency = 0
						highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
						highlight.OutlineTransparency = 1
						highlight.Parent = decorateInst
						tweenService:Create(highlight, TweenInfo.new(UNLOCK_AREA_ANIMATION_SEC, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1}):Play()

						local vanityUnlockParent = VanityUnlockParent:Clone()
						vanityUnlockParent:PivotTo(decorateInst:GetPivot())
						vanityUnlockParent.Parent = workspace

						local burst = vanityUnlockParent:FindFirstChild("Burst")
						burst:Emit(250)

						utils.safelyDisposeOfParticleParent(vanityUnlockParent, UNLOCK_AREA_ANIMATION_SEC,
							function()
								highlight:Destroy()
							end
						)
					end
				end

				if not GuiRoot.Enabled then
					return
				end

				self:updateMenuInterface()
			end
		)
	end

	self:queryRobuxProductInfo()
end

function ClientVanityUnlockedManager.new(): ClientVanityUnlockedManager
	local self = setmetatable({} :: ClientVanityUnlockedManagerFields, ClientVanityUnlockedManager)

	self.indicatorMap = {}

	self.connections = {}

	self.robuxProductInfo = {}

	self.beamData = nil

	return self
end

function ClientVanityUnlockedManager.initClass(deps: any)
	clientVanityExpansionsManager = deps.clientVanityExpansionsManager
	clientVanityFencesManager = deps.clientVanityFencesManager
	clientVanityPlotsManager = deps.clientVanityPlotsManager
end


local singleton = ClientVanityUnlockedManager.new()

return singleton
