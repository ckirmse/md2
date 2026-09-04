--!strict

local FtueManager = {}
FtueManager.__index = FtueManager

local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local plotsManager = require("./PlotsManager")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local FtueSteps = require("@game/ReplicatedStorage/Shared/FtueSteps")
local PivotToIndependentTween = require("@game/ReplicatedStorage/Shared/PivotToIndependentTween")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")

type FtueManagerFields = {}

export type FtueManager = typeof(setmetatable({} :: FtueManagerFields, FtueManager))

function FtueManager.getDefaultFtueProgress(self: FtueManager): any
	return {
		isEnabled = true,
		stepName = nil,
		setupStepNames = {},
	}
end

function FtueManager.getDisabledFtueProgress(self: FtueManager): any
	return {
		isEnabled = false,
		stepName = nil,
	}
end

function FtueManager.isInFtue(self: FtueManager, ftueProgress: any): boolean
	return ftueProgress.isEnabled
end

function FtueManager.mapFtueProgressFromSaveData(self: FtueManager, ftueProgress: any): any
	if not ftueProgress.isEnabled then
		return ftueProgress
	end

	if not ftueProgress.stepName then
		return ftueProgress
	end

	if not FtueSteps.validateStepName(ftueProgress.stepName) then
		return self:getDefaultFtueProgress()
	end

	local stepName = FtueSteps:mapStepNameFromSaveData(ftueProgress.stepName)
	--print("loading ftue state going from", ftueProgress.stepName, "to", stepName)
	ftueProgress.stepName = stepName
	return ftueProgress
end


function FtueManager.setupStep(self: FtueManager, player: Player, stepName: string?)
	-- an unknown step name crashed here before typing too
	local stepData = FtueSteps.getStepDataForStepName(stepName) :: any

	for _, setup in stepData.setup do
		if setup.type == enums.FtueSetupType.NONE then
			-- pass
		elseif setup.type == enums.FtueSetupType.CREATE_AND_DROP_ITEM then
			local itemName = setup.itemName
			local item = itemManager:createItem(itemName, player.UserId)
			if not item then
				warn("ftue setup failed to create item", itemName)
				continue
			end
			local location = plotsManager:getWorldPositionFromPlotPositionForUserId(Vector3.new(setup.plotLocation[1], 0, setup.plotLocation[2]), player.UserId)
			if not location then
				warn("ftue setup has no world location for player", player)
				continue
			end
			local position = utils.getGroundPositionForLocation(location) + Vector3.new(0, item:getPart().Size.Y / 2, 0)

			local spawnPosition = position + Vector3.new(0, 500, 0)
			item:getObj():PivotTo(CFrame.new(spawnPosition))
			item:setPreventSettling()
			item:getObj().Parent = workspace

			-- highlights don't always immediately work, so delay...
			-- xxx ideally should put this on client
			local delayTime = 0.05
			task.delay(delayTime,
				function()
					if not gameController:getPlayerData(player) then
						-- player is gone
						return
					end

					local startPosition = position + Vector3.new(0, 30, 0)
					item:getObj():PivotTo(CFrame.new(startPosition))

					item:createAndDecayHighlight()

					local tween = PivotToIndependentTween(item:getObj(), setup.fallDuration or 1.5, "linear", "linear", "outBounce", "linear", CFrame.new(position))
					tween:Play()
				end
			)
		elseif setup.type == enums.FtueSetupType.CREATE_ITEM then
			local itemName = setup.itemName
			local item = itemManager:createItem(itemName, player.UserId)
			if not item then
				warn("ftue setup failed to create item", itemName)
				continue
			end
			local location = plotsManager:getWorldPositionFromPlotPositionForUserId(Vector3.new(setup.plotLocation[1], 0, setup.plotLocation[2]), player.UserId)
			if not location then
				warn("ftue setup has no world location for player", player)
				continue
			end
			local position = utils.getGroundPositionForLocation(location) + Vector3.new(0, item:getPart().Size.Y / 2, 0)

			item:getObj():PivotTo(CFrame.new(position))
			item:setPreventSettling()
			item:getObj().Parent = workspace
		elseif setup.type == enums.FtueSetupType.CREATE_ITEM_IN_BACKPACK then
			local itemName = setup.itemName
			local item = itemManager:createItem(itemName, player.UserId)
			if not item then
				warn("ftue setup failed to create item", itemName)
				continue
			end
			item:putInBackpack()
		else
			warn("unknown ftue setup type", stepName, setup.type)
		end
	end

end

function FtueManager.setupStepIfNeeded(self: FtueManager, player: Player, stepName: string?)
	local playerData = gameController:getPlayerData(player)
	local ftueProgress = playerData:getFtueProgress()

	ftueProgress.stepName = stepName

	if not ftueProgress.setupStepNames then
		--pre-2026-april-21 users won't have this set
		ftueProgress.setupStepNames = {}
	end

	if not utils.doesArrayContain(ftueProgress.setupStepNames, stepName) then
		-- we only do the setup of each step once, no matter how many times a user gets to that step
		self:setupStep(player, stepName)
		table.insert(ftueProgress.setupStepNames, stepName)
	end

	playerData:setFtueProgress(ftueProgress)

	RemoteEvents.NotifyFtueProgress:FireClient(player, ftueProgress)

	-- a nil step name crashed on the analytics table key before typing too
	analyticsManager:logEvent(player, analyticsManager:getFtueAnalyticsEventName(stepName :: string),
		{
			[stepName :: string] = true,
		}
	)

end

function FtueManager.trySetComplete(self: FtueManager, player: Player): boolean
	--print("player finished ftue", player)

	local playerData = gameController:getPlayerData(player)

	local ftueProgress = playerData:getFtueProgress()
	if not ftueProgress.isEnabled then
		return false
	end

	ftueProgress.stepName = nil
	ftueProgress.isEnabled = false

	playerData:setFtueProgress(ftueProgress)

	RemoteEvents.NotifyFtueProgress:FireClient(player, ftueProgress)

	analyticsManager:logEvent(player, analyticsManager.Events.FtueComplete,
		{
			[analyticsManager.Events.FtueComplete] = true,
		}
	)

	gameController:tryPlaceLuckBillboardForPlayer(player)

	return true
end


function FtueManager.trySetStepName(self: FtueManager, player: Player, stepName: string?)
	local playerData = gameController:getPlayerData(player)

	local ftueProgress = playerData:getFtueProgress()
	if not ftueProgress.isEnabled then
		return
	end

	self:setupStepIfNeeded(player, stepName)
end

function FtueManager.tryGetStepData(self: FtueManager, player: Player): any
	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local ftueProgress = playerData:getFtueProgress()
	if not ftueProgress.isEnabled then
		return
	end

	if not ftueProgress.stepName then
		return nil
	end

	local stepData = FtueSteps.getStepDataForStepName(ftueProgress.stepName)

	return stepData :: any
end

function FtueManager.notifyPickupItemForPlayer(self: FtueManager, player: Player, itemId: number)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.PICKUP then
			continue
		end

		local item = itemManager:getItemById(itemId)
		if not item then
			continue
		end
		if item:getItemName() ~= transition.itemName then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyMergeForPlayer(self: FtueManager, player: Player, mergeItem: any)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.MERGE then
			continue
		end

		-- can validate mergeItem in the future if needed

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyItemEquipped(self: FtueManager, player: Player?, itemId: number)
	if not player then
		return
	end
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	local item = itemManager:getItemById(itemId)
	if not item then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.EQUIP_ITEM then
			continue
		end

		if item:getItemName() ~= transition.itemName then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyItemUnequipped(self: FtueManager, player: Player?, itemId: number)
	if not player then
		return
	end
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	local item = itemManager:getItemById(itemId)
	if not item then
		-- it was merged or destroyed, can't tell what it was now
		return
	end


	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.UNEQUIP_ITEM then
			continue
		end

		if item:getItemName() ~= transition.itemName then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyItemPlacedOnGroundForPlayer(self: FtueManager, player: Player?, itemId: number)
	if not player then
		return
	end
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	local item = itemManager:getItemById(itemId)
	if not item then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.PLACE_ON_BOARD then
			continue
		end

		if item:getItemName() ~= transition.itemName then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifySummonToEatForPlayer(self: FtueManager, player: Player, dragon: any, crop: any)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.SUMMON_TO_EAT then
			continue
		end

		-- can validate dragon, crop in the future if needed

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyGemsCountChangedForPlayer(self: FtueManager, player: Player, playerAttributesKey: string, value: number)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.GET_GEMS then
			continue
		end

		local playerAttributesKeyGems = Elements.getGemsKeyForPrimaryElement(transition.primaryElement)

		if playerAttributesKey ~= playerAttributesKeyGems then
			continue
		end

		if value < transition.count then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyCoinsCountChangedForPlayer(self: FtueManager, player: Player, value: number)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.GET_COINS then
			continue
		end

		if value < transition.count then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.notifyBuyItemForPlayer(self: FtueManager, player: Player)
	local stepData = self:tryGetStepData(player)
	if not stepData then
		return
	end

	for _, transition in stepData.transitions do
		if transition.type ~= enums.FtueTransitionType.GET_ITEMS then
			continue
		end

		local isComplete = true

		-- check if we have what we need
		for _, itemDescriptor in transition.itemDescriptors do
			local itemName = itemDescriptor.itemName
			local count = itemDescriptor.count

			local playerData = gameController:getPlayerData(player)
			if not playerData:doesPlayerHaveItemCount(itemName, count) then
				-- this only works because GET_ITEMS only has 1 item type per ftue step
				analyticsManager:logEvent(player, analyticsManager.Events.FtueBuyItem,
					{
						objectName = itemName,
					}
				)
				isComplete = false
			end
		end

		if not isComplete then
			continue
		end

		task.spawn(
			function()
				self:trySetStepName(player, transition.stepName)
			end
		)
		return
	end
end

function FtueManager.new(): FtueManager
	local self: FtueManager = setmetatable({} :: FtueManagerFields, FtueManager)

	return self
end

function FtueManager.initClass(deps: any)
	gameController = deps.gameController
	itemManager = deps.itemManager
end

local singleton = FtueManager.new()

return singleton
