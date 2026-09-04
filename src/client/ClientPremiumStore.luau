--!strict

local ClientPremiumStore = {}
ClientPremiumStore.__index = ClientPremiumStore

local marketplaceService = game:GetService("MarketplaceService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
-- the store template's shape only exists in Studio, so it is untyped here
local PremiumStore: any = MainElements:WaitForChild("PremiumStore")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")
local Types = require("./Types")

local DEFAULT_CAMERA_POSITION_DATA = {0, 2, 5}
local ROTATION_SEC = 5

local PREMIUM_STORE_NAME = "PremiumStore"

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("StarterOffer")

type ClientPremiumStoreFields = {
	premiumStoreFolder: any?, -- PremiumStore clone
	proximityThresholdTracker: ProximityThresholdTracker.ProximityThresholdTracker?,
	starterOfferData: any, -- server-sent offer data
	robuxPrice: number?,
	purchaseButtonConnect: RBXScriptConnection?,
	runConnect: RBXScriptConnection?,
}

export type ClientPremiumStore = typeof(setmetatable({} :: ClientPremiumStoreFields, ClientPremiumStore))

function ClientPremiumStore.getGuiRoot(self: ClientPremiumStore): Instance
	return GuiRoot
end

function ClientPremiumStore.notifyForceEnd(self: ClientPremiumStore)
	self:cleanupStore()
end

function ClientPremiumStore.notifyClickOutside(self: ClientPremiumStore)
	self:notifyForceEnd()
end

function ClientPremiumStore.getHudElements(self: ClientPremiumStore): { number }
	return {}
end

function ClientPremiumStore.beginStore(self: ClientPremiumStore)
	local objProximityPrompt: any = utils.findFirstDescendant(self.premiumStoreFolder :: any, "ProximityPrompt")
	objProximityPrompt.Enabled = false

	self:updateStarterOffer()

	local Main = GuiRoot:WaitForChild("Main")
	local Header = Main:WaitForChild("Header")
	local restock = Header:WaitForChild("Restock")
	local Offers = Main:FindFirstChild("Offers")

	local totalTime = 0
	self.runConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			local timeRemainingSec = math.ceil(math.max(0, self.starterOfferData.endTime - workspace:GetServerTimeNow()))
			restock.Text = utils.convertDurationSecToString(timeRemainingSec)

			for _, inst in Offers:GetChildren() do
				if inst.Name ~= "Offer" then
					continue
				end

				local viewportFrame: any = utils.findFirstDescendant(inst, "ViewportFrame")

				totalTime += deltaTime

				local obj = viewportFrame:FindFirstChildOfClass("Model") or viewportFrame:FindFirstChildOfClass("BasePart")

				-- 1. Get the bounding box CFrame and extract its position (the geometric center)
				local boundingBoxCFrame, _ = obj:GetBoundingBox()
				local centerPoint = boundingBoxCFrame.Position

				-- 2. Get the model's current pivot CFrame
				local currentPivot = obj:GetPivot()

				-- 3. Construct the rotation transformation
				-- This shifts the math to the bounding box center, rotates, and shifts back
				local rotationTransform = CFrame.new(centerPoint)
					* CFrame.Angles(0, math.rad(360 * deltaTime / ROTATION_SEC), 0)
					* CFrame.new(-centerPoint)

				-- 4. Calculate the new pivot CFrame and apply it to the model
				local newPivot = rotationTransform * currentPivot
				obj:PivotTo(newPivot)
			end

		end
	)

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientPremiumStore.cleanupStore(self: ClientPremiumStore)
	GuiRoot.Enabled = false

	local objProximityPrompt: any = utils.findFirstDescendant(self.premiumStoreFolder :: any, "ProximityPrompt")
	objProximityPrompt.Enabled = true

	local purchaseButtonConnect = self.purchaseButtonConnect
	if purchaseButtonConnect then
		purchaseButtonConnect:Disconnect()
		self.purchaseButtonConnect = nil
	end

	local runConnect = self.runConnect
	if runConnect then
		runConnect:Disconnect()
		self.runConnect = nil
	end

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end


function ClientPremiumStore.updateStarterOffer(self: ClientPremiumStore)
	local Main = GuiRoot:WaitForChild("Main")

	-- hide/remove non-template items

	local storeOfferTemplate: any
	local Offers = Main:FindFirstChild("Offers")
	for _, inst in Offers:GetChildren() do
		if inst.Name == "OfferTemplate" then
			storeOfferTemplate = inst
			continue
		end

		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end

		inst:Destroy()
	end

	storeOfferTemplate.Visible = false

	for _, itemDescriptor in self.starterOfferData.itemDescriptors do
		local offer = storeOfferTemplate:Clone()
		offer.Name = "Offer"

		local viewportFrame: any = utils.findFirstDescendant(offer, "ViewportFrame")

		local inst = utils.getPathReference(GameAssets, itemDescriptor.templatePath)
		if not inst then
			print("failed to find template for instance in premium store", itemDescriptor.templatePath)
			continue
		end

		local obj: any = inst:Clone()

		if itemDescriptor.mutation and itemDescriptor.mutation ~= enums.Mutations.NORMAL then
			local mutationSurfaceAppearanceName = itemDescriptor.mutationSurfaceAppearanceName
			utils.applyMutationToObj(obj, itemDescriptor.mutation, mutationSurfaceAppearanceName)
		end

		-- 1. Get the bounding box CFrame and extract its position (the geometric center)
		local boundingBoxCFrame, _ = obj:GetBoundingBox()
		local centerPoint = boundingBoxCFrame.Position

		-- 2. Get the model's current pivot CFrame
		local currentPivot = obj:GetPivot()

		-- 3. Construct the move transformation
		local moveTransform = CFrame.new(-centerPoint)

		-- 4. Calculate the new pivot CFrame and apply it to the model
		local newPivot = moveTransform * currentPivot
		obj:PivotTo(newPivot)

		obj.Parent = viewportFrame

		local viewportCamera = Instance.new("Camera")
		viewportFrame.CurrentCamera = viewportCamera
		viewportCamera.Parent = viewportFrame

		local cameraPositionData = itemDescriptor.cameraPosition or DEFAULT_CAMERA_POSITION_DATA

		viewportFrame.CurrentCamera.CFrame = CFrame.new(Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3]), Vector3.zero)

		local description = offer:FindFirstChild("Description")
		description.Text = itemDescriptor.description

		offer.Visible = true

		offer.Parent = Offers
	end


	local oldPriceNumber = (self.robuxPrice :: number) * 111
	local priceNumber = self.robuxPrice :: number
	local discountNumber = oldPriceNumber - priceNumber

	local DiscountTitle  = Main:FindFirstChild("DiscountTitle")
	DiscountTitle.Text = string.format("%i%% OFF", math.floor(100 * (oldPriceNumber - priceNumber) / oldPriceNumber))

	local Purchase = Main:FindFirstChild("Purchase")
	local TextLabel = Purchase:FindFirstChild("TextLabel")
	TextLabel.Text = string.format("Save %i Robux!\nLimited Time Offer!", discountNumber)
	local CollectButton = Purchase:FindFirstChild("CollectButton")
	local OldPrice = CollectButton:FindFirstChild("OldPrice")
	local Price = CollectButton:FindFirstChild("Price")

	OldPrice.Text = tostring(oldPriceNumber)
	Price.Text = tostring(priceNumber)

	self.purchaseButtonConnect = CollectButton.Activated:Connect(
		function()
			--print("trying to buy starter offer")

			local isSuccess, errorMessage = pcall(
				function()
					marketplaceService:PromptProductPurchase(player, self.starterOfferData.robuxProductId)
				end
			)

			if isSuccess then
				--print("yes prompted")
			else
				warn("error prompting for robux purchase", errorMessage)
			end

			self:cleanupStore()
		end
	) :: RBXScriptConnection
end

function ClientPremiumStore.initWorldInterface(self: ClientPremiumStore)
	local premiumStoreFolder = PremiumStore:Clone()
	premiumStoreFolder.Name = PREMIUM_STORE_NAME
	premiumStoreFolder.Parent = workspace

	self.premiumStoreFolder = premiumStoreFolder

	local objProximityPrompt: any = utils.findFirstDescendant(premiumStoreFolder, "ProximityPrompt")

	objProximityPrompt.PromptShown:Connect(
		function()
		end
	)

	objProximityPrompt.PromptHidden:Connect(
		function()
		end
	)

	objProximityPrompt.Triggered:Connect(
		function(_player: Player)
			--print("interacted, showing dialog box")
			self:beginStore()
		end
	)

	local chest = premiumStoreFolder:FindFirstChild("Chest")

	local proximityThresholdTracker = ProximityThresholdTracker.new(chest:GetPivot().Position, 10)
	self.proximityThresholdTracker = proximityThresholdTracker

	proximityThresholdTracker:getEnterEvent():Connect(
		function()
		end
	)

	proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			if not GuiRoot.Enabled then
				return
			end

			self:cleanupStore()
		end
	)


	local Main = GuiRoot:WaitForChild("Main")
	Main:WaitForChild("Header"):WaitForChild("ExitButton").Activated:Connect(
		function()
			self:cleanupStore()
		end
	)

end

function ClientPremiumStore.initStarterOfferData(self: ClientPremiumStore, starterOfferData: any)
	self.starterOfferData = starterOfferData

	if not self.starterOfferData then
		return
	end

	if not self.starterOfferData.itemDescriptors then
		return
	end

	--[[
	if self.starterOfferData.beginTime then
		print("beginning at", self.starterOfferData.beginTime - workspace:GetServerTimeNow())
	else
		print("begin immediately if at all")
	end
	print("ending at", self.starterOfferData.endTime - workspace:GetServerTimeNow())
	]]

	-- lookup product info
	local isSuccess, productInfo = pcall(
		function()
			return marketplaceService:GetProductInfoAsync(self.starterOfferData.robuxProductId, Enum.InfoType.Product) :: any
		end
	)
	if isSuccess then
		--print("got marketplace info", productInfo)
		if productInfo.IsForSale then
			self.robuxPrice = productInfo.PriceInRobux :: number
		else
			print("product not for robux sale",productInfo)
		end
	else
		print("failed to get info for", self.starterOfferData.robuxProductId, productInfo)
		return
	end

	local waitShowSec = 0
	if self.starterOfferData.beginTime then
		-- as of 2026-august-11 this calls GetServerTimeNow; it previously called
		-- getServerTimeNow (lowercase), which is not a member and would have thrown whenever
		-- the offer had a begin time
		waitShowSec = math.max(0, self.starterOfferData.beginTime - workspace:GetServerTimeNow())
	end
	--print("starter offer available in", waitShowSec)
	task.delay(waitShowSec,
		function()
			self:initWorldInterface()
		end
	)
end

function ClientPremiumStore.notifyEndStarterOffer(self: ClientPremiumStore)
	if GuiRoot.Enabled then
		self:cleanupStore()
	end

	local premiumStoreFolder = self.premiumStoreFolder
	if premiumStoreFolder then
		premiumStoreFolder:Destroy()
		self.premiumStoreFolder = nil
	end

	local proximityThresholdTracker = self.proximityThresholdTracker
	if proximityThresholdTracker then
		proximityThresholdTracker:destroy()
		self.proximityThresholdTracker = nil
	end

end

function ClientPremiumStore.init(self: ClientPremiumStore)

end

function ClientPremiumStore.new(): ClientPremiumStore
	local self = setmetatable({} :: ClientPremiumStoreFields, ClientPremiumStore)

	return self
end

local singleton = ClientPremiumStore.new()

return singleton
