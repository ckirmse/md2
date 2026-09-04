--!strict

local ContextualFtueManager = {}
ContextualFtueManager.__index = ContextualFtueManager

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local ContextualFtueCatalog = require("@game/ReplicatedStorage/Shared/ContextualFtueCatalog")

type ContextualFtueManagerFields = {}

export type ContextualFtueManager = typeof(setmetatable({} :: ContextualFtueManagerFields, ContextualFtueManager))

function ContextualFtueManager.tryTrigger(self: ContextualFtueManager, player: Player?, hintId: string): boolean
	if not player then
		return false
	end
	local entry = ContextualFtueCatalog.getEntryById(hintId)
	if not entry then
		warn("ContextualFtueManager: unknown hint id", hintId)
		return false
	end

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return false
	end

	if playerData:hasTriggeredContextualFtue(hintId) then
		return false
	end

	playerData:markContextualFtueTriggered(hintId)

	RemoteEvents.NotifyContextualFtueTriggered:FireClient(player, hintId)

	return true
end

function ContextualFtueManager.new(): ContextualFtueManager
	local self: ContextualFtueManager = setmetatable({} :: ContextualFtueManagerFields, ContextualFtueManager)

	return self
end

function ContextualFtueManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = ContextualFtueManager.new()

return singleton
