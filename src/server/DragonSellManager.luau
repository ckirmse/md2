--!strict

local DragonSellManager = {}
DragonSellManager.__index = DragonSellManager

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local CurrencyGranter = require("./CurrencyGranter")

type DragonSellManagerFields = {}

export type DragonSellManager = typeof(setmetatable({} :: DragonSellManagerFields, DragonSellManager))

-- dragons not stable-slotted and not being ridden; stable-slotted and ridden dragons are always
-- parented to workspace, so getItemsNotOnGroundByUserId already excludes both
function DragonSellManager.getBackpackDragons(self: DragonSellManager, player: Player): { Types.ShadowDragon }
	local dragons = {}
	for _, item in itemManager:getItemsNotOnGroundByUserId(player.UserId) do
		if item:getType() ~= "shadowDragon" then
			continue
		end

		table.insert(dragons, item :: Types.ShadowDragon)
	end
	return dragons
end

function DragonSellManager.trySellBackpackDragons(self: DragonSellManager, player: Player)
	local dragons = self:getBackpackDragons(player)
	if #dragons == 0 then
		gameController:sendSystemMessageToPlayer(player, "You have no dragons to sell")
		return
	end

	table.sort(dragons, function(a, b)
		return a:getIncome() > b:getIncome()
	end)

	local totalCount = 0
	for _, dragon in dragons do
		totalCount += dragon:getCount()
	end

	local playerData = gameController:getPlayerData(player)
	local freeSlotCount = playerData:getDragonLimit() - playerData:getPlacedDragonCount()
	local remainingSpare = math.clamp(freeSlotCount, 0, totalCount)

	local soldCount = 0
	local totalValue = 0

	-- a stack holds several identical dragons, so spare and sell by dragon, not by stack
	for _, dragon in dragons do
		local stackCount = dragon:getCount()
		local spared = math.min(remainingSpare, stackCount)
		remainingSpare -= spared

		local sellCount = stackCount - spared
		if sellCount == 0 then
			continue
		end

		totalValue += dragon:getSellValue() * sellCount
		soldCount += sellCount
		if sellCount == stackCount then
			itemManager:destroyItem(dragon)
		else
			dragon:reduceCount(sellCount)
		end
	end

	if soldCount == 0 then
		gameController:sendSystemMessageToPlayer(player, "No dragons were sold (all spared for your free dragon spots)")
		return
	end

	CurrencyGranter.grantCoins(player, totalValue, "sellDragons")
	gameController:sendSystemMessageToPlayer(
		player,
		string.format("Sold %d dragon%s for %d coins", soldCount, if soldCount == 1 then "" else "s", totalValue)
	)
end

function DragonSellManager.new(): DragonSellManager
	local self = setmetatable({}, DragonSellManager)
	return self
end

function DragonSellManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

function DragonSellManager.init(self: DragonSellManager) end

local singleton = DragonSellManager.new()

return singleton
