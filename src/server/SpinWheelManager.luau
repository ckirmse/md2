--!strict

-- Daily spin wheel, opened from a HUD button (no world presence). Prizes come from the loot table named in
-- GameData/Control/SpinWheel. Players accrue one free spin (1x luck) per calendar UTC day, even while offline, and can
-- buy 2x-luck spins with Robux; the first purchase each UTC day is the discounted product. A paid spin rolls best-of-N
-- and keeps the rarer result (lower weight ranks better, see SpinWheelMath).
-- The prize is decided at spin time but only delivered once the client's wheel animation has finished (or a fallback
-- fires), so nothing about it leaks early through the coin HUD, the message or the backpack. A prize that cannot be
-- delivered gives the spin back. The state travels in initData and NotifySpinWheelState; the result of a spin is only
-- the winning segment index.
local SpinWheelManager = {}
SpinWheelManager.__index = SpinWheelManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local SpinWheelMath = require("@game/ReplicatedStorage/Shared/SpinWheelMath")
local spinWheelData = require("@game/ServerScriptService/GameData/Control/SpinWheel")

local lootTableManager = require("./LootTableManager")
local objectDataStore = require("./ObjectDataStore")
local RewardGranter = require("./RewardGranter")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ACQUISITION_SOURCE = "spinWheel"

local kinds = Enums.PlaytimeRewardKind

type PendingPrize = {
	reward: RewardGranter.GrantableReward,
	wasPaid: boolean,
	generation: number,
}

-- one record per wheel segment, in loot-table order, with the odds at both luck levels; never holds a rolled item
type ClientSegment = {
	kind: number,
	fraction: number,
	paidFraction: number,
	coinAmount: number?,
	diamondAmount: number?,
	skipSec: number?,
	itemName: string?,
	itemType: number?,
	displayName: string?,
	rarity: number?,
	iconAssetId: string?,
}

export type ClientSpinWheelState = {
	freeSpins: number,
	paidSpins: number,
	isDiscountAvailable: boolean,
}

export type ClientSpinWheel = ClientSpinWheelState & {
	catalog: { ClientSegment },
	robuxProductIds: { [string]: number },
}

type SpinWheelManagerFields = {
	boundaryTimerGeneration: number,
	pendingByPlayer: { [Player]: PendingPrize },
	pendingGeneration: number,
	catalog: { ClientSegment }?,
}

export type SpinWheelManager = typeof(setmetatable({} :: SpinWheelManagerFields, SpinWheelManager))

-- the Robux product ids and how many paid spins each one buys
local PRODUCT_SPINS = {
	single = { count = 1, isDiscount = false },
	singleDiscount = { count = 1, isDiscount = true },
	five = { count = 5, isDiscount = false },
}

local function getToday(): number
	return SpinWheelMath.computeEpochDay(workspace:GetServerTimeNow())
end

-- the Enums.ItemType of an object, from its `type` string
local function getItemTypeByObjectType(objectType: string): number?
	for itemType, typeName in Enums.ItemType.ObjectTypes do
		if typeName == objectType then
			return itemType
		end
	end

	return nil
end

function SpinWheelManager.getClientState(self: SpinWheelManager, playerData: Types.PlayerData): ClientSpinWheelState
	local state = playerData:getSpinWheel()

	return {
		freeSpins = state.freeSpins,
		paidSpins = state.paidSpins,
		isDiscountAvailable = state.lastDiscountDay < getToday(),
	}
end

-- one entry per wheel segment, built lazily (first player) so ObjectDataStore and the loot tables are loaded
function SpinWheelManager.getCatalog(self: SpinWheelManager): { ClientSegment }
	local cached = self.catalog
	if cached then
		return cached
	end

	local segments: { ClientSegment } = {}
	local lootTable = lootTableManager:getLootTable(spinWheelData.lootTableName)
	if lootTable then
		local fractions = SpinWheelMath.computeFractions(lootTable)
		local paidFractions = SpinWheelMath.computeBestOfNFractions(lootTable, spinWheelData.paidLuckMultiplier)

		for index, lootEntry in lootTable do
			local result = lootEntry.result
			local segment: ClientSegment = {
				kind = result.kind,
				fraction = fractions[index],
				paidFraction = paidFractions[index],
				coinAmount = nil,
				diamondAmount = nil,
				skipSec = nil,
				itemName = nil,
				itemType = nil,
				displayName = nil,
				rarity = nil,
				iconAssetId = nil,
			}

			if result.kind == kinds.COINS then
				segment.coinAmount = result.minCoins
			elseif result.kind == kinds.DIAMONDS then
				segment.diamondAmount = result.diamondAmount
			elseif result.kind == kinds.TIME_SKIP then
				segment.skipSec = result.skipSec
			elseif result.kind == kinds.FIXED_ITEM then
				segment.itemName = result.itemName
				local itemData = objectDataStore:getObjectDataByName(result.itemName)
				if itemData then
					segment.itemType = getItemTypeByObjectType(itemData.type)
					segment.displayName = itemData.displayName
					segment.rarity = itemData.rarity or Enums.Rarity.COMMON
				end
			elseif result.kind == kinds.LOOT_TABLE then
				-- the item is rolled from the named table at spin time, so only the authored face is sent
				segment.itemType = result.itemType
				segment.displayName = result.displayName
				segment.rarity = result.rarity
				segment.iconAssetId = result.iconAssetId
			end

			table.insert(segments, segment)
		end
	end

	self.catalog = segments
	return segments
end

function SpinWheelManager.getClientData(self: SpinWheelManager, playerData: Types.PlayerData): ClientSpinWheel
	local data = self:getClientState(playerData) :: ClientSpinWheel
	data.catalog = self:getCatalog()
	data.robuxProductIds = spinWheelData.robuxProductIds or {}

	return data
end

function SpinWheelManager.sendState(self: SpinWheelManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	RemoteEvents.NotifySpinWheelState:FireClient(player, self:getClientState(playerData))
end

-- grants any elapsed UTC days' free spins (idempotent) without sending anything
function SpinWheelManager.grantElapsedSpins(self: SpinWheelManager, playerData: Types.PlayerData)
	local today = getToday()
	local state = table.clone(playerData:getSpinWheel())
	local granted = SpinWheelMath.computeGrantedFreeSpins(state.lastGrantDay, today, spinWheelData.maxAccruedFreeSpins)
	if granted > 0 then
		state.freeSpins += granted
	end
	state.lastGrantDay = today
	playerData:setSpinWheel(state)
end

-- safe to call any time a player's day may have rolled over
function SpinWheelManager.refreshPlayer(self: SpinWheelManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	self:grantElapsedSpins(playerData)
	self:sendState(player)
end

-- called before initData is built, so the state the client starts with already includes today's spin
function SpinWheelManager.notifyAddPlayer(self: SpinWheelManager, player: Player, playerData: Types.PlayerData)
	self:grantElapsedSpins(playerData)
end

-- one server-wide timer: every player crosses the same UTC epoch-day boundary
function SpinWheelManager.scheduleNextBoundary(self: SpinWheelManager)
	local generation = self.boundaryTimerGeneration + 1
	self.boundaryTimerGeneration = generation

	local now = workspace:GetServerTimeNow()
	local delaySec = SpinWheelMath.getNextDayBoundaryTime(now) - now
	task.delay(math.max(1, delaySec), function()
		if self.boundaryTimerGeneration ~= generation then
			return
		end

		for _, player in Players:GetPlayers() do
			self:refreshPlayer(player)
		end
		self:scheduleNextBoundary()
	end)
end

-- the grantable form of a rolled wheel result; a LOOT_TABLE result rolls its item now. nil (with a warning) if
-- it cannot be turned into a prize
function SpinWheelManager.resolveReward(self: SpinWheelManager, result: any): RewardGranter.GrantableReward?
	if result.kind == kinds.COINS then
		return { kind = result.kind, coinAmount = result.minCoins, skipSec = nil, minCoins = nil, itemName = nil }
	elseif result.kind == kinds.DIAMONDS then
		return { kind = result.kind, diamondAmount = result.diamondAmount }
	elseif result.kind == kinds.TIME_SKIP then
		return { kind = result.kind, coinAmount = nil, skipSec = result.skipSec, minCoins = result.minCoins, itemName = nil }
	elseif result.kind == kinds.FIXED_ITEM then
		return { kind = result.kind, coinAmount = nil, skipSec = nil, minCoins = nil, itemName = result.itemName }
	elseif result.kind == kinds.LOOT_TABLE then
		local lootEntries = lootTableManager:calculateLootResults(result.lootTableName)
		local rolledResult = if #lootEntries > 0 then lootEntries[1].result else nil
		if type(rolledResult) ~= "table" or type(rolledResult.itemName) ~= "string" then
			warn("SpinWheelManager: loot table rolled no item", result.lootTableName)
			return nil
		end

		return { kind = kinds.FIXED_ITEM, coinAmount = nil, skipSec = nil, minCoins = nil, itemName = rolledResult.itemName }
	end

	warn("SpinWheelManager: unsupported prize kind", result.kind)
	return nil
end

-- delivers the held prize. A failed delivery gives the spin back so it is never lost for nothing
function SpinWheelManager.deliverPending(self: SpinWheelManager, player: Player, isLeaving: boolean)
	local pending = self.pendingByPlayer[player]
	if not pending then
		return
	end
	self.pendingByPlayer[player] = nil

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local grantedText, failureMessage = RewardGranter.grant(player, playerData, pending.reward, ACQUISITION_SOURCE)
	if grantedText then
		gameController:sendSystemMessageToPlayer(player, `You won {grantedText}!`)
		return
	end

	local state = table.clone(playerData:getSpinWheel())
	if pending.wasPaid then
		state.paidSpins += 1
	else
		state.freeSpins += 1
	end
	playerData:setSpinWheel(state)

	if not isLeaving then
		self:sendState(player)
		if failureMessage then
			gameController:sendSystemMessageToPlayer(player, `{failureMessage} Your spin was given back.`)
		end
	end
end

function SpinWheelManager.tryClaimPrize(self: SpinWheelManager, player: Player)
	self:deliverPending(player, false)
end

-- called before the player's data is torn down, so the grant lands in the save
function SpinWheelManager.deliverPendingOnLeave(self: SpinWheelManager, player: Player)
	self:deliverPending(player, true)
end

function SpinWheelManager.notifyRemovePlayer(self: SpinWheelManager, player: Player)
	self.pendingByPlayer[player] = nil
end

function SpinWheelManager.trySpin(self: SpinWheelManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	-- refresh first so a spin raced against the day boundary sees fresh state
	self:grantElapsedSpins(playerData)

	local state = table.clone(playerData:getSpinWheel())
	local wasPaid: boolean
	if state.freeSpins > 0 then
		state.freeSpins -= 1
		wasPaid = false
	elseif state.paidSpins > 0 then
		state.paidSpins -= 1
		wasPaid = true
	else
		self:sendState(player)
		return
	end

	local lootTableName = spinWheelData.lootTableName
	local lootTable = lootTableManager:getLootTable(lootTableName)
	if not lootTable or #lootTable == 0 then
		warn("SpinWheelManager: loot table missing or empty", lootTableName)
		return
	end

	local entries
	if wasPaid then
		entries = lootTableManager:calculateBestLootResults(
			lootTableName,
			spinWheelData.paidLuckMultiplier,
			SpinWheelMath.makeIsBetterResult(lootTable)
		)
	else
		entries = lootTableManager:calculateLootResults(lootTableName)
	end
	if #entries == 0 then
		return
	end

	local segmentIndex = table.find(lootTable, entries[1])
	if not segmentIndex then
		warn("SpinWheelManager: rolled entry not found in loot table", lootTableName)
		return
	end

	local reward = self:resolveReward(entries[1].result)
	if not reward then
		return
	end

	-- a re-spin before the previous prize was claimed must not orphan it; deliver it first, which can hand its spin
	-- back, so the state to write is re-read afterwards
	self:deliverPending(player, false)
	state = table.clone(playerData:getSpinWheel())
	if wasPaid then
		state.paidSpins -= 1
	else
		state.freeSpins -= 1
	end
	if state.freeSpins < 0 or state.paidSpins < 0 then
		return
	end

	local generation = self.pendingGeneration + 1
	self.pendingGeneration = generation
	self.pendingByPlayer[player] = { reward = reward, wasPaid = wasPaid, generation = generation }

	playerData:setSpinWheel(state)
	self:sendState(player)
	RemoteEvents.NotifySpinWheelResult:FireClient(player, segmentIndex, wasPaid)

	-- fallback for a client that closed the dialog, hid the UI or never claims
	task.delay(spinWheelData.prizeClaimTimeoutSec, function()
		local pending = self.pendingByPlayer[player]
		if pending and pending.generation == generation then
			self:deliverPending(player, false)
		end
	end)
end

function SpinWheelManager.isProductId(self: SpinWheelManager, productId: number): boolean
	local robuxProductIds = spinWheelData.robuxProductIds
	if not robuxProductIds then
		return false
	end

	for name in PRODUCT_SPINS do
		if robuxProductIds[name] == productId then
			return true
		end
	end

	return false
end

-- a receipt for a wheel product adds paid spins; spinning them is a separate action
function SpinWheelManager.tryDeliverToPlayer(self: SpinWheelManager, player: Player, productId: number): boolean
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return false
	end

	local robuxProductIds = spinWheelData.robuxProductIds or {}
	for name, product in PRODUCT_SPINS do
		if robuxProductIds[name] ~= productId then
			continue
		end

		local state = table.clone(playerData:getSpinWheel())
		state.paidSpins += product.count
		if product.isDiscount then
			-- ProcessReceipt can't reject a completed purchase, so a stale client buying the discount product twice in
			-- a day still gets its spin; the stamp just closes the window going forward
			state.lastDiscountDay = getToday()
		end
		playerData:setSpinWheel(state)
		self:sendState(player)
		gameController:sendSystemMessageToPlayer(
			player,
			if product.count == 1 then "You bought 1 wheel spin!" else `You bought {product.count} wheel spins!`
		)
		return true
	end

	return false
end

-- dev tool: adds spins without a purchase
function SpinWheelManager.debugAddSpins(self: SpinWheelManager, player: Player, freeCount: number, paidCount: number)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local state = table.clone(playerData:getSpinWheel())
	state.freeSpins += freeCount
	state.paidSpins += paidCount
	playerData:setSpinWheel(state)
	self:sendState(player)
end

-- dev tool: pretends the last grant and discount happened yesterday, then refreshes (grants a day's spin and reopens
-- the discount)
function SpinWheelManager.debugAdvanceDay(self: SpinWheelManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local state = table.clone(playerData:getSpinWheel())
	state.lastGrantDay = math.max(1, getToday() - 1)
	state.lastDiscountDay = math.min(state.lastDiscountDay, getToday() - 1)
	playerData:setSpinWheel(state)
	self:refreshPlayer(player)
end

-- dev tool: back to a brand-new player (the sentinel grants exactly one free spin again)
function SpinWheelManager.resetPlayer(self: SpinWheelManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	self.pendingByPlayer[player] = nil
	playerData:resetSpinWheel()
	self:refreshPlayer(player)
end

function SpinWheelManager.init(self: SpinWheelManager)
	self:scheduleNextBoundary()
end

function SpinWheelManager.new(): SpinWheelManager
	local self = setmetatable({
		boundaryTimerGeneration = 0,
		pendingByPlayer = {},
		pendingGeneration = 0,
		catalog = nil,
	} :: SpinWheelManagerFields, SpinWheelManager)

	return self
end

function SpinWheelManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = SpinWheelManager.new()

return singleton
