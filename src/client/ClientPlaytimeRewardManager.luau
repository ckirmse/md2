--!strict

-- Playtime rewards: the server sends the session's reward set (at join and after every claim); this manager shows
-- the HUD button (a countdown to the next unlock while nothing can be claimed, an icon and a "!" badge with a
-- twitch when something can) and the PlaytimeRewards dialog, a grid of tiles that each count down, show a Claim
-- button once unlocked, and gray out once claimed. The server decides everything; the client's clock is only
-- used to drive the display.
local ClientPlaytimeRewardManager = {}
ClientPlaytimeRewardManager.__index = ClientPlaytimeRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local PlaytimeRewardMath = require("@game/ReplicatedStorage/Shared/PlaytimeRewardMath")

local ButtonTwitcher = require("./ButtonTwitcher")
local ClaimFeedback = require("./ClaimFeedback")
local ClientTicker = require("./ClientTicker")
local overlayTracker = require("./OverlayTracker")
local RewardTileUi = require("./RewardTileUi")
local Types = require("./Types")

local player = game:GetService("Players").LocalPlayer :: Player

local DISPLAY_ORDER = 130
-- the server answers every claim; this only unlocks a button whose request was dropped
local PENDING_TIMEOUT_SEC = 5

export type RewardEntry = RewardTileUi.RewardContent & {
	index: number,
	unlockSec: number,
	claimed: boolean,
}

export type RewardData = {
	sessionStartTime: number,
	rewards: { RewardEntry },
}

-- the gui's shape only exists in Studio, so its instances are untyped here
type ClientPlaytimeRewardManagerFields = {
	gui: any?,
	dialog: any?,
	tileGrid: any?,
	templates: RewardTileUi.TileTemplates?,
	hudButton: any?,
	timerLabel: any?,
	iconLabel: any?,
	alertLabel: any?,
	twitcher: ButtonTwitcher.ButtonTwitcher?,
	rewardData: RewardData?,
	random: Random,
	tilesByIndex: { [number]: GuiObject },
	tileStatesByIndex: { [number]: number },
	pendingClaimIndex: number?,
	panelOpen: boolean,
}

export type ClientPlaytimeRewardManager = typeof(setmetatable({} :: ClientPlaytimeRewardManagerFields, ClientPlaytimeRewardManager))

function ClientPlaytimeRewardManager.getElapsedSec(self: ClientPlaytimeRewardManager): number
	local data = self.rewardData
	if not data then
		return 0
	end

	return workspace:GetServerTimeNow() - data.sessionStartTime
end

-- seconds until the soonest locked reward unlocks; nil when none is waiting
function ClientPlaytimeRewardManager.getNextUnlockRemainingSec(self: ClientPlaytimeRewardManager): number?
	local data = self.rewardData
	if not data then
		return nil
	end

	local elapsed = self:getElapsedSec()
	local best: number? = nil
	for _, reward in data.rewards do
		if reward.claimed then
			continue
		end
		local remaining = reward.unlockSec - elapsed
		if remaining > 0 and (best == nil or remaining < best) then
			best = remaining
		end
	end

	return best
end

function ClientPlaytimeRewardManager.hasClaimableReward(self: ClientPlaytimeRewardManager): boolean
	local data = self.rewardData
	if not data then
		return false
	end

	local elapsed = self:getElapsedSec()
	for _, reward in data.rewards do
		if not reward.claimed and elapsed >= reward.unlockSec then
			return true
		end
	end

	return false
end

function ClientPlaytimeRewardManager.getTileState(self: ClientPlaytimeRewardManager, reward: RewardEntry): number
	if reward.claimed then
		return RewardTileUi.TILE_STATE_CLAIMED
	end
	if self:getElapsedSec() >= reward.unlockSec then
		return RewardTileUi.TILE_STATE_READY
	end

	return RewardTileUi.TILE_STATE_LOCKED
end

function ClientPlaytimeRewardManager.updateLockedTileTimer(self: ClientPlaytimeRewardManager, tile: GuiObject, reward: RewardEntry)
	local timerLabel = tile:FindFirstChild("Timer") :: TextLabel?
	if not timerLabel then
		return
	end

	timerLabel.Text = PlaytimeRewardMath.formatCountdown(math.max(reward.unlockSec - self:getElapsedSec(), 0))
end

function ClientPlaytimeRewardManager.rebuildTiles(self: ClientPlaytimeRewardManager)
	local grid = self.tileGrid
	local templates = self.templates
	if not grid or not templates then
		return
	end

	RewardTileUi.clearTiles(grid, templates)
	self.tilesByIndex = {}
	self.tileStatesByIndex = {}

	local data = self.rewardData
	if not data then
		return
	end

	local layoutOrderByIndex: { [number]: number } = {}
	for rank, rewardIndex in PlaytimeRewardMath.getSortedOrder(data.rewards) do
		layoutOrderByIndex[rewardIndex] = rank
	end

	for _, reward in data.rewards do
		local tileState = self:getTileState(reward)
		local tile = RewardTileUi.getTemplateForState(templates, tileState):Clone()
		tile.Name = `Reward{reward.index}`
		tile.LayoutOrder = layoutOrderByIndex[reward.index] or reward.index
		tile.Visible = true

		RewardTileUi.fillTileContent(tile, reward, tileState)

		if tileState == RewardTileUi.TILE_STATE_LOCKED then
			self:updateLockedTileTimer(tile, reward)
		elseif tileState == RewardTileUi.TILE_STATE_READY then
			local claimButton = RewardTileUi.findClaimButton(tile)
			if claimButton then
				local rewardIndex = reward.index
				claimButton.Active = self.pendingClaimIndex ~= rewardIndex
				claimButton.Activated:Connect(function()
					self:tryClaim(rewardIndex)
				end)
			end
		end

		tile.Parent = grid
		self.tilesByIndex[reward.index] = tile
		self.tileStatesByIndex[reward.index] = tileState
	end
end

function ClientPlaytimeRewardManager.tryClaim(self: ClientPlaytimeRewardManager, rewardIndex: number)
	local data = self.rewardData
	if not data or self.pendingClaimIndex ~= nil then
		return
	end

	for _, reward in data.rewards do
		if reward.index ~= rewardIndex then
			continue
		end
		if reward.claimed or self:getElapsedSec() < reward.unlockSec then
			return
		end

		self.pendingClaimIndex = rewardIndex
		local tile = self.tilesByIndex[rewardIndex]
		local claimButton = if tile then RewardTileUi.findClaimButton(tile) else nil
		if claimButton then
			claimButton.Active = false
		end

		RemoteEvents.TryClaimPlaytimeReward:FireServer(rewardIndex)

		task.delay(PENDING_TIMEOUT_SEC, function()
			if self.pendingClaimIndex == rewardIndex then
				self.pendingClaimIndex = nil
				if self.panelOpen then
					self:rebuildTiles()
				end
			end
		end)
		return
	end
end

-- the server's answer to a claim; every refusal comes back with isSuccess false
function ClientPlaytimeRewardManager.notifyClaimResult(self: ClientPlaytimeRewardManager, rewardIndex: any, isSuccess: any)
	if self.pendingClaimIndex == rewardIndex then
		self.pendingClaimIndex = nil
	end

	if isSuccess == true then
		local gui = self.gui
		if self.panelOpen and gui then
			ClaimFeedback.play(gui, self.random)
		end
	elseif self.panelOpen then
		-- re-enable the Claim button
		self:rebuildTiles()
	end
end

-- called every second while the dialog is open
function ClientPlaytimeRewardManager.refreshTimers(self: ClientPlaytimeRewardManager)
	local data = self.rewardData
	if not data then
		return
	end

	for _, reward in data.rewards do
		if self:getTileState(reward) ~= self.tileStatesByIndex[reward.index] then
			-- a tile just unlocked
			self:rebuildTiles()
			return
		end
	end

	for _, reward in data.rewards do
		if self.tileStatesByIndex[reward.index] ~= RewardTileUi.TILE_STATE_LOCKED then
			continue
		end
		local tile = self.tilesByIndex[reward.index]
		if tile then
			self:updateLockedTileTimer(tile, reward)
		end
	end
end

function ClientPlaytimeRewardManager.updateHudButton(self: ClientPlaytimeRewardManager)
	if not self.hudButton then
		return
	end

	local isClaimable = self:hasClaimableReward()

	local iconLabel = self.iconLabel
	if iconLabel then
		iconLabel.Visible = isClaimable
	end

	local alertLabel = self.alertLabel
	if alertLabel then
		alertLabel.Visible = isClaimable
	end

	local timerLabel = self.timerLabel
	if timerLabel then
		local remaining = self:getNextUnlockRemainingSec()
		if remaining and not isClaimable then
			timerLabel.Text = PlaytimeRewardMath.formatCountdown(remaining)
			timerLabel.Visible = true
		else
			timerLabel.Visible = false
		end
	end

	local twitcher = self.twitcher
	if isClaimable and twitcher then
		twitcher:updateIfNeeded()
	end
end

function ClientPlaytimeRewardManager.getGuiRoot(self: ClientPlaytimeRewardManager): any
	return self.dialog
end

function ClientPlaytimeRewardManager.getHudElements(self: ClientPlaytimeRewardManager): { number }
	return {}
end

function ClientPlaytimeRewardManager.doesWantBlur(self: ClientPlaytimeRewardManager): boolean
	return false
end

function ClientPlaytimeRewardManager.openPanel(self: ClientPlaytimeRewardManager)
	local gui = self.gui
	if self.panelOpen then
		return
	end
	if not gui then
		warn("ClientPlaytimeRewardManager: the PlaytimeRewards gui was not set up at startup, see the startup warning")
		return
	end
	if not self.rewardData then
		warn("ClientPlaytimeRewardManager: no playtime rewards have arrived from the server")
		return
	end

	self.panelOpen = true
	self:rebuildTiles()
	gui.Enabled = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientPlaytimeRewardManager.closePanel(self: ClientPlaytimeRewardManager)
	if not self.panelOpen then
		return
	end
	self.panelOpen = false

	local gui = self.gui
	if gui then
		gui.Enabled = false
	end

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientPlaytimeRewardManager.togglePanel(self: ClientPlaytimeRewardManager)
	if self.panelOpen then
		self:closePanel()
	else
		self:openPanel()
	end
end

-- called by the overlay tracker when another overlay takes over; it has already ended this one
function ClientPlaytimeRewardManager.notifyForceEnd(self: ClientPlaytimeRewardManager)
	self:closePanel()
end

function ClientPlaytimeRewardManager.notifyClickOutside(self: ClientPlaytimeRewardManager)
	self:closePanel()
end

-- the reward set from the server: in the init data, and again after every claim or reset
function ClientPlaytimeRewardManager.setRewardData(self: ClientPlaytimeRewardManager, data: any)
	if type(data) == "table" and type(data.rewards) == "table" and type(data.sessionStartTime) == "number" then
		self.rewardData = data :: RewardData
	else
		self.rewardData = nil
	end

	if self.panelOpen then
		if self.rewardData then
			self:rebuildTiles()
		else
			self:closePanel()
		end
	end
	self:updateHudButton()
end

-- the HUD button lives in the main HUD ScreenGui, which ScreenGuiManager owns and wires up
function ClientPlaytimeRewardManager.setHudButton(self: ClientPlaytimeRewardManager, button: any)
	self.hudButton = button
	self.twitcher = ButtonTwitcher.new(button)
	self.timerLabel = button:FindFirstChild("Timer")
	self.iconLabel = button:FindFirstChild("Icon")
	self.alertLabel = button:FindFirstChild("Alert")
	self:updateHudButton()
end

function ClientPlaytimeRewardManager.init(self: ClientPlaytimeRewardManager)
	RemoteEvents.NotifyPlaytimeRewards.OnClientEvent:Connect(function(data)
		self:setRewardData(data)
	end)
	RemoteEvents.NotifyPlaytimeRewardResult.OnClientEvent:Connect(function(rewardIndex, isSuccess)
		self:notifyClaimResult(rewardIndex, isSuccess)
	end)

	-- the countdown and the unlock checks only need to run once a second
	ClientTicker.every(1, function()
		self:updateHudButton()
		if self.panelOpen then
			self:refreshTimers()
		end
	end)

	-- authored in Studio, so a missing one must not hang client startup
	local playerGui = player:WaitForChild("PlayerGui")
	local gui: any = playerGui:WaitForChild("PlaytimeRewards", 10)
	if not gui then
		warn("ClientPlaytimeRewardManager: PlaytimeRewards gui missing from PlayerGui; the playtime rewards dialog is disabled")
		return
	end

	local dialog: any = gui:FindFirstChild("Dialog")
	local tileGrid: any = dialog and dialog:FindFirstChild("TileGrid")
	local title: any = dialog and dialog:FindFirstChild("Title")
	local exitButton: any = title and title:FindFirstChild("Exit")
	if not tileGrid or not tileGrid:FindFirstChild("TileTemplate") or not tileGrid:FindFirstChild("TileTemplateReady") or not tileGrid:FindFirstChild("TileTemplateClaimed") then
		warn("ClientPlaytimeRewardManager: PlaytimeRewards needs Dialog/TileGrid with TileTemplate, TileTemplateReady and TileTemplateClaimed; the dialog is disabled")
		return
	end

	-- the tiles are cloned from templates at runtime, so a respawn must not recreate the gui from StarterGui
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = DISPLAY_ORDER
	self.gui = gui
	self.dialog = dialog
	self.tileGrid = tileGrid
	self.templates = RewardTileUi.findTemplates(tileGrid)

	if exitButton then
		exitButton.Activated:Connect(function()
			self:closePanel()
		end)
	else
		warn("ClientPlaytimeRewardManager: PlaytimeRewards has no Dialog/Title/Exit button")
	end
end

function ClientPlaytimeRewardManager.new(): ClientPlaytimeRewardManager
	local self = setmetatable({} :: ClientPlaytimeRewardManagerFields, ClientPlaytimeRewardManager)

	self.gui = nil
	self.dialog = nil
	self.tileGrid = nil
	self.templates = nil
	self.hudButton = nil
	self.timerLabel = nil
	self.iconLabel = nil
	self.alertLabel = nil
	self.twitcher = nil
	self.rewardData = nil
	self.random = Random.new()
	self.tilesByIndex = {}
	self.tileStatesByIndex = {}
	self.pendingClaimIndex = nil
	self.panelOpen = false

	return self
end

local singleton = ClientPlaytimeRewardManager.new()

return singleton
