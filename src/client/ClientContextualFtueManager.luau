--!strict

local ClientContextualFtueManager = {}
ClientContextualFtueManager.__index = ClientContextualFtueManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local ContextualFtueCatalog = require("@game/ReplicatedStorage/Shared/ContextualFtueCatalog")

local player = game:GetService("Players").LocalPlayer :: Player

-- the gui's shape only exists in Studio, so these are untyped here
local contextualFtueGui: any
local illustration: any
local bodyBackground: any
local title: any
local body: any
local playButton: any

type ClientContextualFtueManagerFields = {
	pendingHintIds: { string },
	isShowing: boolean,
}

export type ClientContextualFtueManager = typeof(setmetatable({} :: ClientContextualFtueManagerFields, ClientContextualFtueManager))

function ClientContextualFtueManager.showEntry(self: ClientContextualFtueManager, entry: ContextualFtueCatalog.Entry)
	illustration.Image = entry.imageAssetId
	title.Text = entry.title
	body.Text = entry.bodyText

	contextualFtueGui.Enabled = true
	self.isShowing = true
end

function ClientContextualFtueManager.showNextPendingIfAny(self: ClientContextualFtueManager)
	if #self.pendingHintIds == 0 then
		return
	end

	local nextHintId = table.remove(self.pendingHintIds, 1) :: string
	self:notifyHintTriggered(nextHintId)
end

function ClientContextualFtueManager.dismiss(self: ClientContextualFtueManager)
	if not self.isShowing then
		return
	end

	self.isShowing = false

	contextualFtueGui.Enabled = false
	self:showNextPendingIfAny()
end

function ClientContextualFtueManager.notifyHintTriggered(self: ClientContextualFtueManager, hintId: string)
	local entry = ContextualFtueCatalog.getEntryById(hintId)
	if not entry then
		warn("ClientContextualFtueManager: unknown hint id", hintId)
		return
	end

	if self.isShowing then
		table.insert(self.pendingHintIds, hintId)
		return
	end

	self:showEntry(entry)
end

function ClientContextualFtueManager.requestTrigger(self: ClientContextualFtueManager, hintId: string)
	RemoteEvents.TryTriggerContextualFtue:FireServer(hintId)
end

function ClientContextualFtueManager.init(self: ClientContextualFtueManager)
	local playerGui = player:WaitForChild("PlayerGui")
	contextualFtueGui = playerGui:WaitForChild("ContextualFtueGui") :: any
	contextualFtueGui.Enabled = false
	contextualFtueGui.DisplayOrder = 130
	local card: any = contextualFtueGui:WaitForChild("Card")
	illustration = card:WaitForChild("Illustration")
	bodyBackground = card:WaitForChild("BodyBackground")
	title = bodyBackground:WaitForChild("Title")
	body = bodyBackground:WaitForChild("Body")
	playButton = card:WaitForChild("PlayButton")

	self.pendingHintIds = {}
	self.isShowing = false

	playButton.Activated:Connect(function()
		self:dismiss()
	end)
end

function ClientContextualFtueManager.new(): ClientContextualFtueManager
	local self = setmetatable({} :: ClientContextualFtueManagerFields, ClientContextualFtueManager)

	self.pendingHintIds = {}
	self.isShowing = false

	return self
end

local singleton = ClientContextualFtueManager.new()

return singleton
