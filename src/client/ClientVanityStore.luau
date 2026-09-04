--!strict

local ClientVanityStore = {}
ClientVanityStore.__index = ClientVanityStore

local marketplaceService = game:GetService("MarketplaceService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
-- the store template's shape only exists in Studio, so it is untyped here
local VanityStore: any = MainElements:WaitForChild("VanityStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local screenGuiManager = require("./ScreenGuiManager")
local Types = require("./Types")
local clientFtueManager = require("./ClientFtueManager")

local GREETING_DISTANCE = 10
local DISCOUNT_SIGN_ORBIT_RADIUS = 20
local DISCOUNT_SIGN_ORBIT_PERIOD = 15

local BALLOON1_PERIOD = 10
local BALLOON2_PERIOD = 8

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("VanityGacha")

type RobuxProductInfo = {
	robuxPrice: number,
}

type ClientVanityStoreFields = {
	vanityStore: any?, -- VanityStore clone
	audioButtonParent: any?,
	proximityThresholdTracker: ProximityThresholdTracker.ProximityThresholdTracker?,
	robuxProductInfo: { [number]: RobuxProductInfo },
	connections: { RBXScriptConnection },
	discountAvailableTime: number,
}

export type ClientVanityStore = typeof(setmetatable({} :: ClientVanityStoreFields, ClientVanityStore))

function ClientVanityStore.getGuiRoot(self: ClientVanityStore): Instance
	return GuiRoot
end

function ClientVanityStore.notifyForceEnd(self: ClientVanityStore)
	self:cleanupDialog()
end

function ClientVanityStore.notifyClickOutside(self: ClientVanityStore)
	self:notifyForceEnd()
end

function ClientVanityStore.getHudElements(self: ClientVanityStore): { number }
	return {}
end

function ClientVanityStore.beginDialog(self: ClientVanityStore, name: string)
	for _, prompt in (utils.getAllDescendantsByName(self.vanityStore :: any, "Prompt") :: { any }) do
		prompt.Enabled = false
	end

	local Main = GuiRoot:WaitForChild("Main")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityStoreDataFolder = splendidDataFolder:WaitForChild("VanityStore")

	for _, inst in vanityStoreDataFolder:GetChildren() :: { any } do
		Main:FindFirstChild(inst:GetAttribute(Attributes.HEADER_NAME)).Visible = (inst.Name == name)
	end

	local inst: any = vanityStoreDataFolder:FindFirstChild(name)

	for _, rarity in enums.getAllValues(enums.Rarity) do
		local rarityName = enums.getPublicName(enums.Rarity, rarity) :: string

		local textLabel = (utils.findFirstDescendant(Main, rarityName) :: any):FindFirstChild("TextLabel")
		textLabel.Text = string.format("%s %g%%", rarityName, 100 * (inst:GetAttribute(rarityName) :: number))
		textLabel.TextColor3 = utils.getColorForRarity(rarity)
	end

	local buyButton = Main:FindFirstChild("BuyButton")
	local buyDiscountButton = Main:FindFirstChild("BuyDiscountButton")

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
						warn("error prompting for discount robux purchase", errorMessage)
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
						warn("error prompting for robux purchase", errorMessage)
					end
				end
			)
			table.insert(self.connections, buyConnection)
			buyButton.Visible = true
		else
			buyButton.Visible = false
		end
	end

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityStore.cleanupDialog(self: ClientVanityStore)
	GuiRoot.Enabled = false

	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}

	for _, prompt in (utils.getAllDescendantsByName(self.vanityStore :: any, "Prompt") :: { any }) do
		prompt.Enabled = true
	end

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityStore.initWorldInterface(self: ClientVanityStore)
	local vanityStore = VanityStore:Clone()
	vanityStore.Parent = workspace

	self.vanityStore = vanityStore

	local Main = GuiRoot:WaitForChild("Main")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityStoreDataFolder = splendidDataFolder:WaitForChild("VanityStore")

	self.discountAvailableTime = (vanityStoreDataFolder:GetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME) :: number?) or 0
	vanityStoreDataFolder:GetAttributeChangedSignal(Attributes.DISCOUNT_AVAILABLE_TIME):Connect(
		function()
			self.discountAvailableTime = (vanityStoreDataFolder:GetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME) :: number?) or 0
		end
	)

	for _, inst in vanityStoreDataFolder:GetChildren() :: { any } do
		local name = inst.Name

		local instName = inst:GetAttribute(Attributes.INSTANCE_NAME)
		local headerName = inst:GetAttribute(Attributes.HEADER_NAME)

		local objProximityPrompt = Instance.new("ProximityPrompt")
		objProximityPrompt.Name = "Prompt"
		objProximityPrompt.Style = Enum.ProximityPromptStyle.Custom
		objProximityPrompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		objProximityPrompt.RequiresLineOfSight = true
		objProximityPrompt.UIOffset = Vector2.new(0, 0)
		objProximityPrompt.ActionText = "View Offer"

		local chestInst: any = utils.findFirstDescendant(self.vanityStore :: any, instName)
		objProximityPrompt.Parent = chestInst

		objProximityPrompt.Triggered:Connect(
			function(_player)
				--print("interacted, showing vanity store dialog box")

				if clientFtueManager:isFtueActive() then
					screenGuiManager:showSystemMessage("You cannot buy blueprints yet")
					return
				end

				self:beginDialog(name)
			end
		)

		Main:WaitForChild(headerName):WaitForChild("ExitButton").Activated:Connect(
			function()
				local audioClick = (self.audioButtonParent :: any):FindFirstChild("AudioClick")
				audioClick:Play()

				self:cleanupDialog()
			end
		)

		for _, rarity in enums.getAllValues(enums.Rarity) do
			local rarityName = enums.getPublicName(enums.Rarity, rarity) :: string

			local surfaceGuis = utils.getAllDescendantsByName(chestInst:FindFirstChild("CTA_Frame"), "SurfaceGui") :: { any }
			for _, surfaceGui in surfaceGuis do
				local textLabel = (utils.findFirstDescendant(surfaceGui, rarityName) :: any):FindFirstChild("TextLabel")
				textLabel.Text = string.format("%s %g%%", rarityName, 100 * (inst:GetAttribute(rarityName) :: number))
				textLabel.TextColor3 = utils.getColorForRarity(rarity)
			end
		end
	end

	local proximityThresholdTracker = ProximityThresholdTracker.new((self.vanityStore :: any):FindFirstChild("ChestRobuxLarge"):GetPivot().Position, GREETING_DISTANCE)
	self.proximityThresholdTracker = proximityThresholdTracker

	proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			if not GuiRoot.Enabled then
				return
			end

			self:cleanupDialog()
		end
	)

	-- move the balloons up and down so the sign dances around and orbit the discount sign around the large chest

	local discountSign: any = (self.vanityStore :: any):FindFirstChild("DiscountSign")
	local chestRobuxLarge: any = (self.vanityStore :: any):FindFirstChild("ChestRobuxLarge")
	local chestCenter = chestRobuxLarge:GetPivot().Position :: Vector3
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

	local headerSign: any = (self.vanityStore :: any):FindFirstChild("HeaderSign")
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
			local discountPos = Vector3.new(chestCenter.X + orbitOffset.X, discountSignBaseCFrame.Position.Y, chestCenter.Z + orbitOffset.Z)
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

	self.audioButtonParent = utils.findFirstDescendant(self.vanityStore :: any, "AudioButtonParent")
end

function ClientVanityStore.tryBuyWithRobux(self: ClientVanityStore, inventoryData: any)
	local isSuccess, errorMessage = pcall(
		function()
			marketplaceService:PromptProductPurchase(player, inventoryData.robuxProductId)
		end
	)

	if isSuccess then
		--print("yes prompted")
	else
		warn("error prompting for robux purchase", errorMessage)
	end

	-- as of 2026-august-11 the updateStoreInterface() call was removed: that method never
	-- existed on this store (copied from ClientBuyStore) and would have thrown if this
	-- method were ever called
end

function ClientVanityStore.queryRobuxProductInfo(self: ClientVanityStore)
	--print("querying robux product info")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityStoreDataFolder = splendidDataFolder:WaitForChild("VanityStore")

	for _, inst in vanityStoreDataFolder:GetChildren() :: { any } do
		local robuxProductId = inst:GetAttribute(Attributes.PRODUCT_ID)
		local discountRobuxProductId = inst:GetAttribute(Attributes.DISCOUNT_PRODUCT_ID)

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(robuxProductId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						self.robuxProductInfo[robuxProductId] = {
							robuxPrice = productInfo.PriceInRobux :: number
						}
					else
						print("product not for robux sale", robuxProductId, productInfo)
					end
				end
			end
		)

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(discountRobuxProductId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						self.robuxProductInfo[discountRobuxProductId] = {
							robuxPrice = productInfo.PriceInRobux :: number
						}
					else
						print("product not for robux sale", discountRobuxProductId, productInfo)
					end
				end
			end
		)
	end
	--print("querying robux product info kicked off")
end

function ClientVanityStore.init(self: ClientVanityStore)
	self:initWorldInterface()

	task.spawn(
		function()
			self:queryRobuxProductInfo()
		end
	)
end

function ClientVanityStore.new(): ClientVanityStore
	local self = setmetatable({} :: ClientVanityStoreFields, ClientVanityStore)

	self.robuxProductInfo = {}

	self.connections = {}

	self.discountAvailableTime = 0

	return self
end

local singleton = ClientVanityStore.new()

return singleton
