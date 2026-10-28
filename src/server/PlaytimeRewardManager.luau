--!strict

-- Session-playtime rewards: each reward unlocks after a set number of seconds of the current session. Nothing is
-- saved, so unclaimed rewards are lost when the player leaves and the next session starts fresh.
--
-- COINS amounts are fixed when the session starts. Items (RANDOM_BY_RARITY, LOOT_TABLE) and TIME_SKIP are rolled
-- or computed at CLAIM time. The set is sent to the client at join, and a rejoin is free, so anything shown in
-- advance could be rerolled by relogging until the best item appeared; the client only learns what it got after
-- the claim. A time skip is worth income x seconds, so it is also computed at claim, and a claim that would pay
-- nothing is refused instead of burning the reward.

local PlaytimeRewardManager = {}
PlaytimeRewardManager.__index = PlaytimeRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local playtimeData = require("@game/ServerScriptService/GameData/Control/Playtime")
local PlaytimeRewardMath = require("@game/ReplicatedStorage/Shared/PlaytimeRewardMath")

local incomeManager = require("./IncomeManager")
local lootTableManager = require("./LootTableManager")
local objectDataStore = require("./ObjectDataStore")
local RewardGranter = require("./RewardGranter")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ACQUISITION_SOURCE = "playtimeReward"
local LOOT_TABLE_LABEL = "Mystery Prize"

local kinds = enums.PlaytimeRewardKind

type PlaytimeRewardState = {
	index: number, -- 1-based position in the GameData rewards list; stable id for the client
	kind: number,
	unlockSec: number,
	claimed: boolean,
	coinAmount: number?, -- COINS only, fixed at session start
	diamondAmount: number?, -- DIAMONDS only
	skipSec: number?, -- TIME_SKIP only
	fixedItemName: string?, -- FIXED_ITEM only
	receivedItemName: string?, -- item kinds, set once claimed
}

type PlayerRewardState = {
	-- owned here rather than read from PlayerData, whose session fields serve saving
	sessionStartTime: number,
	rewards: { PlaytimeRewardState },
}

type PlaytimeRewardManagerFields = {
	playerStates: { [Player]: PlayerRewardState },
	random: Random,
	-- object names by object type then rarity, sorted so rolls are stable per seed; built on first use
	namesByTypeAndRarity: { [string]: { [number]: { string } } },
}

export type PlaytimeRewardManager = typeof(setmetatable({} :: PlaytimeRewardManagerFields, PlaytimeRewardManager))

-- the shape sent to clients (JSON-safe: arrays of records, no sparse numeric keys)
type ClientReward = {
	index: number,
	kind: number,
	unlockSec: number,
	claimed: boolean,
	coinAmount: number?,
	diamondAmount: number?,
	skipSec: number?,
	label: string?,
	rarity: number?,
	itemName: string?,
	displayName: string?,
}

export type ClientPlaytimeRewards = {
	sessionStartTime: number,
	rewards: { ClientReward },
}

function PlaytimeRewardManager.getNamesForTypeAndRarity(self: PlaytimeRewardManager, itemType: string, rarity: number): { string }
	local cached = self.namesByTypeAndRarity[itemType]
	if cached then
		return cached[rarity] or {}
	end

	local byRarity: { [number]: { string } } = {}
	for _, objectName in objectDataStore:getAllObjectNamesByDataKeyValue("type", itemType) do
		local itemRarity = objectDataStore:getObjectDataByName(objectName).rarity or enums.Rarity.COMMON
		byRarity[itemRarity] = byRarity[itemRarity] or {}
		table.insert(byRarity[itemRarity], objectName)
	end
	for _, names in byRarity do
		table.sort(names)
	end
	self.namesByTypeAndRarity[itemType] = byRarity

	return byRarity[rarity] or {}
end

-- rolls the item for an item kind; nil when nothing can be rolled
function PlaytimeRewardManager.rollItemName(self: PlaytimeRewardManager, entry: any): string?
	if entry.kind == kinds.RANDOM_BY_RARITY then
		local names = self:getNamesForTypeAndRarity(enums.ItemType.ObjectTypes[entry.itemType], entry.rarity)
		if #names == 0 then
			warn("PlaytimeRewardManager: no objects of item type", entry.itemType, "rarity", entry.rarity)
			return nil
		end
		return names[self.random:NextInteger(1, #names)]
	elseif entry.kind == kinds.LOOT_TABLE then
		local results = lootTableManager:calculateLootResults(entry.lootTableName)
		local result = results[1] and results[1].result
		if typeof(result) ~= "table" or typeof(result.itemName) ~= "string" then
			warn("PlaytimeRewardManager: loot table", entry.lootTableName, "returned no item result")
			return nil
		end
		return result.itemName
	end

	return nil
end

function PlaytimeRewardManager.resolveRewards(self: PlaytimeRewardManager, playerData: Types.PlayerData): { PlaytimeRewardState }
	local hourlyIncome = incomeManager:getIncomePerSec(playerData) * 3600
	local rewards: { PlaytimeRewardState } = {}

	for index, entry in playtimeData.rewards :: { any } do
		local reward: PlaytimeRewardState = {
			index = index,
			kind = entry.kind,
			unlockSec = entry.unlockSec,
			claimed = false,
			coinAmount = nil,
			diamondAmount = nil,
			skipSec = nil,
			fixedItemName = nil,
			receivedItemName = nil,
		}
		if entry.kind == kinds.COINS then
			reward.coinAmount = PlaytimeRewardMath.computeCoinReward(hourlyIncome, entry.hourlyPercent, entry.minCoins, entry.maxCoins)
		elseif entry.kind == kinds.DIAMONDS then
			reward.diamondAmount = entry.diamondAmount
		elseif entry.kind == kinds.TIME_SKIP then
			reward.skipSec = entry.skipSec
		elseif entry.kind == kinds.FIXED_ITEM then
			reward.fixedItemName = entry.itemName
		end
		table.insert(rewards, reward)
	end

	return rewards
end

function PlaytimeRewardManager.buildClientReward(self: PlaytimeRewardManager, reward: PlaytimeRewardState): ClientReward
	local entry = (playtimeData.rewards :: { any })[reward.index]
	local client: ClientReward = {
		index = reward.index,
		kind = reward.kind,
		unlockSec = reward.unlockSec,
		claimed = reward.claimed,
		coinAmount = reward.coinAmount,
		diamondAmount = reward.diamondAmount,
		skipSec = reward.skipSec,
		label = nil,
		rarity = nil,
		itemName = nil,
		displayName = nil,
	}

	local itemName = reward.fixedItemName or reward.receivedItemName
	if itemName then
		local itemData = objectDataStore:getObjectDataByName(itemName)
		client.itemName = itemName
		if itemData then
			client.displayName = itemData.displayName
			client.rarity = itemData.rarity or enums.Rarity.COMMON
		end
	elseif reward.kind == kinds.RANDOM_BY_RARITY then
		-- the generic label and rarity colour only; the specific item stays hidden until claimed
		client.label = `Random {enums.getPublicName(enums.Rarity, entry.rarity)} {enums.getPublicName(enums.ItemType, entry.itemType)}`
		client.rarity = entry.rarity
	elseif reward.kind == kinds.LOOT_TABLE then
		client.label = LOOT_TABLE_LABEL
	end

	return client
end

function PlaytimeRewardManager.getClientData(self: PlaytimeRewardManager, player: Player): ClientPlaytimeRewards?
	local state = self.playerStates[player]
	if not state then
		return nil
	end

	local rewards: { ClientReward } = {}
	for _, reward in state.rewards do
		table.insert(rewards, self:buildClientReward(reward))
	end

	return {
		sessionStartTime = state.sessionStartTime,
		rewards = rewards,
	}
end

function PlaytimeRewardManager.sendRewards(self: PlaytimeRewardManager, player: Player)
	RemoteEvents.NotifyPlaytimeRewards:FireClient(player, self:getClientData(player))
end

function PlaytimeRewardManager.rejectClaim(self: PlaytimeRewardManager, player: Player, rewardIndex: number, message: string?)
	if message then
		gameController:sendSystemMessageToPlayer(player, message)
	end
	RemoteEvents.NotifyPlaytimeRewardResult:FireClient(player, rewardIndex, false)
end

-- returns the text for the "You received ...!" message, or nil when nothing was delivered (the player has been told)
function PlaytimeRewardManager.grantReward(
	self: PlaytimeRewardManager,
	player: Player,
	playerData: Types.PlayerData,
	reward: PlaytimeRewardState,
	entry: any
): string?
	local grantable: RewardGranter.GrantableReward = {
		kind = reward.kind,
		coinAmount = reward.coinAmount,
		diamondAmount = reward.diamondAmount,
		skipSec = reward.skipSec,
		minCoins = nil,
		itemName = nil,
	}
	if reward.kind ~= kinds.COINS and reward.kind ~= kinds.DIAMONDS and reward.kind ~= kinds.TIME_SKIP then
		grantable.itemName = reward.fixedItemName or self:rollItemName(entry)
		if not grantable.itemName then
			self:rejectClaim(player, reward.index, nil)
			return nil
		end
	end

	local grantedText, failureMessage = RewardGranter.grant(player, playerData, grantable, ACQUISITION_SOURCE)
	if not grantedText then
		self:rejectClaim(player, reward.index, failureMessage)
		return nil
	end

	reward.receivedItemName = grantable.itemName
	return grantedText
end

-- every refusal replies success = false so the client's pending claim always clears
function PlaytimeRewardManager.tryClaim(self: PlaytimeRewardManager, player: Player, rewardIndex: number)
	local playerData = gameController:getPlayerData(player)
	local state = self.playerStates[player]
	if not playerData or not state then
		self:rejectClaim(player, rewardIndex, nil)
		return
	end

	local reward: PlaytimeRewardState? = nil
	for _, candidate in state.rewards do
		if candidate.index == rewardIndex then
			reward = candidate
			break
		end
	end
	if not reward or reward.claimed or workspace:GetServerTimeNow() - state.sessionStartTime < reward.unlockSec then
		self:rejectClaim(player, rewardIndex, nil)
		return
	end

	local grantedText = self:grantReward(player, playerData, reward, (playtimeData.rewards :: { any })[reward.index])
	if not grantedText then
		return
	end

	-- claimed is set only after a successful grant, so a failed one leaves the reward claimable
	reward.claimed = true
	self:sendRewards(player)
	gameController:sendSystemMessageToPlayer(player, `You received {grantedText}!`)
	RemoteEvents.NotifyPlaytimeRewardResult:FireClient(player, rewardIndex, true)
end

function PlaytimeRewardManager.notifyAddPlayer(self: PlaytimeRewardManager, player: Player, playerData: Types.PlayerData)
	self.playerStates[player] = {
		sessionStartTime = workspace:GetServerTimeNow(),
		rewards = self:resolveRewards(playerData),
	}
end

-- a fresh locked set with the session clock restarted (dev reset); the client is told directly
function PlaytimeRewardManager.resetPlayer(self: PlaytimeRewardManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	self:notifyAddPlayer(player, playerData)
	self:sendRewards(player)
end

-- dev tool: pretend the session is older so rewards unlock sooner
function PlaytimeRewardManager.advanceSession(self: PlaytimeRewardManager, player: Player, seconds: number)
	local state = self.playerStates[player]
	if not state then
		return
	end

	state.sessionStartTime -= seconds
	self:sendRewards(player)
end

function PlaytimeRewardManager.notifyRemovePlayer(self: PlaytimeRewardManager, player: Player)
	self.playerStates[player] = nil
end

function PlaytimeRewardManager.new(): PlaytimeRewardManager
	local self = setmetatable({} :: PlaytimeRewardManagerFields, PlaytimeRewardManager)

	self.playerStates = {}
	self.random = Random.new()
	self.namesByTypeAndRarity = {}

	return self
end

function PlaytimeRewardManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = PlaytimeRewardManager.new()

return singleton
