--!strict

local IncomeManager = {}
IncomeManager.__index = IncomeManager

local Types = require("./Types")
local playerAttributesManager = require("./PlayerAttributesManager")

local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local incomeData = require("@game/ServerScriptService/GameData/Control/Income")

type IncomeManagerFields = {
	-- fractional gold carried between 1 s ticks so nothing is lost to flooring
	incomeRemainder: { [Player]: number },
}

export type IncomeManager = typeof(setmetatable({} :: IncomeManagerFields, IncomeManager))

function IncomeManager.getIncomePerSec(self: IncomeManager, playerData: Types.PlayerData): number
	return playerData:getTotalDragonPower() * incomeData.incomeCoeff
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

function IncomeManager.init(self: IncomeManager) end

local singleton = IncomeManager.new()

return singleton
