--!strict

local ClientGiftingManager = {}
ClientGiftingManager.__index = ClientGiftingManager

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")
local screenGuiManager: Types.ScreenGuiManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local player = Players.LocalPlayer :: Player

type ClientGiftingManagerFields = {
	gui: any?,
	scroll: any,
	playerTemplate: any,
	rows: { any },
	activeProductId: number?,
	pendingProductId: number?,
	panelOpen: boolean,
	isReady: boolean,
}

export type ClientGiftingManager = typeof(setmetatable({} :: ClientGiftingManagerFields, ClientGiftingManager))

function ClientGiftingManager.isGiftingEnabled(self: ClientGiftingManager): boolean
	return self.isReady
end

function ClientGiftingManager.getGuiRoot(self: ClientGiftingManager): any
	return self.gui
end

function ClientGiftingManager.getHudElements(self: ClientGiftingManager)
	return {}
end

function ClientGiftingManager.notifyForceEnd(self: ClientGiftingManager)
	self:closePanel()
end

function ClientGiftingManager.notifyClickOutside(self: ClientGiftingManager)
	self:notifyForceEnd()
end

function ClientGiftingManager.doesWantBlur(self: ClientGiftingManager): boolean
	return false
end

function ClientGiftingManager.closePanel(self: ClientGiftingManager)
	if not self.panelOpen then
		return
	end
	self.panelOpen = false

	local gui: any = self.gui
	gui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientGiftingManager.selectRecipient(self: ClientGiftingManager, recipientUserId: number)
	local productId = self.activeProductId
	if not productId then
		return
	end

	self:closePanel()

	RemoteEvents.TryBeginGift:FireServer(productId, recipientUserId)
	self.pendingProductId = productId

	local isSuccess, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not isSuccess then
		warn("ClientGiftingManager: error prompting for robux purchase", errorMessage)
		self.pendingProductId = nil
		RemoteEvents.TryClearGift:FireServer()
	end
end

function ClientGiftingManager.fillAvatarImage(self: ClientGiftingManager, avatarImage: any, userId: number)
	task.spawn(function()
		local isSuccess, image = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if not isSuccess then
			warn("ClientGiftingManager: failed to load avatar thumbnail for", userId, image)
			return
		end

		-- the row may have been cleared while the thumbnail loaded
		if avatarImage.Parent then
			avatarImage.Image = image
		end
	end)
end

function ClientGiftingManager.clearRows(self: ClientGiftingManager)
	for _, row in self.rows do
		row:Destroy()
	end
	self.rows = {}
end

function ClientGiftingManager.addRow(self: ClientGiftingManager, otherPlayer: Player, layoutOrder: number)
	local row: any = self.playerTemplate:Clone()
	row.Name = `Player_{otherPlayer.UserId}`
	row.LayoutOrder = layoutOrder
	row.Visible = true

	local nameText: any = row:FindFirstChild("PlayerName")
	if nameText then
		nameText.Text = otherPlayer.DisplayName
	end

	local avatarImage: any = row:FindFirstChild("PlayerAvatar")
	if avatarImage then
		self:fillAvatarImage(avatarImage, otherPlayer.UserId)
	end

	local selectButton: any = row:FindFirstChild("Select")
	if selectButton then
		selectButton.Activated:Connect(function()
			self:selectRecipient(otherPlayer.UserId)
		end)
	else
		warn("ClientGiftingManager: Select button missing from the player row")
	end

	row.Parent = self.scroll
	table.insert(self.rows, row)
end

-- the list is rebuilt on every open, so players who joined or left since are always right
function ClientGiftingManager.open(self: ClientGiftingManager, productId: number)
	local gui: any = self.gui
	if not self.isReady or not gui then
		warn("ClientGiftingManager: gifting is not set up, check the Gifting gui")
		return
	end

	local otherPlayers: { Player } = {}
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			table.insert(otherPlayers, otherPlayer)
		end
	end
	if #otherPlayers == 0 then
		screenGuiManager:showSystemMessage("There is no one else here to send a gift to")
		return
	end

	table.sort(otherPlayers, function(a: Player, b: Player): boolean
		return a.DisplayName < b.DisplayName
	end)

	self.activeProductId = productId
	self:clearRows()
	for index, otherPlayer in otherPlayers do
		self:addRow(otherPlayer, index)
	end

	self.panelOpen = true
	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
	gui.Enabled = true
end

function ClientGiftingManager.notifyGiftReceived(self: ClientGiftingManager, fromDisplayName: any, dealTitle: any)
	if type(fromDisplayName) ~= "string" or type(dealTitle) ~= "string" then
		warn("ClientGiftingManager: malformed NotifyGiftReceived arguments")
		return
	end

	screenGuiManager:showSystemMessage(`{fromDisplayName} sent you a gift: {dealTitle}!`)
end

function ClientGiftingManager.init(self: ClientGiftingManager)
	-- authored in Studio, so a missing one must not hang client startup
	local playerGui = player:FindFirstChild("PlayerGui") :: Instance
	local gui: any = playerGui:FindFirstChild("Gifting")
	if not gui then
		warn("ClientGiftingManager: Gifting gui missing from PlayerGui; gifting is disabled")
		return
	end

	local main: any = gui:FindFirstChild("Main")
	local scroll: any = main and main:FindFirstChild("Scroll")
	local playerTemplate: any = scroll and scroll:FindFirstChild("PlayerTemplate")
	if not playerTemplate then
		warn("ClientGiftingManager: Gifting needs Main/Scroll/PlayerTemplate; gifting is disabled")
		return
	end

	gui.ResetOnSpawn = false
	gui.Enabled = false
	playerTemplate.Visible = false
	self.gui = gui
	self.scroll = scroll
	self.playerTemplate = playerTemplate

	local title: any = main:FindFirstChild("Title")
	local exitButton: any = title and title:FindFirstChild("Exit")
	if exitButton then
		exitButton.Activated:Connect(function()
			self:closePanel()
		end)
	end

	-- a gift whose purchase prompt was cancelled must not stay pending on the server
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
		if userId ~= player.UserId or productId ~= self.pendingProductId then
			return
		end

		self.pendingProductId = nil
		if not isPurchased then
			RemoteEvents.TryClearGift:FireServer()
		end
	end)

	self.isReady = true
end

function ClientGiftingManager.new(): ClientGiftingManager
	local self = setmetatable({} :: ClientGiftingManagerFields, ClientGiftingManager)

	self.gui = nil
	self.rows = {}
	self.activeProductId = nil
	self.pendingProductId = nil
	self.panelOpen = false
	self.isReady = false

	return self
end

function ClientGiftingManager.initClass(deps: any)
	screenGuiManager = deps.screenGuiManager
end

local singleton = ClientGiftingManager.new()

return singleton
