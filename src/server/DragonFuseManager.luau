--!strict

local DragonFuseManager = {}
DragonFuseManager.__index = DragonFuseManager

local workspace = game:GetService("Workspace")

local MItem = require("./MItem")
local objectDataStore = require("./ObjectDataStore")
local Types = require("./Types")
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

type DragonFuseManagerFields = {}

export type DragonFuseManager = typeof(setmetatable({} :: DragonFuseManagerFields, DragonFuseManager))

local function isBackpackDragon(dragon: Types.ShadowDragon): boolean
	return dragon:getObj().Parent ~= workspace
end

function DragonFuseManager.tryFuseDragonsAtMaxLevel(self: DragonFuseManager, player: Player, itemId1: any, itemId2: any)
	if itemId1 == itemId2 then
		gameController:sendSystemMessageToPlayer(player, "You can't fuse a dragon with itself")
		return
	end

	local item1 = itemManager:getItemById(itemId1)
	local item2 = itemManager:getItemById(itemId2)
	if not item1 or not item2 then
		return
	end

	if item1:getType() ~= "shadowDragon" or item2:getType() ~= "shadowDragon" then
		return
	end

	if item1:getUserId() ~= player.UserId or item2:getUserId() ~= player.UserId then
		return
	end

	local dragon1 = item1 :: Types.ShadowDragon
	local dragon2 = item2 :: Types.ShadowDragon

	if not isBackpackDragon(dragon1) or not isBackpackDragon(dragon2) then
		gameController:sendSystemMessageToPlayer(player, "Only unused dragons in your backpack can be fused")
		return
	end

	if dragon1:getItemName() ~= dragon2:getItemName() then
		gameController:sendSystemMessageToPlayer(player, "You can only fuse two dragons of the same rarity and type")
		return
	end

	if not dragon1:isAtMaxLevel() or not dragon2:isAtMaxLevel() then
		gameController:sendSystemMessageToPlayer(player, "Both dragons must be at max level to fuse")
		return
	end

	local itemData = dragon1:getItemData()
	local upgradeItemName = itemData.mixins.merge and itemData.mixins.merge.upgradeItemName
	if not upgradeItemName then
		gameController:sendSystemMessageToPlayer(player, "This dragon is already at the top of its rarity chain")
		return
	end

	if not objectDataStore:getObjectDataByName(upgradeItemName) then
		warn("fuse-at-max-level: upgradeItemName does not resolve to a real item, refusing to consume sources", itemData.name, upgradeItemName)
		return
	end

	local bestMutation = MItem.getBestMutation(dragon1:getMutation(), dragon2:getMutation())

	local newDragon = itemManager:createItem(upgradeItemName, player.UserId) :: Types.ShadowDragon?
	if not newDragon then
		warn("failed to create fused dragon", upgradeItemName)
		return
	end

	newDragon:setMutation(bestMutation)
	newDragon:putInBackpack()

	itemManager:destroyItem(dragon1)
	itemManager:destroyItem(dragon2)

	gameController:sendSystemMessageToPlayer(player, string.format("Fused into %s", newDragon:getDisplayName()))
end

function DragonFuseManager.new(): DragonFuseManager
	local self = setmetatable({}, DragonFuseManager)
	return self
end

function DragonFuseManager.initClass(deps: any)
	itemManager = deps.itemManager
	gameController = deps.gameController
end

function DragonFuseManager.init(self: DragonFuseManager) end

local singleton = DragonFuseManager.new()

return singleton
