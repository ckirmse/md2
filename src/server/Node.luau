--!strict

local BaseObject = require("./BaseObject")
local super = BaseObject

local Node = {}
Node.__index = setmetatable(Node, super)

local collectionService = game:GetService("CollectionService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local Effects = GameAssets:WaitForChild("Effects")
local SummonDragonToMineAudioParent = Effects:WaitForChild("SummonDragonToMineAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local analyticsManager = require("./AnalyticsManager")
local lootTableManager = require("./LootTableManager")


export type NodeFields = Types.NodeFields
export type Node = Types.Node

function Node.getMineTargetPosition(self: Node)
	local crystal = self.obj:FindFirstChild("CrystalNode_Crystal")
	return crystal.Position
end

function Node.beginIdle(self: Node)
	local crystal = self.obj:FindFirstChild("CrystalNode_Crystal")
	crystal.Transparency = 0
	crystal.CanCollide = true
	crystal:FindFirstChild("Motes").Enabled = true
	crystal:FindFirstChild("PointLight").Enabled = true

	collectionService:AddTag(self:getObj(), Tags.MINABLE_NODE)
end

function Node.cleanupIdle(self: Node)

end

function Node.beginGettingMined(self: Node, dragon: any)
	local player = dragon:getPlayer()
	local playerData = gameController:getPlayerData(player)

	collectionService:RemoveTag(self:getObj(), Tags.MINABLE_NODE)

	utils.pulseAttribute(self:getObj(), Attributes.ANIMATION_MINE_NODE, "")

	local objectData = self:getObjectData()
	local lootName = objectData.lootName
	local lootEntries = lootTableManager:calculateLootResults(lootName)

	-- get the items from the results (expectation on 2026-january-20 is that they will be crystals)
	local itemCreationData = lootTableManager:getItemCreationDataFromItemLootResults(lootEntries)
	local items = gameController:createItemsFromItemCreationDataForPlayer(itemCreationData, player)

	for _, item in items do
		item:setPreventSettling()
	end

	for _, item in items do
		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "mineNode",
			}
		)
	end

	-- see if any extra due to abilities
	local primaryElement = objectData.primaryElement
	local extraLootPrefix = playerData:getPlayerVariable(Attributes.EXTRA_NODE_LOOT_PREFIX)
	if extraLootPrefix ~= "" then
		local extraLootName = "NodeAbility" .. tostring(enums.getPublicName(enums.PrimaryElements, primaryElement)) .. extraLootPrefix

		local extraLootEntries = lootTableManager:calculateLootResults(extraLootName)
		local extraItemCreationData = lootTableManager:getItemCreationDataFromItemLootResults(extraLootEntries)
		local extraItems = gameController:createItemsFromItemCreationDataForPlayer(extraItemCreationData, player)

		for _, item in extraItems do
			item:setPreventSettling()
		end

		for _, item in extraItems do
			analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
				{
					objectName = item:getItemName(),
					primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
					rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
					itemType = item:getType(),
					acquisitionSource = "abilityExtraNodeLoot",
				}
			)
		end

		utils.arrayAppend(items, extraItems)
	end

	gameController:spawnItemsAtPositionAndGoToPlayerBackpack(items, self:getObj():GetPivot().Position, player)

	playerData:unlockPrimaryElementIfNeeded(primaryElement)

	analyticsManager:logEvent(player, analyticsManager.Events.MineNode,
		{
			objectName = self.objectName,
			dragonObjectName = dragon:getItemName(),
			primaryElement = enums.getPublicName(enums.PrimaryElements, primaryElement),
		}
	)

	playerData:incrementStat("nodesMined")

	self:setState(enums.NodeState.EMPTY)

end

function Node.cleanupGettingMined(self: Node)
end

function Node.beginEmpty(self: Node)
	collectionService:RemoveTag(self:getObj(), Tags.MINABLE_NODE)

	local crystal = self.obj:FindFirstChild("CrystalNode_Crystal")
	crystal.Transparency = 1
	crystal.CanCollide = false
	crystal:FindFirstChild("Motes").Enabled = false
	crystal:FindFirstChild("PointLight").Enabled = false

end

function Node.cleanupEmpty(self: Node)

end

function Node.isPlayerCloseEnoughToSummonToMine(self: Node, player: Player)
	local distance = ((player.Character :: any).HumanoidRootPart.Position - self.obj:GetPivot().Position).Magnitude
	local maxDistance = Constants.SUMMON_MINE_NODE_DISTANCE

	if distance > maxDistance * 1.1 then
		print("player tried to summon to mine but too far away", player, distance, maxDistance)
		return false
	end

	return true
end

function Node.isPlayerCloseEnoughToMineWhileRiding(self: Node, player: Player)
	local playerData = gameController:getPlayerData(player)
	local maxDistance = playerData:getPlayerVariable(Attributes.FIREBALL_RANGE)

	local distance = ((player.Character :: any).HumanoidRootPart.Position - self.obj:GetPivot().Position).Magnitude

	if distance > maxDistance * 1.1 then
		print("player tried to mine while riding but too far away", player, distance, maxDistance)
		return false
	end

	return true
end

function Node.canBeMinedByPlayer(self: Node, player: Player)
	if self.state ~= enums.NodeState.IDLE then
		return false
	end

	return true
end

function Node.notifyDragonComingToMine(self: Node, dragon: any)
	local player = dragon:getPlayer()
	if not player then
		return
	end

	local summonDragonToMineAudioParent: any = SummonDragonToMineAudioParent:Clone()
	summonDragonToMineAudioParent.Position = player.Character.HumanoidRootPart.Position
	summonDragonToMineAudioParent.Parent = workspace
	game:GetService("Debris"):AddItem(summonDragonToMineAudioParent, 5) -- destroy after 5s

	local audioSummonToMine = summonDragonToMineAudioParent:FindFirstChild("AudioSummonToMine")
	audioSummonToMine:Play()
end

function Node.notifyMinedByDragon(self: Node, dragon: any)
	if self.state ~= enums.NodeState.IDLE then
		return
	end

	-- probably shouldn't be a state, should just do the stuff here
	self:setState(enums.NodeState.GETTING_MINED, dragon)
end

function Node.notifyRefill(self: Node)
	self:setState(enums.NodeState.IDLE)
end

function Node.endState(self: Node)
	if self.state == enums.NodeState.IDLE then
		self:cleanupIdle()
	elseif self.state == enums.NodeState.GETTING_MINED then
		self:cleanupGettingMined()
	elseif self.state == enums.NodeState.EMPTY then
		self:cleanupEmpty()
	else
		warn("end unknown node state", self, self.state)
	end

	self.state = nil
end

function Node.beginState(self: Node, state: number?, data: any)
	self.state = state
	--print("node beginning state", self:getObjectName(), state)

	if self.state == enums.NodeState.IDLE then
		self:beginIdle()
	elseif self.state == enums.NodeState.GETTING_MINED then
		self:beginGettingMined(data)
	elseif self.state == enums.NodeState.EMPTY then
		self:beginEmpty()
	else
		warn("begin unknown node state", self, state)
	end
end

function Node.setState(self: Node, state: number?, data: any)
	self:endState()

	self:beginState(state, data)
end

function Node.loadSaveData(self: Node, objectSaveData: any)
	local state = objectSaveData.state

	self:setState(state)
end

function Node.getSaveData(self: Node): any
	return {
		state = self.state,
	}
end

function Node.destroy(self: Node)
	self:endState()

	self.obj:Destroy()
	self.obj = nil
end

function Node.new(objectData: any, cframe: CFrame, objectId: number): Node
	local self = (setmetatable(super.new(objectData, cframe, objectId), Node) :: any) :: Node

	self:beginState(enums.NodeState.IDLE)

	self:getObj():SetAttribute(Attributes.PRIMARY_ELEMENT, objectData.primaryElement)
	self:getObj():SetAttribute(Attributes.SIZE, objectData.targetSize)

	if objectData.animation then
		if objectData.animation.type == "rotation" then
			self:getObj():SetAttribute(Attributes.ANIMATION_NODE_ROTATE, string.format("%s %.3f", objectData.animation.partName, objectData.animation.rotationPeriodSec))
		else
			warn("invalid node animation type", objectData, objectData.animation.type)
		end
	end

	self:getObj():SetAttribute(Attributes.OBJECT_ID, self:getObjectId())
	collectionService:AddTag(self:getObj(), Tags.NODE)

	return self
end

function Node.initClass(deps: any)
	gameController = deps.gameController
end

return Node
