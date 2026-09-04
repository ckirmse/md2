--!strict

local ProcessReceipt = {}
ProcessReceipt.__index = ProcessReceipt

local dataStoreService = game:GetService("DataStoreService")
local marketplaceService = game:GetService("MarketplaceService")
local playersService = game:GetService("Players")


local analyticsManager = require("./AnalyticsManager")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local storageManager = require("./StorageManager")

type ProcessReceiptFields = {}

export type ProcessReceipt = typeof(setmetatable({} :: ProcessReceiptFields, ProcessReceipt))

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	--print("told to process receipt which we will now try to do", receiptInfo)

	local player = playersService:GetPlayerByUserId(userId)
	if not player then
		-- The user's items couldn't be awarded
		-- Returns "NotProcessedYet" and tries again next time the user joins the experience
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not playerData:hasProfile() then
		-- hack, should really wait more elegantly
		local found = false
		for i = 1, 20 do
			task.wait(1)
			if playerData:hasProfile() then
				found = true
				break
			end
		end
		if not found then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		print("delayed delivery of processReceipt to player", player, "proceeding")
	end


	-- rather than using StorageManager we do this inline due to the various trickiness/ordering to ensure
	-- the purchase is recorded AND granted, or neither, not a mix
	local purchaseIdsStore = dataStoreService:GetDataStore("purchaseIds")

	local isSuccess, isPurchaseRecorded = pcall(
		function()
			return purchaseIdsStore:UpdateAsync(receiptInfo.PurchaseId,
				function(isAlreadyPurchased): boolean?
					if isAlreadyPurchased then
						return true
					end

					local isGrantSuccess, isGranted = pcall(
						function()
							return gameController:tryGrantPlayerRobuxProductId(player, productId)
						end
					)

					if isGrantSuccess and isGranted then
						-- track this purchase in analytics if we just processed this for the first time
						analyticsManager:logPurchase(player, receiptInfo)
						return true
					else
						warn("Failed to process a product purchase", productId, isGranted)
						return nil
					end
				end
			)
		end
	)

	--print("purchase item, got", isSuccess, isPurchaseRecorded)

	if not isSuccess or not isPurchaseRecorded then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- we want to record the history of purchases but don't want to risk anything before telling roblox we granted the purchase,
	-- so defer our work
	task.defer(
		function()
			storageManager:recordPurchase(player, receiptInfo)
		end
	)

	-- IMPORTANT: Tell Roblox that the game successfully handled the purchase
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProcessReceipt.init(self: ProcessReceipt)
	-- Sets the callback
	-- This can only be done once by one server-side script
	marketplaceService.ProcessReceipt = processReceipt

end

function ProcessReceipt.new(): ProcessReceipt
	local self: ProcessReceipt = setmetatable({} :: ProcessReceiptFields, ProcessReceipt)

	return self
end

function ProcessReceipt.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = ProcessReceipt.new()

return singleton
