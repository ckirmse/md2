--!strict

-- Daily login bonus: persisted claim progress (PlayerData.dailyLogin) unlocks one reward per day from
-- GameData/Control/DailyLogin (TILE_COUNT entries: days 1 to 7, then the last tile repeats for every later day).
-- Progress is claim-driven and never resets: a day stays claimable until it is claimed, and the next opens DAY_SEC
-- later. The server runs no timers: the client works out claimability from nextClaimTime on its own clock, and the
-- server re-checks on every claim and accepts only the tile that is claimable right now. Every reward is fixed
-- (coins, time skip, fixed item), so what a tile shows is what the claim grants.
local DailyLoginManager = {}
DailyLoginManager.__index = DailyLoginManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local DailyLoginMath = require("@game/ReplicatedStorage/Shared/DailyLoginMath")
local dailyLoginData = require("@game/ServerScriptService/GameData/Control/DailyLogin")
local enums = require("@game/ReplicatedStorage/Shared/Enums")

local RewardGranter = require("./RewardGranter")
local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ACQUISITION_SOURCE = "dailyLogin"

local kinds = enums.PlaytimeRewardKind

type DailyLoginState = DailyLoginMath.DailyLoginState

export type DailyLoginManager = typeof(setmetatable({} :: {}, DailyLoginManager))

-- the record sent to clients (JSON-safe: an array of records, no sparse numeric keys)
type ClientReward = RewardGranter.RewardEntry & {
	tileIndex: number,
}

export type ClientDailyLogin = {
	lastClaimedDay: number,
	nextClaimTime: number,
	rewards: { ClientReward },
}

-- the grantable form of a tile's GameData entry; nil (with a warning) for an entry that cannot be granted
function DailyLoginManager.getGrantableReward(self: DailyLoginManager, tileIndex: number): RewardGranter.GrantableReward?
	local entry: any = (dailyLoginData.rewards :: { any })[tileIndex]
	if type(entry) ~= "table" then
		warn("DailyLoginManager: no reward for tile", tileIndex)
		return nil
	end

	if entry.kind == kinds.COINS then
		return { kind = entry.kind, coinAmount = entry.minCoins, skipSec = nil, minCoins = nil, itemName = nil }
	elseif entry.kind == kinds.TIME_SKIP then
		return { kind = entry.kind, coinAmount = nil, skipSec = entry.skipSec, minCoins = entry.minCoins, itemName = nil }
	elseif entry.kind == kinds.FIXED_ITEM then
		return { kind = entry.kind, coinAmount = nil, skipSec = nil, minCoins = nil, itemName = entry.itemName }
	end

	warn("DailyLoginManager: unsupported reward kind", entry.kind, "for tile", tileIndex)
	return nil
end

function DailyLoginManager.getClientData(self: DailyLoginManager, playerData: Types.PlayerData): ClientDailyLogin
	local state: DailyLoginState = playerData:getDailyLogin()
	local rewards: { ClientReward } = {}

	for tileIndex = 1, DailyLoginMath.TILE_COUNT do
		local reward = self:getGrantableReward(tileIndex)
		if not reward then
			continue
		end

		local entry = RewardGranter.buildRewardEntry(reward) :: ClientReward
		entry.tileIndex = tileIndex
		table.insert(rewards, entry)
	end

	return {
		lastClaimedDay = state.lastClaimedDay,
		nextClaimTime = state.nextClaimTime,
		rewards = rewards,
	}
end

function DailyLoginManager.sendState(self: DailyLoginManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	RemoteEvents.NotifyDailyLogin:FireClient(player, self:getClientData(playerData))
end

-- every refusal replies success = false so the client's pending claim always clears
function DailyLoginManager.rejectClaim(self: DailyLoginManager, player: Player, tileIndex: number, message: string?)
	if message then
		gameController:sendSystemMessageToPlayer(player, message)
	end
	RemoteEvents.NotifyDailyRewardResult:FireClient(player, tileIndex, false)
end

function DailyLoginManager.tryClaim(self: DailyLoginManager, player: Player, tileIndex: number)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		self:rejectClaim(player, tileIndex, nil)
		return
	end

	local now = workspace:GetServerTimeNow()
	local state: DailyLoginState = playerData:getDailyLogin()
	local claimableDay = DailyLoginMath.getClaimableDay(state, now)
	if not claimableDay or DailyLoginMath.getTileForDay(claimableDay) ~= tileIndex then
		self:rejectClaim(player, tileIndex, nil)
		return
	end

	local reward = self:getGrantableReward(tileIndex)
	if not reward then
		self:rejectClaim(player, tileIndex, nil)
		return
	end

	local grantedText, failureMessage = RewardGranter.grant(player, playerData, reward, ACQUISITION_SOURCE)
	if not grantedText then
		-- the day stays claimable
		self:rejectClaim(player, tileIndex, failureMessage)
		return
	end

	playerData:setDailyLogin(DailyLoginMath.applyClaim(state, now))
	self:sendState(player)
	gameController:sendSystemMessageToPlayer(player, `You received {grantedText}!`)
	RemoteEvents.NotifyDailyRewardResult:FireClient(player, tileIndex, true)
end

-- dev tool: opens the next day's reward now instead of waiting out the claim timer
function DailyLoginManager.advanceDay(self: DailyLoginManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local state: DailyLoginState = table.clone(playerData:getDailyLogin())
	state.nextClaimTime = 0
	playerData:setDailyLogin(state)
	self:sendState(player)
end

-- dev tool: back to a brand-new player (day 1 claimable)
function DailyLoginManager.resetPlayer(self: DailyLoginManager, player: Player)
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	playerData:resetDailyLogin()
	self:sendState(player)
end

function DailyLoginManager.new(): DailyLoginManager
	local self = setmetatable({} :: {}, DailyLoginManager)

	return self
end

function DailyLoginManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = DailyLoginManager.new()

return singleton
