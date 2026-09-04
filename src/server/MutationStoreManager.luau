--!strict

local MutationStoreManager = {}
MutationStoreManager.__index = MutationStoreManager

local memoryStoreService = game:GetService("MemoryStoreService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager = require("./ItemManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
local MutationStore = MainElements:WaitForChild("MutationStore")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local lootTableManager = require("./LootTableManager")

type MutationStoreManagerFields = {
	discountHashMap: MemoryStoreHashMap?,
}

export type MutationStoreManager = typeof(setmetatable({} :: MutationStoreManagerFields, MutationStoreManager))

local ELEMENT_COLOR_NAMES: { [number]: string } = {
	[enums.PrimaryElements.NATURE] = "Green",
	[enums.PrimaryElements.WATER] = "Blue",
	[enums.PrimaryElements.FIRE] = "Red",
}

local mutationStoreDatas = {
	{
		name = "Small",
		instName = "TubeRobuxSmall",
		headerName = "Header_Small",
		robuxProductId = 3602662117,
		discountRobuxProductId = 3602662175,
		lootName = "MutationStoreSmall",
	},
	{
		name = "Medium",
		instName = "TubeRobuxMedium",
		headerName = "Header_Medium",
		robuxProductId = 3602662236,
		discountRobuxProductId = 3602662302,
		lootName = "MutationStoreMedium",
	},
	{
		name = "Large",
		instName = "TubeRobuxLarge",
		headerName = "Header_Large",
		robuxProductId = 3602662377,
		discountRobuxProductId = 3602662442,
		lootName = "MutationStoreLarge",
	},
}


function MutationStoreManager.addClientDataToFolder(self: MutationStoreManager, mutationStoreDataFolder: Instance)
	for _, mutationStoreData in mutationStoreDatas do
		local item = Instance.new("Part")
		item.Name = mutationStoreData.name
		item:SetAttribute(Attributes.INSTANCE_NAME, mutationStoreData.instName)
		item:SetAttribute(Attributes.HEADER_NAME, mutationStoreData.headerName)
		item:SetAttribute(Attributes.PRODUCT_ID, mutationStoreData.robuxProductId)
		item:SetAttribute(Attributes.DISCOUNT_PRODUCT_ID, mutationStoreData.discountRobuxProductId)

		local fractionTable = lootTableManager:GetLootFractionTable(mutationStoreData.lootName)

		for _, mutation in enums.getAllValues(enums.Mutations) do
			local mutationName = enums.getPublicName(enums.Mutations, mutation)
			if not mutationName then
				continue
			end
			item:SetAttribute(mutationName, fractionTable[mutation] or 0)
		end

		item.Parent = mutationStoreDataFolder
	end

	mutationStoreDataFolder:SetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME, 0)
end

function MutationStoreManager.isDiscountProductId(self: MutationStoreManager, robuxProductId: number): boolean
	for _, mutationStoreData in mutationStoreDatas do
		if mutationStoreData.discountRobuxProductId == robuxProductId then
			return true
		end
	end
	return false
end

function MutationStoreManager.isProductId(self: MutationStoreManager, robuxProductId: number): boolean
	for _, mutationStoreData in mutationStoreDatas do
		if mutationStoreData.robuxProductId == robuxProductId then
			return true
		end
		if mutationStoreData.discountRobuxProductId == robuxProductId then
			return true
		end
	end
	return false
end

-- returns item, mutation (or nil, nil on failure)
function MutationStoreManager.rollAndCreateItem(self: MutationStoreManager, player: Player?, lootTableName: string): (any, any)
	if not player then
		return nil, nil
	end
	local lootEntries = lootTableManager:calculateLootResults(lootTableName)
	if #lootEntries ~= 1 then
		warn("invalid mutation loot result", lootTableName, lootEntries)
		return nil, nil
	end

	local mutation = lootEntries[1].result

	local random = Random.new()
	local primaryElements = Elements.getPrimaryElementsSorted()
	local primaryElement = primaryElements[random:NextInteger(1, #primaryElements)]
	local colorName = ELEMENT_COLOR_NAMES[primaryElement]

	local itemName
	if random:NextNumber() < 0.5 then
		itemName = colorName .. " Dragon Level 1"
	else
		itemName = colorName .. " Plant 1"
	end

	-- dragons and plants are both MItems, so they can carry the rolled mutation
	local item = itemManager:createItem(itemName, player.UserId) :: Types.MItem?
	if not item then
		warn("mutation roll failed to create item", itemName)
		return nil, nil
	end

	item:setMutation(mutation)

	return item, mutation
end

function MutationStoreManager.tryDeliverToPlayer(self: MutationStoreManager, player: Player, robuxProductId: number): boolean
	local playerData = gameController:getPlayerData(player)

	for _, mutationStoreData in mutationStoreDatas do
		if mutationStoreData.robuxProductId ~= robuxProductId and mutationStoreData.discountRobuxProductId ~= robuxProductId then
			continue
		end

		local item, mutation = self:rollAndCreateItem(player, mutationStoreData.lootName)
		if not item then
			return false
		end

		task.defer(
			function()
				local visibleName = item:getVisibleName()

				local itemData = item:getItemData()
				local templatePath = itemData.casterPath or itemData.templatePath
				local mutationSurfaceAppearanceName = itemData.mutationSurfaceAppearanceName
				local cameraPosition = itemData.buy and itemData.buy.cameraPosition or nil

				item:setPreventSettling()

				local position = (MutationStore:FindFirstChild("TubeRobuxLarge") :: any):GetPivot().Position
				gameController:spawnItemsAtPositionAndGoToPlayerBackpack({item}, position, player)

				playerData:notifyItemReceived(item)

				--gameController:sendSystemMessageToPlayer(player, string.format("You received a %s!", visibleName))

				local text = string.format("You received a %s!", visibleName)
				RemoteEvents.NotifyMutationStorePurchase:FireClient(player, text, templatePath, mutation, mutationSurfaceAppearanceName, cameraPosition)
			end
		)

		if self:isDiscountProductId(robuxProductId) then
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

	warn("could not find mutation store product id", player, robuxProductId)
	return false
end

function MutationStoreManager.getSecondsUntilMidnightUTC(self: MutationStoreManager): number
	return 86400 - (workspace:GetServerTimeNow() % 86400)
end

function MutationStoreManager.updateDiscountAttributeForPlayer(self: MutationStoreManager, player: Player, availableTime: number)
	local splendidDataFolder = (player :: any).PlayerGui:FindFirstChild(Constants.SPLENDID_DATA_NAME)
	if not splendidDataFolder then
		return
	end
	local mutationStoreDataFolder = splendidDataFolder:FindFirstChild("MutationStore")
	if not mutationStoreDataFolder then
		return
	end
	mutationStoreDataFolder:SetAttribute(Attributes.DISCOUNT_AVAILABLE_TIME, availableTime)
end

function MutationStoreManager.notifyAddPlayer(self: MutationStoreManager, player: Player)
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
			warn("MutationStoreManager: MemoryStore GetAsync failed for", player, result)
		end
	end
	if isAvailable then
		self:updateDiscountAttributeForPlayer(player, 0)
	else
		self:updateDiscountAttributeForPlayer(player, workspace:GetServerTimeNow() + self:getSecondsUntilMidnightUTC())
	end
end

function MutationStoreManager.init(self: MutationStoreManager)

end

function MutationStoreManager.new(): MutationStoreManager
	local self: MutationStoreManager = setmetatable({} :: MutationStoreManagerFields, MutationStoreManager)

	local isSuccess, _ = pcall(
		function()
			self.discountHashMap = memoryStoreService:GetHashMap("MutationDiscountPurchases")
		end
	)
	if not isSuccess then
		warn("MutationStoreManager: MemoryStore GetHashMap failed, discount limits not enforced")
	end

	return self
end

function MutationStoreManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = MutationStoreManager.new()

return singleton
