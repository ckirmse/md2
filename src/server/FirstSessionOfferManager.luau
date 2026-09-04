--!strict

local FirstSessionOfferManager = {}
FirstSessionOfferManager.__index = FirstSessionOfferManager

local Types = require("./Types")
local itemManager = require("./ItemManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local plotsManager = require("./PlotsManager")
local Timer = require("./Timer")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Fixtures = GameAssets:WaitForChild("Fixtures")
-- the balloon fixture is a Model
local DragonBalloon = Fixtures:WaitForChild("DragonBalloon") :: Model

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")

local firstSessionOfferData = require("@game/ServerScriptService/GameData/Control/FirstSessionOffer")

type FirstSessionOfferManagerFields = {}

export type FirstSessionOfferManager = typeof(setmetatable({} :: FirstSessionOfferManagerFields, FirstSessionOfferManager))

function FirstSessionOfferManager.getDefaultFirstSessionOfferState(self: FirstSessionOfferManager): any
	return {
		state = enums.FirstSessionOfferState.NONE,
		plotLocation = firstSessionOfferData.plotLocation,
	}
end

function FirstSessionOfferManager.mapFirstSessionOfferStateFromSaveData(self: FirstSessionOfferManager, player: Player, firstSessionOfferState: any): any
	if firstSessionOfferState.state == enums.FirstSessionOfferState.WAITING then
		return {
			state = enums.FirstSessionOfferState.COMPLETE,
		}
	end

	return firstSessionOfferState
end

function FirstSessionOfferManager.setRedeemable(self: FirstSessionOfferManager, player: Player)
	local playerData = gameController:getPlayerData(player)

	local firstSessionOfferState = playerData:getFirstSessionOfferState()
	firstSessionOfferState.state = enums.FirstSessionOfferState.REDEEMABLE

	playerData:setFirstSessionOfferState(firstSessionOfferState)
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, firstSessionOfferState)

	analyticsManager:logEvent(player, analyticsManager.Events.FirstSessionOfferRedeemable, {})
end

function FirstSessionOfferManager.startOffer(self: FirstSessionOfferManager, player: Player)
	local playerData = gameController:getPlayerData(player)

	local firstSessionOfferState = playerData:getFirstSessionOfferState()
	firstSessionOfferState.state = enums.FirstSessionOfferState.WAITING
	firstSessionOfferState.completeTime = workspace:GetServerTimeNow() + 15 * 60

	playerData:setFirstSessionOfferState(firstSessionOfferState)
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, firstSessionOfferState)

	local now = workspace:GetServerTimeNow()
	local duration = firstSessionOfferState.completeTime - now
	Timer.new(duration,
		function()
			-- see if player is still around
			playerData = gameController:getPlayerData(player)
			if not playerData then
				return
			end

			self:setRedeemable(player)
		end
	)

	analyticsManager:logEvent(player, analyticsManager.Events.FirstSessionOfferStarted, {})

end

function FirstSessionOfferManager.canRedeem(self: FirstSessionOfferManager, player: Player): boolean
	local playerData = gameController:getPlayerData(player)

	local firstSessionOfferState = playerData:getFirstSessionOfferState()
	return firstSessionOfferState.state == enums.FirstSessionOfferState.REDEEMABLE
end

function FirstSessionOfferManager.redeem(self: FirstSessionOfferManager, player: Player)
	local playerData = gameController:getPlayerData(player)

	local firstSessionOfferState = playerData:getFirstSessionOfferState()
	firstSessionOfferState.state = enums.FirstSessionOfferState.COMPLETE

	playerData:setFirstSessionOfferState(firstSessionOfferState)
	RemoteEvents.NotifyFirstSessionOfferState:FireClient(player, firstSessionOfferState)

	local dragon = itemManager:createItem("Green Dragon Level 4", player.UserId) :: Types.ShadowDragon?
	if not dragon then
		warn("first session offer failed to create dragon")
		return
	end
	local obj = dragon:getObj()

	local plotCFrame = CFrame.fromEulerAnglesXYZ(0, math.rad(90), 0) + Vector3.new(firstSessionOfferData.plotLocation[1], DragonBalloon:GetPivot().Position.Y, firstSessionOfferData.plotLocation[2])


	local cframe = plotsManager:getWorldCFrameFromPlotCFrameForUserId(plotCFrame, player.UserId)
	obj:PivotTo(cframe)
	obj.Parent = workspace

	local duration = 2
	utils.pulseAttribute(obj, Attributes.ANIMATION_HIGHLIGHT_FADE_OUT, string.format("%i 255 255 255", duration))
	local burstCount = 10
	utils.pulseAttribute(obj, Attributes.ANIMATION_MERGE_PARTICLES, string.format("%i", burstCount))

	dragon:notifyShouldMoveToIdleAtCurrentLocation()

	analyticsManager:logEvent(player, analyticsManager.Events.FirstSessionOfferRedeemed, {})

end


function FirstSessionOfferManager.new(): FirstSessionOfferManager
	local self: FirstSessionOfferManager = setmetatable({} :: FirstSessionOfferManagerFields, FirstSessionOfferManager)

	return self
end

function FirstSessionOfferManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = FirstSessionOfferManager.new()

return singleton
