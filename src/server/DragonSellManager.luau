--!strict

local DragonSellManager = {}
DragonSellManager.__index = DragonSellManager

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local playerAttributesManager = require("./PlayerAttributesManager")
local rideMixin = require("./RideMixin")
local stableManager = require("./StableManager")

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

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

function DragonSellManager.trySellRiddenDragon(self: DragonSellManager, player: Player)
	if not rideMixin:isPlayerRiding(player) then
		gameController:sendSystemMessageToPlayer(player, "You must be riding a dragon to sell it")
		return
	end

	local dragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if not dragon then
		return
	end

	if not gameController:tryStowRidingDragon(player) then
		return
	end

	local sellValue = dragon:getSellValue()
	local dragonName = dragon:getDisplayName()

	itemManager:destroyItem(dragon)

	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, sellValue)
	gameController:sendSystemMessageToPlayer(player, string.format("Sold %s for %d coins", dragonName, sellValue))
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

	local playerData = gameController:getPlayerData(player)
	local freeSlotCount = stableManager:getStableSlotCount(player) - utils.getTableSize(playerData:getStableSlots())
	local spareCount = math.clamp(freeSlotCount, 0, #dragons)

	local soldCount = 0
	local totalValue = 0

	for i = spareCount + 1, #dragons do
		local dragon = dragons[i]
		totalValue += dragon:getSellValue()
		itemManager:destroyItem(dragon)
		soldCount += 1
	end

	if soldCount == 0 then
		gameController:sendSystemMessageToPlayer(player, "No dragons were sold (all spared for your free stable slots)")
		return
	end

	playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, totalValue)
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
