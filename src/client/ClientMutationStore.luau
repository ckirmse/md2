--!strict

local ClientMutationStore = {}
ClientMutationStore.__index = ClientMutationStore

local marketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
-- the store/effect templates' shapes only exist in Studio, so they are untyped here
local MutationStore: any = MainElements:WaitForChild("MutationStore")
local ParticleEffects = GameAssets:WaitForChild("ParticleEffects")
local MutationCreatedParent: any = ParticleEffects:WaitForChild("MutationCreatedParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientNewMutationItemManager = require("./ClientNewMutationItemManager")
local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local screenGuiManager = require("./ScreenGuiManager")
local Types = require("./Types")
local clientFtueManager = require("./ClientFtueManager")

local GREETING_DISTANCE = 10
local DISCOUNT_SIGN_ORBIT_RADIUS = 22
local DISCOUNT_SIGN_ORBIT_PERIOD = 14

local BALLOON1_PERIOD = 11
local BALLOON2_PERIOD = 7

local MUTATION_CLOUD_DURATION_SEC = 4

local PROMPT_NAME = "MutationStorePrompt"

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("MutationGacha")

local runService = game:GetService("RunService")

type RobuxProductInfo = {
	robuxPrice: number,
}

type ClientMutationStoreFields = {
	connections: { RBXScriptConnection },
	discountAvailableTime: number,
	mutationStoreDataFolder: any?,
	robuxProductInfo: { [number]: RobuxProductInfo },
	latestName: string?,
	mutationStore: any?,
	audioButtonParent: any?,
	proximityThresholdTracker: ProximityThresholdTracker.ProximityThresholdTracker?,
}

export type ClientMutationStore = typeof(setmetatable({} :: ClientMutationStoreFields, ClientMutationStore))

local function setMutationText(textLabel: any, mutationName: string, mutation: number, percent: number)
	textLabel.RichText = true
	textLabel.Text = utils.getColoredTextForMutation(
		string.format("%s %g%%", mutationName, percent),
		mutation
	)
end

local function populateMutationRates(container: any, inst: any)
	for _, mutation in enums.getAllValues(enums.Mutations) do
		local mutationName = enums.getPublicName(enums.Mutations, mutation)
		if not mutationName then
			continue
		end
		local frame = container:FindFirstChild(mutationName)
		if not frame then
			continue
		end
		local textLabel = frame:FindFirstChild("TextLabel")
		if not textLabel then
			continue
		end
		setMutationText(textLabel, mutationName, mutation, 100 * inst:GetAttribute(mutationName))
	end
end

function ClientMutationStore.getGuiRoot(self: ClientMutationStore): Instance
	return GuiRoot
end

function ClientMutationStore.notifyForceEnd(self: ClientMutationStore)
	self:cleanupDialog()
end

function ClientMutationStore.notifyClickOutside(self: ClientMutationStore)
	self:notifyForceEnd()
end

function ClientMutationStore.getHudElements(self: ClientMutationStore): { number }
	return {}
end

function ClientMutationStore.showPurchaseAnimation(self: ClientMutationStore, text: any, templatePath: any, mutation: any, mutationSurfaceAppearanceName: any, cameraPosition: any)
	local name = self.latestName
	if not name then
		name = "Large"
	end

	local tubeInst: any
	for _, storeItem in (self.mutationStoreDataFolder :: any):GetChildren() do
		if not storeItem:IsA("Part") then
			continue
		end
		if storeItem.Name ~= name then
			continue
		end

		local instanceName = storeItem:GetAttribute(Attributes.INSTANCE_NAME)

		tubeInst = utils.findFirstDescendant(self.mutationStore :: any, instanceName)
	end

	if not tubeInst then
		warn("couldn't find tube for", name)
		return
	end

	-- first we show the mutation animation

	local destCFrame = tubeInst:GetPivot()

	local mutationCreatedParent = MutationCreatedParent:Clone()
	mutationCreatedParent.CFrame = destCFrame
	mutationCreatedParent.Anchored = true
	mutationCreatedParent.Parent = workspace
	utils.safelyDisposeOfParticleParent(mutationCreatedParent, MUTATION_CLOUD_DURATION_SEC,
		function()
			-- particle effect done, so we show the 2d overlay
			clientNewMutationItemManager:notifyNewMutationItem(text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition)
		end
	)
end

function ClientMutationStore.beginDialog(self: ClientMutationStore, name: string)
	-- so when we're told we bought something (which comes down at any time, thanks to how robux purchases work on server)
	-- we'll animate based on this name
	self.latestName = name

	for _, prompt in utils.getAllDescendantsByName(self.mutationStore :: any, PROMPT_NAME) :: { any } do
		prompt.Enabled = false
	end

	local Main = GuiRoot:WaitForChild("Main")

	for _, storeItem in (self.mutationStoreDataFolder :: any):GetChildren() do
		if not storeItem:IsA("Part") then
			continue
		end
		Main:FindFirstChild(storeItem:GetAttribute(Attributes.HEADER_NAME)).Visible = (storeItem.Name == name)
	end

	local inst: any = (self.mutationStoreDataFolder :: any):FindFirstChild(name)

	local buyButton = Main:FindFirstChild("BuyButton")
	local buyDiscountButton = Main:FindFirstChild("BuyDiscount")

	if workspace:GetServerTimeNow() >= self.discountAvailableTime then
		buyButton.Visible = false
		local discountProductId = inst:GetAttribute(Attributes.DISCOUNT_PRODUCT_ID)
		local regularProductId = inst:GetAttribute(Attributes.PRODUCT_ID)
		if self.robuxProductInfo[discountProductId] and self.robuxProductInfo[regularProductId] then
			buyDiscountButton:FindFirstChild("Price").Text = tostring(self.robuxProductInfo[discountProductId].robuxPrice)
			buyDiscountButton:FindFirstChild("Slashed").Text = tostring(self.robuxProductInfo[regularProductId].robuxPrice)
			local discountConnection: RBXScriptConnection = buyDiscountButton.Activated:Connect(
				function()
					(self.audioButtonParent :: any):FindFirstChild("AudioVanityPurchaseButton"):Play()
					local isSuccess, errorMessage = pcall(
						function()
							marketplaceService:PromptProductPurchase(player, discountProductId)
						end
					)
					if isSuccess then
						self:cleanupDialog()
					else
						warn("error prompting for mutation store discount purchase", errorMessage)
					end
				end
			)
			table.insert(self.connections, discountConnection)
			buyDiscountButton.Visible = true
		else
			buyDiscountButton.Visible = false
		end
	else
		buyDiscountButton.Visible = false
		local regularProductId = inst:GetAttribute(Attributes.PRODUCT_ID)
		if self.robuxProductInfo[regularProductId] then
			buyButton:FindFirstChild("Price").Text = tostring(self.robuxProductInfo[regularProductId].robuxPrice)
			local buyConnection: RBXScriptConnection = buyButton.Activated:Connect(
				function()
					(self.audioButtonParent :: any):FindFirstChild("AudioVanityPurchaseButton"):Play()
					local isSuccess, errorMessage = pcall(
						function()
							marketplaceService:PromptProductPurchase(player, regularProductId)
						end
					)
					if isSuccess then
						self:cleanupDialog()
					else
						warn("error prompting for mutation store purchase", errorMessage)
					end
				end
			)
			table.insert(self.connections, buyConnection)
			buyButton.Visible = true
		else
			buyButton.Visible = false
		end
	end
	populateMutationRates(Main:FindFirstChild("Rates"), inst)

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientMutationStore.cleanupDialog(self: ClientMutationStore)
	GuiRoot.Enabled = false

	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}

	for _, prompt in utils.getAllDescendantsByName(self.mutationStore :: any, PROMPT_NAME) :: { any } do
		prompt.Enabled = true
	end

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientMutationStore.initWorldInterface(self: ClientMutationStore)
	local mutationStore = MutationStore:Clone()
	mutationStore.Parent = workspace

	self.mutationStore = mutationStore

	local Main = GuiRoot:WaitForChild("Main")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local mutationStoreDataFolder = splendidDataFolder:WaitForChild("MutationStore")
	self.mutationStoreDataFolder = mutationStoreDataFolder

	self.discountAvailableTime = (mutationStoreDataFolder:GetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME) :: number?) or 0
	mutationStoreDataFolder:GetAttributeChangedSignal(Attributes.DISCOUNT_AVAILABLE_TIME):Connect(
		function()
			self.discountAvailableTime = (mutationStoreDataFolder:GetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME) :: number?) or 0
		end
	)

	local random = Random.new()

	for _, storeItem in mutationStoreDataFolder:GetChildren() :: { any } do
		if not storeItem:IsA("Part") then
			continue
		end
		local itemName = storeItem.Name
		local instanceName = storeItem:GetAttribute(Attributes.INSTANCE_NAME)
		local headerName = storeItem:GetAttribute(Attributes.HEADER_NAME)

		local tubeInst: any = utils.findFirstDescendant(self.mutationStore :: any, instanceName)
		local floaters = tubeInst:FindFirstChild("Floaters")
		if floaters:IsA("Folder") then
			local children = floaters:GetChildren()
			local index = Random.new():NextInteger(1, #children)
			local elapsedTime = random:NextNumber(0, 20) -- just to randomize stuff
			local switchSec = 10

			for i, child in children do
				local baseCFrame = child:GetPivot()
				local amplitude = 1
				local period = 10 + random:NextNumber(0, 5)
				runService.PostSimulation:Connect(
					function(deltaTime: number)
						local prevElapsedTime = elapsedTime
						elapsedTime += deltaTime
						if (elapsedTime // switchSec) ~= (prevElapsedTime // switchSec) then
							index = (index + 1) % #children
						end

						--utils.setPropertyTreeBaseParts(child, "Transparency", 0)

						child:PivotTo(baseCFrame + Vector3.new(0, math.sin(2 * math.pi * elapsedTime/ period) * amplitude))
					end
				)
			end
		end

		local objProximityPrompt = Instance.new("ProximityPrompt")
		objProximityPrompt.Name = PROMPT_NAME
		objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
		objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		objProximityPrompt.RequiresLineOfSight = true
		objProximityPrompt.UIOffset = Vector2.new(0, 0)
		objProximityPrompt.ActionText = "View Offer"
		objProximityPrompt.Parent = tubeInst

		objProximityPrompt.Triggered:Connect(
			function()
				if clientFtueManager:isFtueActive() then
					screenGuiManager:showSystemMessage("You cannot buy mutated items yet")
					return
				end

				self:beginDialog(itemName)
			end
		)

		Main:WaitForChild(headerName):WaitForChild("ExitButton").Activated:Connect(
			function()
				(self.audioButtonParent :: any):FindFirstChild("AudioClick"):Play()
				self:cleanupDialog()
			end
		)

		local surfaceGuis = utils.getAllDescendantsByName(tubeInst:FindFirstChild("CTA_Frame"), "SurfaceGui") :: { any }
		for _, surfaceGui in surfaceGuis do
			for _, mutation in enums.getAllValues(enums.Mutations) do
				local mutationName = enums.getPublicName(enums.Mutations, mutation)
				if not mutationName then
					continue
				end
				local textLabel = utils.findFirstDescendant(surfaceGui, mutationName)
				if not textLabel then
					continue
				end
				setMutationText(textLabel, mutationName, mutation, 100 * (storeItem:GetAttribute(mutationName) :: number))
			end
		end
	end

	self.audioButtonParent = utils.findFirstDescendant(self.mutationStore :: any, "AudioButtonParent")

	local tubeRobuxLarge: any = utils.findFirstDescendant(self.mutationStore :: any, "TubeRobuxLarge")
	local tubeCenter = tubeRobuxLarge:GetPivot().Position :: Vector3

	local proximityThresholdTracker = ProximityThresholdTracker.new(tubeCenter, GREETING_DISTANCE)
	self.proximityThresholdTracker = proximityThresholdTracker

	proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			if not GuiRoot.Enabled then
				return
			end

			self:cleanupDialog()
		end
	)

	local discountSign: any = (self.mutationStore :: any):FindFirstChild("DiscountSign")
	local discountSignBaseCFrame = discountSign:GetPivot()
	local discountSignOrbitBase = CFrame.new(Vector3.new(DISCOUNT_SIGN_ORBIT_RADIUS, 0, 0))

	local discountFrame = discountSign:FindFirstChild("DiscountFrame")
	local discountTextLabels: { any } = {}
	for _, textPart in utils.getAllDescendantsByName(discountFrame, "Text") :: { any } do
		local surfaceGui = textPart:FindFirstChild("SurfaceGui")
		if surfaceGui then
			local textLabel = surfaceGui:FindFirstChild("TextLabel")
			if textLabel then
				table.insert(discountTextLabels, textLabel)
			end
		end
	end
	local lastDiscountDisplaySeconds = -1

	local headerSign: any = (self.mutationStore :: any):FindFirstChild("HeaderSign")
	local balloon1 = headerSign:FindFirstChild("Balloon01")
	local balloon2 = headerSign:FindFirstChild("Balloon02")

	local balloon1BaseCFrame = balloon1.CFrame
	local balloon2BaseCFrame = balloon2.CFrame

	local totalTime = 0
	runService.PostSimulation:Connect(
		function(deltaTime: number)
			totalTime += deltaTime
			local balloon1Diff = math.sin(2 * math.pi * totalTime / BALLOON1_PERIOD)
			local balloon2Diff = math.sin(2 * math.pi * totalTime / BALLOON2_PERIOD)

			balloon1:PivotTo(balloon1BaseCFrame.Rotation + (balloon1BaseCFrame.Position + Vector3.new(0, balloon1Diff, 0)))
			balloon2:PivotTo(balloon2BaseCFrame.Rotation + (balloon2BaseCFrame.Position + Vector3.new(0, balloon2Diff, 0)))

			local discountAngle = 2 * math.pi * totalTime / DISCOUNT_SIGN_ORBIT_PERIOD
			local orbitOffset = (CFrame.fromEulerAnglesXYZ(0, discountAngle, 0) * discountSignOrbitBase).Position
			local discountPos = Vector3.new(tubeCenter.X + orbitOffset.X, discountSignBaseCFrame.Position.Y, tubeCenter.Z + orbitOffset.Z)
			discountSign:PivotTo(discountSignBaseCFrame.Rotation + discountPos)

			local availableTime = self.discountAvailableTime
			local isAvailableNow = workspace:GetServerTimeNow() >= availableTime
			local discountText: string?
			if isAvailableNow then
				discountText = "FIRST PURCHASE DISCOUNT AVAILABLE"
			else
				local remainingSeconds = math.floor(availableTime - workspace:GetServerTimeNow())
				if remainingSeconds ~= lastDiscountDisplaySeconds then
					lastDiscountDisplaySeconds = remainingSeconds
					local hours = math.floor(remainingSeconds / 3600)
					local minutes = math.floor((remainingSeconds % 3600) / 60)
					discountText = string.format("FIRST PURCHASE DISCOUNT AVAILABLE IN %02i:%02i", hours, minutes)
				end
			end
			if discountText then
				for _, textLabel in discountTextLabels do
					textLabel.Text = discountText
				end
			end
		end
	)
end

function ClientMutationStore.queryRobuxProductInfo(self: ClientMutationStore)
	for _, storeItem in (self.mutationStoreDataFolder :: any):GetChildren() do
		if not storeItem:IsA("Part") then
			continue
		end

		local regularProductId = storeItem:GetAttribute(Attributes.PRODUCT_ID)
		local discountProductId = storeItem:GetAttribute(Attributes.DISCOUNT_PRODUCT_ID)

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(regularProductId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess and productInfo.IsForSale then
					self.robuxProductInfo[regularProductId] = { robuxPrice = productInfo.PriceInRobux :: number }
				end
			end
		)

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(discountProductId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess and productInfo.IsForSale then
					self.robuxProductInfo[discountProductId] = { robuxPrice = productInfo.PriceInRobux :: number }
				end
			end
		)
	end
end

function ClientMutationStore.notifyMutationStorePurchase(self: ClientMutationStore, text: any, templatePath: any, mutation: any, mutationSurfaceAppearanceName: any, cameraPosition: any)
	self:showPurchaseAnimation(text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition)
end

function ClientMutationStore.init(self: ClientMutationStore)
	self:initWorldInterface()

	task.spawn(
		function()
			self:queryRobuxProductInfo()
		end
	)
end

function ClientMutationStore.new(): ClientMutationStore
	local self = setmetatable({} :: ClientMutationStoreFields, ClientMutationStore)

	self.connections = {}
	self.discountAvailableTime = 0
	self.robuxProductInfo = {}

	return self
end

local singleton = ClientMutationStore.new()

return singleton
