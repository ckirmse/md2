--!strict

-- Daily login bonus: the server sends the saved claim progress (it never resets; the next day opens 24 hours after
-- each claim) with the fixed reward list, at join and after every claim. This manager shows the HUD buttons (Daily,
-- and DailyAlert while a reward can be claimed, which twitches) and the DailyRewards dialog: a grid of one tile per
-- reward plus a footer countdown to the next reward. Each tile is a clone of one of three Studio-authored templates
-- (locked, ready with a Claim button, claimed); a state change rebuilds the grid. The server decides everything; the
-- client only works out what to show from nextClaimTime on its own clock.
local ClientDailyLoginManager = {}
ClientDailyLoginManager.__index = ClientDailyLoginManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local DailyLoginMath = require("@game/ReplicatedStorage/Shared/DailyLoginMath")
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
	tileIndex: number,
}

export type DailyData = {
	lastClaimedDay: number,
	nextClaimTime: number,
	rewards: { RewardEntry },
}

-- the gui's shape only exists in Studio, so its instances are untyped here
type ClientDailyLoginManagerFields = {
	gui: any?,
	dialog: any?,
	tileGrid: any?,
	templates: RewardTileUi.TileTemplates?,
	nextRewardLabel: any?,
	dailyButton: any?,
	alertButton: any?,
	twitcher: ButtonTwitcher.ButtonTwitcher?,
	dailyData: DailyData?,
	random: Random,
	tilesByIndex: { [number]: GuiObject },
	tileStatesByIndex: { [number]: number },
	pendingClaimIndex: number?,
	panelOpen: boolean,
}

export type ClientDailyLoginManager = typeof(setmetatable({} :: ClientDailyLoginManagerFields, ClientDailyLoginManager))

local function getDayLabelText(tileIndex: number): string
	if tileIndex >= DailyLoginMath.TILE_COUNT then
		return `Day {DailyLoginMath.TILE_COUNT}+`
	end

	return `Day {tileIndex}`
end

function ClientDailyLoginManager.getState(self: ClientDailyLoginManager): DailyLoginMath.DailyLoginState?
	local data = self.dailyData
	if not data then
		return nil
	end

	return {
		lastClaimedDay = data.lastClaimedDay,
		nextClaimTime = data.nextClaimTime,
	}
end

-- the tile that can be claimed right now; nil while the next reward is still counting down
function ClientDailyLoginManager.getClaimableTile(self: ClientDailyLoginManager): number?
	local state = self:getState()
	if not state then
		return nil
	end

	local claimableDay = DailyLoginMath.getClaimableDay(state, workspace:GetServerTimeNow())
	if not claimableDay then
		return nil
	end

	return DailyLoginMath.getTileForDay(claimableDay)
end

function ClientDailyLoginManager.getTileState(self: ClientDailyLoginManager, tileIndex: number): number
	if self:getClaimableTile() == tileIndex then
		return RewardTileUi.TILE_STATE_READY
	end

	local data = self.dailyData
	local claimedTile = if data and data.lastClaimedDay > 0 then DailyLoginMath.getTileForDay(data.lastClaimedDay) else 0
	if tileIndex <= claimedTile then
		return RewardTileUi.TILE_STATE_CLAIMED
	end

	return RewardTileUi.TILE_STATE_LOCKED
end

function ClientDailyLoginManager.updateFooter(self: ClientDailyLoginManager)
	local label = self.nextRewardLabel
	if not label then
		return
	end

	local state = self:getState()
	if not state then
		label.Text = ""
		return
	end

	local remaining = DailyLoginMath.getNextRewardRemainingSec(state, workspace:GetServerTimeNow())
	if remaining == nil then
		label.Text = "READY TO CLAIM"
	else
		label.Text = `Next reward available in {PlaytimeRewardMath.formatCountdown(remaining)}`
	end
end

function ClientDailyLoginManager.rebuildTiles(self: ClientDailyLoginManager)
	local grid = self.tileGrid
	local templates = self.templates
	if not grid or not templates then
		return
	end

	RewardTileUi.clearTiles(grid, templates)
	self.tilesByIndex = {}
	self.tileStatesByIndex = {}

	local data = self.dailyData
	if not data then
		return
	end

	for _, reward in data.rewards do
		local tileState = self:getTileState(reward.tileIndex)
		local tile = RewardTileUi.getTemplateForState(templates, tileState):Clone()
		tile.Name = `Reward{reward.tileIndex}`
		tile.LayoutOrder = reward.tileIndex
		tile.Visible = true

		-- the claimed template's DayLabel keeps its authored "Claimed" text
		if tileState ~= RewardTileUi.TILE_STATE_CLAIMED then
			local dayLabel = tile:FindFirstChild("DayLabel") :: TextLabel?
			if dayLabel then
				dayLabel.Text = getDayLabelText(reward.tileIndex)
			end
		end

		RewardTileUi.fillTileContent(tile, reward, tileState)

		if tileState == RewardTileUi.TILE_STATE_READY then
			local claimButton = RewardTileUi.findClaimButton(tile)
			if claimButton then
				local tileIndex = reward.tileIndex
				claimButton.Active = self.pendingClaimIndex ~= tileIndex
				claimButton.Activated:Connect(function()
					self:tryClaim(tileIndex)
				end)
			end
		end

		tile.Parent = grid
		self.tilesByIndex[reward.tileIndex] = tile
		self.tileStatesByIndex[reward.tileIndex] = tileState
	end

	self:updateFooter()
end

function ClientDailyLoginManager.tryClaim(self: ClientDailyLoginManager, tileIndex: number)
	if self.pendingClaimIndex ~= nil or self:getClaimableTile() ~= tileIndex then
		return
	end

	self.pendingClaimIndex = tileIndex
	local tile = self.tilesByIndex[tileIndex]
	local claimButton = if tile then RewardTileUi.findClaimButton(tile) else nil
	if claimButton then
		claimButton.Active = false
	end

	RemoteEvents.TryClaimDailyReward:FireServer(tileIndex)

	task.delay(PENDING_TIMEOUT_SEC, function()
		if self.pendingClaimIndex == tileIndex then
			self.pendingClaimIndex = nil
			if self.panelOpen then
				self:rebuildTiles()
			end
		end
	end)
end

-- the server's answer to a claim; every refusal comes back with isSuccess false
function ClientDailyLoginManager.notifyClaimResult(self: ClientDailyLoginManager, tileIndex: any, isSuccess: any)
	if self.pendingClaimIndex == tileIndex then
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
function ClientDailyLoginManager.refreshTiles(self: ClientDailyLoginManager)
	for tileIndex in self.tilesByIndex do
		if self:getTileState(tileIndex) ~= self.tileStatesByIndex[tileIndex] then
			-- the next day just opened
			self:rebuildTiles()
			return
		end
	end

	self:updateFooter()
end

function ClientDailyLoginManager.updateHudButtons(self: ClientDailyLoginManager)
	local dailyButton = self.dailyButton
	local alertButton = self.alertButton
	if not dailyButton or not alertButton then
		return
	end

	local isClaimable = self:getClaimableTile() ~= nil
	dailyButton.Visible = not isClaimable
	alertButton.Visible = isClaimable

	local twitcher = self.twitcher
	if isClaimable and twitcher then
		twitcher:updateIfNeeded()
	end
end

function ClientDailyLoginManager.getGuiRoot(self: ClientDailyLoginManager): any
	return self.dialog
end

function ClientDailyLoginManager.getHudElements(self: ClientDailyLoginManager): { number }
	return {}
end

function ClientDailyLoginManager.doesWantBlur(self: ClientDailyLoginManager): boolean
	return false
end

function ClientDailyLoginManager.openPanel(self: ClientDailyLoginManager)
	local gui = self.gui
	if self.panelOpen then
		return
	end
	if not gui then
		warn("ClientDailyLoginManager: the DailyRewards gui was not set up at startup, see the startup warning")
		return
	end
	if not self.dailyData then
		warn("ClientDailyLoginManager: no daily login data has arrived from the server")
		return
	end

	self.panelOpen = true
	self:rebuildTiles()
	gui.Enabled = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientDailyLoginManager.closePanel(self: ClientDailyLoginManager)
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

-- called by the overlay tracker when another overlay takes over
function ClientDailyLoginManager.notifyForceEnd(self: ClientDailyLoginManager)
	self:closePanel()
end

function ClientDailyLoginManager.notifyClickOutside(self: ClientDailyLoginManager)
	self:closePanel()
end

-- the saved progress and reward list from the server: in the init data, and again after every claim or dev change
function ClientDailyLoginManager.setDailyData(self: ClientDailyLoginManager, data: any)
	if type(data) == "table" and type(data.rewards) == "table" and type(data.lastClaimedDay) == "number" and type(data.nextClaimTime) == "number" then
		self.dailyData = data :: DailyData
	else
		self.dailyData = nil
	end

	if self.panelOpen then
		if self.dailyData then
			self:rebuildTiles()
		else
			self:closePanel()
		end
	end
	self:updateHudButtons()
end

-- the HUD buttons live in the main HUD ScreenGui, which ScreenGuiManager owns and wires up
function ClientDailyLoginManager.setHudButtons(self: ClientDailyLoginManager, dailyButton: any, alertButton: any)
	self.dailyButton = dailyButton
	self.alertButton = alertButton
	self.twitcher = ButtonTwitcher.new(alertButton)
	alertButton.Visible = false
	self:updateHudButtons()
end

function ClientDailyLoginManager.init(self: ClientDailyLoginManager)
	RemoteEvents.NotifyDailyLogin.OnClientEvent:Connect(function(data)
		self:setDailyData(data)
	end)
	RemoteEvents.NotifyDailyRewardResult.OnClientEvent:Connect(function(tileIndex, isSuccess)
		self:notifyClaimResult(tileIndex, isSuccess)
	end)

	-- the countdown and the unlock checks only need to run once a second
	ClientTicker.every(1, function()
		self:updateHudButtons()
		if self.panelOpen then
			self:refreshTiles()
		end
	end)

	-- authored in Studio, so a missing one must not hang client startup
	local playerGui = player:FindFirstChild("PlayerGui") :: Instance
	local gui: any = playerGui:FindFirstChild("DailyRewards")
	if not gui then
		warn("ClientDailyLoginManager: DailyRewards gui missing from PlayerGui; the daily rewards dialog is disabled")
		return
	end

	local dialog: any = gui:FindFirstChild("Dialog")
	local tileGrid: any = dialog and dialog:FindFirstChild("TileGrid")
	local title: any = dialog and dialog:FindFirstChild("Title")
	local exitButton: any = title and title:FindFirstChild("Exit")
	if not tileGrid or not tileGrid:FindFirstChild("TileTemplate") or not tileGrid:FindFirstChild("TileTemplateReady") or not tileGrid:FindFirstChild("TileTemplateClaimed") then
		warn("ClientDailyLoginManager: DailyRewards needs Dialog/TileGrid with TileTemplate, TileTemplateReady and TileTemplateClaimed; the dialog is disabled")
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
	self.nextRewardLabel = dialog:FindFirstChild("NextReward")
	if not self.nextRewardLabel then
		warn("ClientDailyLoginManager: DailyRewards has no Dialog/NextReward label; the countdown is not shown")
	end

	if exitButton then
		exitButton.Activated:Connect(function()
			self:closePanel()
		end)
	else
		warn("ClientDailyLoginManager: DailyRewards has no Dialog/Title/Exit button")
	end
end

function ClientDailyLoginManager.new(): ClientDailyLoginManager
	local self = setmetatable({} :: ClientDailyLoginManagerFields, ClientDailyLoginManager)

	self.gui = nil
	self.dialog = nil
	self.tileGrid = nil
	self.templates = nil
	self.nextRewardLabel = nil
	self.dailyButton = nil
	self.alertButton = nil
	self.twitcher = nil
	self.dailyData = nil
	self.random = Random.new()
	self.tilesByIndex = {}
	self.tileStatesByIndex = {}
	self.pendingClaimIndex = nil
	self.panelOpen = false

	return self
end

local singleton = ClientDailyLoginManager.new()

return singleton
