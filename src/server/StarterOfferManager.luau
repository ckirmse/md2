--!strict

local StarterOfferManager = {}
StarterOfferManager.__index = StarterOfferManager

local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local itemManager = require("./ItemManager")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local enums = require("@game/ReplicatedStorage/Shared/Enums")

local analyticsManager = require("./AnalyticsManager")

-- GameData tables are authored in Studio and stay untyped
local starterOfferData: any = require("@game/ServerScriptService/GameData/Control/StarterOffer")

type StarterOfferManagerFields = {}

export type StarterOfferManager = typeof(setmetatable({} :: StarterOfferManagerFields, StarterOfferManager))

function StarterOfferManager.updateAndGetStarterOfferDataForPlayer(self: StarterOfferManager, player: Player): any
	local playerData = gameController:getPlayerData(player)

	local starterOfferProgress = playerData:getStarterOfferProgress()

	if starterOfferProgress.isPurchased then
		return {}
	end

	local now = workspace:GetServerTimeNow()

	local beginTime: number?
	local totalPlaySec = playerData:getTotalPlaySec()
	if totalPlaySec < starterOfferData.minPlaySec then
		beginTime = now + starterOfferData.minPlaySec - totalPlaySec
	end

	if not starterOfferProgress.endTime then
		starterOfferProgress.endTime = math.floor(now + starterOfferData.durationSec)
		playerData:setStarterOfferProgress(starterOfferProgress)
	end

	if starterOfferProgress.endTime < now then
		return {}
	end

	local itemDescriptors: { any } = {}
	for _, itemDescriptor in starterOfferData.itemDescriptors do
		local objectData = objectDataStore:getObjectDataByName(itemDescriptor.itemName)
		table.insert(itemDescriptors,
			{
				itemName = itemDescriptor.itemName,
				templatePath = objectData.casterPath or objectData.templatePath,
				cameraPosition = itemDescriptor.cameraPosition,
				mutation = itemDescriptor.mutation,
				mutationSurfaceAppearanceName = objectData.mutationSurfaceAppearanceName,
				description = itemDescriptor.description or objectData.displayName or objectData.name,
			}
		)
	end

	local starterOfferData = {
		beginTime = beginTime,
		endTime = starterOfferProgress.endTime,
		itemDescriptors = itemDescriptors,
		robuxProductId = starterOfferData.robuxProductId,
	}

	--print("sending starter offer data", starterOfferData)
	return starterOfferData
end

function StarterOfferManager.deliverToPlayer(self: StarterOfferManager, player: Player)
	local playerData = gameController:getPlayerData(player)

	for _, itemDescriptor in starterOfferData.itemDescriptors do
		local item = itemManager:createItem(itemDescriptor.itemName, player.UserId)
		if not item then
			warn("failed to create starter offer item", itemDescriptor.itemName)
			continue
		end
		if itemDescriptor.mutation and itemDescriptor.mutation ~= enums.Mutations.NORMAL then
			-- a mutation in the descriptor implies a mutation-capable (MItem) item
			local mutationItem = item :: Types.MItem
			mutationItem:setMutation(itemDescriptor.mutation :: number)
		end

		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "starterOffer",
			}
		)

		local visibleName = item:getVisibleName()
		item:putInBackpack()
		-- note: item may have been destroyed if it entered a stack

		gameController:sendSystemMessageToPlayer(player, string.format("You received a %s!", visibleName))
	end

	local starterOfferProgress = {
		isPurchased = true,
	}

	playerData:setStarterOfferProgress(starterOfferProgress)

	RemoteEvents.NotifyEndStarterOffer:FireClient(player)
end

function StarterOfferManager.resetStarterOfferProgressForPlayer(self: StarterOfferManager, player: Player)
	local playerData = gameController:getPlayerData(player)

	local starterOfferProgress = {}
	playerData:setStarterOfferProgress(starterOfferProgress)
end

-- this stuff can't go in new() because it depends on gameController being set
function StarterOfferManager.init(self: StarterOfferManager)

end

function StarterOfferManager.new(): StarterOfferManager
	local self: StarterOfferManager = setmetatable({} :: StarterOfferManagerFields, StarterOfferManager)

	return self
end

function StarterOfferManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = StarterOfferManager.new()

return singleton
