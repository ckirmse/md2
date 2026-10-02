--!strict

local IncomeManager = {}
IncomeManager.__index = IncomeManager

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local playerAttributesManager = require("./PlayerAttributesManager")
local rideMixin = require("./RideMixin")

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local incomeData = require("@game/ServerScriptService/GameData/Control/Income")
local dragonProgressionData = require("@game/ServerScriptService/GameData/Control/DragonProgression")

local function rebirthIncomeMult(rebirthLevel: number): number
	local levelData = gameController:getRebirthLevelData(rebirthLevel)
	return levelData and levelData.incomeMult or 1
end

type IncomeManagerFields = {
	-- fractional gold carried between 1 s ticks so nothing is lost to flooring
	incomeRemainder: { [Player]: number },
}

export type IncomeManager = typeof(setmetatable({} :: IncomeManagerFields, IncomeManager))

function IncomeManager.getIncomePerSec(self: IncomeManager, playerData: Types.PlayerData): number
	return playerData:getTotalDragonIncome() * incomeData.incomeCoeff * rebirthIncomeMult(playerData:getRebirthLevel())
end

function IncomeManager.getDragonIncomePerSec(self: IncomeManager, dragon: Types.ShadowDragon): number
	local player = dragon:getPlayer()
	local rebirthLevel = if player then gameController:getPlayerData(player):getRebirthLevel() else 0

	return dragon:getIncome() * incomeData.incomeCoeff * rebirthIncomeMult(rebirthLevel)
end

function IncomeManager.tickPlayer(self: IncomeManager, player: Player, playerData: Types.PlayerData, elapsedSec: number)
	local perSec = self:getIncomePerSec(playerData)

	playerAttributesManager:set(player, PlayerAttributeKeys.INCOME_PER_SECOND, perSec)

	local gained = perSec * elapsedSec + (self.incomeRemainder[player] or 0)
	local whole = math.floor(gained)
	self.incomeRemainder[player] = gained - whole

	if whole > 0 then
		playerAttributesManager:addWholeNumber(player, PlayerAttributeKeys.COINS, whole)
	end

	self:tickDragonXp(player, playerData, elapsedSec)
end

function IncomeManager.tickDragonXp(self: IncomeManager, player: Player, playerData: Types.PlayerData, elapsedSec: number)
	for _, itemId in playerData:getStableSlots() do
		local item = itemManager:getItemById(itemId)
		if not item or item:getType() ~= "shadowDragon" then
			continue
		end

		(item :: Types.ShadowDragon):addDragonXp(dragonProgressionData.assignXpPerSec * elapsedSec)
	end

	local ridingDragon = rideMixin:tryGetRidingDragonForPlayer(player)
	if ridingDragon then
		ridingDragon:addDragonXp(dragonProgressionData.assignXpPerSec * dragonProgressionData.rideXpMultiplier * elapsedSec)
	end
end

function IncomeManager.notifyAddPlayer(self: IncomeManager, player: Player)
	self.incomeRemainder[player] = 0
end

function IncomeManager.notifyRemovePlayer(self: IncomeManager, player: Player)
	self.incomeRemainder[player] = nil
end

function IncomeManager.new(): IncomeManager
	local self = setmetatable({}, IncomeManager)
	self.incomeRemainder = {}
	return self
end

function IncomeManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

function IncomeManager.init(self: IncomeManager) end

local singleton = IncomeManager.new()

return singleton
