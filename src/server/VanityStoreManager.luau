--!strict

local VanityStoreManager = {}
VanityStoreManager.__index = VanityStoreManager

local memoryStoreService = game:GetService("MemoryStoreService")

local Types = require("./Types")
local itemManager = require("./ItemManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
local VanityStore = MainElements:WaitForChild("VanityStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local lootTableManager = require("./LootTableManager")

type VanityStoreManagerFields = {
	discountHashMap: MemoryStoreHashMap?,
}

export type VanityStoreManager = typeof(setmetatable({} :: VanityStoreManagerFields, VanityStoreManager))

local vanityStoreDatas = {
	{
		name = "Small",
		instName = "ChestRobuxSmall",
		headerName = "HeaderSmall",
		robuxProductId = 3602661667,
		discountRobuxProductId = 3602661755,
		lootName = "VanityStoreSmall",
	},
	{
		name = "Medium",
		instName = "ChestRobuxMedium",
		headerName = "HeaderMedium",
		robuxProductId = 3602661821,
		discountRobuxProductId = 3602661871,
		lootName = "VanityStoreMedium",
	},
	{
		name = "Large",
		instName = "ChestRobuxLarge",
		headerName = "HeaderLarge",
		robuxProductId = 3602661932,
		discountRobuxProductId = 3602662046,
		lootName = "VanityStoreLarge",
	},
}

function VanityStoreManager.addClientDataToFolder(self: VanityStoreManager, vanityStoreDataFolder: Instance)
	for _, vanityStoreData in vanityStoreDatas do
		local item = Instance.new("Part")
		item.Name = vanityStoreData.name
		item:SetAttribute(Attributes.INSTANCE_NAME, vanityStoreData.instName)
		item:SetAttribute(Attributes.HEADER_NAME, vanityStoreData.headerName)
		item:SetAttribute(Attributes.PRODUCT_ID, vanityStoreData.robuxProductId)
		item:SetAttribute(Attributes.DISCOUNT_PRODUCT_ID, vanityStoreData.discountRobuxProductId)

		local lootTableName = vanityStoreData.lootName
		local fractionTable = lootTableManager:GetLootFractionTable(lootTableName)

		item:SetAttribute(Attributes.COMMON, fractionTable[enums.Rarity.COMMON])
		item:SetAttribute(Attributes.UNCOMMON, fractionTable[enums.Rarity.UNCOMMON])
		item:SetAttribute(Attributes.RARE, fractionTable[enums.Rarity.RARE])
		item:SetAttribute(Attributes.EPIC, fractionTable[enums.Rarity.EPIC])

		item.Parent = vanityStoreDataFolder
	end

	vanityStoreDataFolder:SetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME, 0)
end

function VanityStoreManager.isDiscountProductId(self: VanityStoreManager, robuxProductId: number): boolean
	for _, vanityStoreData in vanityStoreDatas do
		if vanityStoreData.discountRobuxProductId == robuxProductId then
			return true
		end
	end

	return false
end

function VanityStoreManager.isProductId(self: VanityStoreManager, robuxProductId: number): boolean
	for _, vanityStoreData in vanityStoreDatas do
		if vanityStoreData.robuxProductId == robuxProductId then
			return true
		end
		if vanityStoreData.discountRobuxProductId == robuxProductId then
			return true
		end
	end

	return false
end

-- returns item (or nil on failure)
function VanityStoreManager.rollAndCreateItem(self: VanityStoreManager, player: Player?, lootTableName: string): any
	if not player then
		return nil
	end
	local lootEntries = lootTableManager:calculateLootResults(lootTableName)
	if #lootEntries ~= 1 then
		warn("invalid vanity loot result", lootTableName, lootEntries)
		return nil
	end

	local rarity = lootEntries[1].result
	--print("vanity store loot roll blueprint rarity", rarity)

	local blueprintNames = gameController:getBlueprintNamesForRarity(rarity)
	if #blueprintNames < 1 then
		warn("no blueprints available for rarity", rarity)
		return nil
	end

	local random = Random.new()
	local itemName = blueprintNames[random:NextInteger(1, #blueprintNames)]
	--print("vanity store purchase delivering", itemName)

	local item = itemManager:createItem(itemName, player.UserId)
	if not item then
		warn("vanity roll failed to create item", itemName)
		return nil
	end

	return item
end

function VanityStoreManager.tryDeliverToPlayer(self: VanityStoreManager, player: Player, robuxProductId: number): boolean
	local playerData = gameController:getPlayerData(player)

	for _, vanityStoreData in vanityStoreDatas do
		if vanityStoreData.robuxProductId ~= robuxProductId and vanityStoreData.discountRobuxProductId ~= robuxProductId then
			continue
		end

		local item = self:rollAndCreateItem(player, vanityStoreData.lootName)
		if not item then
			return false
		end

		task.defer(
			function()
				local visibleName = item:getVisibleName()

				local position = (VanityStore:FindFirstChild("ChestRobuxLarge") :: any):GetPivot().Position
				gameController:spawnItemsAtPositionAndGoToPlayerBackpack({item}, position, player)

				playerData:notifyItemReceived(item)

				gameController:sendSystemMessageToPlayer(player, string.format("You received a %s!", visibleName))
			end
		)

		if self:isDiscountProductId(robuxProductId) then
			-- in purchase callbacks, we can't yield so spawn this separately
			task.defer(
				function()
					local discountHashMap = self.discountHashMap
					if discountHashMap then
						pcall(
							function()
								discountHashMap:SetAsync(
									tostring(player.UserId),
									true,
									self:getSecondsUntilMidnightUTC()
								)
							end
						)
					end
					self:updateDiscountAttributeForPlayer(player, workspace:GetServerTimeNow() + self:getSecondsUntilMidnightUTC())
				end
			)
		end

		return true
	end

	warn("could not find vanity store product id, should not be possible", player, robuxProductId)

	return false
end

function VanityStoreManager.getSecondsUntilMidnightUTC(self: VanityStoreManager): number
	return 86400 - (workspace:GetServerTimeNow() % 86400)
end

function VanityStoreManager.updateDiscountAttributeForPlayer(self: VanityStoreManager, player: Player, availableTime: number)
	local splendidDataFolder = (player :: any).PlayerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	local vanityStoreDataFolder = splendidDataFolder:FindFirstChild("VanityStore")
	if not vanityStoreDataFolder then
		return
	end
	vanityStoreDataFolder:SetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME, availableTime)
end

function VanityStoreManager.resetDiscountForPlayer(self: VanityStoreManager, player: Player)
	if self.discountHashMap then
		pcall(
			function()
				self.discountHashMap:RemoveAsync(tostring(player.UserId))
			end
		)
	end
	self:updateDiscountAttributeForPlayer(player, 0)
end

function VanityStoreManager.notifyAddPlayer(self: VanityStoreManager, player: Player)
	local isAvailable = true
	if self.discountHashMap then
		local isSuccess, result = pcall(
			function()
				return self.discountHashMap:GetAsync(tostring(player.UserId))
			end
		)
		if isSuccess then
			isAvailable = (result == nil)
		else
			warn("VanityStoreManager: MemoryStore GetAsync failed for", player, result)
		end
	end
	if isAvailable then
		self:updateDiscountAttributeForPlayer(player, 0)
	else
		self:updateDiscountAttributeForPlayer(player, workspace:GetServerTimeNow() + self:getSecondsUntilMidnightUTC())
	end
end

-- this stuff can't go in new() because it depends on gameController being set
function VanityStoreManager.init(self: VanityStoreManager)

end

function VanityStoreManager.new(): VanityStoreManager
	local self: VanityStoreManager = setmetatable({} :: VanityStoreManagerFields, VanityStoreManager)

	local isSuccess, _ = pcall(
		function()
			self.discountHashMap = memoryStoreService:GetHashMap("VanityDiscountPurchases")
		end
	)
	if not isSuccess then
		warn("VanityStoreManager: MemoryStore GetHashMap failed, discount limits not enforced")
	end

	return self
end

function VanityStoreManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = VanityStoreManager.new()

return singleton
