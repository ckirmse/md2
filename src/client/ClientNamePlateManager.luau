--!strict

local ClientNamePlateManager = {}
ClientNamePlateManager.__index = ClientNamePlateManager

local collectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the billboard template's shape only exists in Studio, so it is untyped here
local ItemNameBillboard: any = UX:WaitForChild("ItemNameBillboard")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientMergeController = require("./ClientMergeController")
local clientRideController = require("./ClientRideController")
local clientShadowManager = require("./ClientShadowManager")


type IndicatorData = {
	instance: any, -- world item instance; its shape only exists at runtime
	caster: any,
	isRidingThis: boolean,
	isMerging: boolean,
	billboard: any?, -- ItemNameBillboard clone
	namePlateNameChangedConnect: RBXScriptConnection?,
	modificationsChangedConnect: RBXScriptConnection?,
	mutationChangedConnect: RBXScriptConnection?,
	parentChangedConnect: RBXScriptConnection?,
	casterRecreatedEventConnect: RBXScriptConnection?,
}

type ClientNamePlateManagerFields = {
	indicatorMap: { [number]: IndicatorData },
}

export type ClientNamePlateManager = typeof(setmetatable({} :: ClientNamePlateManagerFields, ClientNamePlateManager))

function ClientNamePlateManager.configureBillboardForItemId(self: ClientNamePlateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		-- this can happen post merge
		return
	end

	local inst = indicatorData.instance
	local billboard = indicatorData.billboard :: any

	billboard.Enabled = (inst.Parent == workspace) and not indicatorData.isRidingThis and not indicatorData.isMerging
end

function ClientNamePlateManager.updateTextForItemId(self: ClientNamePlateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		-- this can happen on startup due to races; we initialize our text when initialized so not a problem
		return
	end

	local inst = indicatorData.instance
	local billboard = indicatorData.billboard :: any

	local itemNameLabel = billboard:FindFirstChild("TextLabel")
	local rawNameStr = inst:GetAttribute(Attributes.DISPLAY_NAME)
	if not rawNameStr then
		-- this can happen when item newly created at startup
		--print("inst doesn't have a nameplate", inst)
		rawNameStr = ""
	end

	local color = utils.getColorForRarity(inst:GetAttribute(Attributes.RARITY))
	local colorStr = color:ToHex()
	local nameStr = string.format("<font color=\"#%s\">%s</font>", colorStr, rawNameStr)

	local str = nameStr

	-- build up optional line of text for mutation and modifications

	local mText = utils.getMutModRichTextForInstance(inst)

	if mText ~= "" then
		str = str .. "\n" .. mText
	end

	local extraText = inst:GetAttribute(Attributes.NAME_PLATE_EXTRA_TEXT) or ""
	if extraText then
		str = str .. "\n" .. extraText
	end
	itemNameLabel.Text = str

	local lineCount = 1 + utils.getCountNewlines(str)
	billboard.Size = UDim2.new(billboard.Size.X :: UDim, UDim.new(0, 20 * lineCount))

end

function ClientNamePlateManager.removeIndicators(self: ClientNamePlateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local billboard = indicatorData.billboard
	if billboard then
		billboard:Destroy()
		indicatorData.billboard = nil
	end

	local namePlateNameChangedConnect = indicatorData.namePlateNameChangedConnect
	if namePlateNameChangedConnect then
		namePlateNameChangedConnect:Disconnect()
		indicatorData.namePlateNameChangedConnect = nil
	end

	local modificationsChangedConnect = indicatorData.modificationsChangedConnect
	if modificationsChangedConnect then
		modificationsChangedConnect:Disconnect()
		indicatorData.modificationsChangedConnect = nil
	end

	local mutationChangedConnect = indicatorData.mutationChangedConnect
	if mutationChangedConnect then
		mutationChangedConnect:Disconnect()
		indicatorData.mutationChangedConnect = nil
	end

	local parentChangedConnect = indicatorData.parentChangedConnect
	if parentChangedConnect then
		parentChangedConnect:Disconnect()
		indicatorData.parentChangedConnect = nil
	end

	local casterRecreatedEventConnect = indicatorData.casterRecreatedEventConnect
	if casterRecreatedEventConnect then
		casterRecreatedEventConnect:Disconnect()
		indicatorData.casterRecreatedEventConnect = nil
	end

	self.indicatorMap[itemId] = nil
end

function ClientNamePlateManager.createBillboard(self: ClientNamePlateManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		-- this can happen post merge
		return
	end

	local caster = indicatorData.caster

	local anchor = utils.findFirstDescendantWithAttribute(caster, "NamePlate", true)
	if not anchor then
		anchor = caster
	end

	local billboard = ItemNameBillboard:Clone()
	billboard.MaxDistance = Constants.NAME_PLATE_DISTANCE
	billboard.Enabled = true
	billboard:SetAttribute(Attributes.ITEM_ID, itemId) -- for debugging

	billboard.Parent = anchor

	indicatorData.billboard = billboard

	self:updateTextForItemId(itemId)
	self:configureBillboardForItemId(itemId)

end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientNamePlateManager.notifyNewInstance(self: ClientNamePlateManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	-- don't create one if we already have one
	if self.indicatorMap[itemId] then
		return
	end

	local caster
	if clientShadowManager:isShadow(itemId) then
		caster = clientShadowManager:getCaster(itemId)
	else
		caster = inst
	end

	local ridingObj: any = clientRideController:getRidingObj()
	-- as of 2026-august-11 this calls GetAttribute; it previously called getAttribute
	-- (lowercase), which is not a member and would have thrown when riding
	local ridingItemId = if ridingObj then ridingObj:GetAttribute(Attributes.ITEM_ID) else nil

	self.indicatorMap[itemId] = {
		instance = inst,
		caster = caster,
		isRidingThis = ridingItemId == itemId,
		isMerging = false,
		billboard = nil,
	}

	local indicatorData = self.indicatorMap[itemId]

	self:createBillboard(itemId)
	-- ideally should support clicking on the text (but not transparent background)
	-- but we do not do that

	indicatorData.namePlateNameChangedConnect = inst:GetAttributeChangedSignal(Attributes.DISPLAY_NAME):Connect(
		function()
			self:updateTextForItemId(itemId)
		end
	)

	indicatorData.modificationsChangedConnect = inst:GetAttributeChangedSignal(Attributes.MODIFICATIONS):Connect(
		function()
			self:updateTextForItemId(itemId)
		end
	)

	indicatorData.mutationChangedConnect = inst:GetAttributeChangedSignal(Attributes.MUTATION):Connect(
		function()
			self:updateTextForItemId(itemId)
		end
	)

	indicatorData.parentChangedConnect = inst:GetPropertyChangedSignal("Parent"):Connect(
		function()
			self:configureBillboardForItemId(itemId)
		end
	)

	if clientShadowManager:isShadow(itemId) then
		indicatorData.casterRecreatedEventConnect = (clientShadowManager:getCasterRecreatedEvent(itemId) :: RBXScriptSignal):Connect(
			function(caster)
				indicatorData.caster = caster

				local billboard = indicatorData.billboard
				if billboard then
					billboard:Destroy()
					indicatorData.billboard = nil
				end

				self:createBillboard(itemId)
			end
		)
	end
end

function ClientNamePlateManager.notifyRemoveInstance(self: ClientNamePlateManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	self:removeIndicators(itemId)
end

function ClientNamePlateManager.getMapSize(self: ClientNamePlateManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientNamePlateManager.init(self: ClientNamePlateManager)

	collectionService:GetInstanceAddedSignal(Tags.CROP):Connect(
		function(inst)
			--print("new crop", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CROP):Connect(
		function(inst)
			--print("removed crop", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.SHADOW_DRAGON):Connect(
		function(inst)
			--print("new shadow dragon", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.SHADOW_DRAGON):Connect(
		function(inst)
			--print("removed shadow dragon", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.DRAGON_EGG):Connect(
		function(inst)
			--print("new dragon egg", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.DRAGON_EGG):Connect(
		function(inst)
			--print("removed dragon egg", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.CRYSTAL):Connect(
		function(inst)
			--print("new crystal", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CRYSTAL):Connect(
		function(inst)
			--print("removed crystal", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.PACK):Connect(
		function(inst)
			--print("new pack", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.PACK):Connect(
		function(inst)
			--print("removed pack", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.KEY):Connect(
		function(inst)
			--print("new key", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.KEY):Connect(
		function(inst)
			--print("removed key", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	collectionService:GetInstanceAddedSignal(Tags.BLUEPRINT):Connect(
		function(inst)
			--print("new blueprint", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.BLUEPRINT):Connect(
		function(inst)
			--print("removed blueprint", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CROP) do
		--print("existing crop", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.SHADOW_DRAGON) do
		--print("existing dragon", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.DRAGON_EGG) do
		--print("existing dragon egg", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.CRYSTAL) do
		--print("existing crystal", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.PACK) do
		--print("existing pack", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.KEY) do
		--print("existing key", inst)
		self:notifyNewInstance(inst)
	end
	for _, inst in collectionService:GetTagged(Tags.BLUEPRINT) do
		--print("existing blueprint", inst)
		self:notifyNewInstance(inst)
	end

	clientRideController:getEvent():Connect(
		function(isRiding)
			--print("name plate manager is riding changed", isRiding)
			local ridingObj: any = clientRideController:getRidingObj()
			-- as of 2026-august-11 this calls GetAttribute; it previously called getAttribute
			-- (lowercase), which is not a member and would have thrown when riding
			local ridingItemId = if ridingObj then ridingObj:GetAttribute(Attributes.ITEM_ID) else nil

			for itemId, indicatorData in self.indicatorMap do
				indicatorData.isRidingThis = ridingItemId == itemId
				self:configureBillboardForItemId(itemId)
			end
		end
	)

	clientMergeController:getEvent():Connect(
		function(itemId, isMerging, isTrigger)
			--print("name plate manager knows item is merging", itemId, isMerging)
			if isTrigger then
				-- don't mess wit the trigger item, it causes problems with the proximity prompt of merging
				return
			end

			local indicatorData = self.indicatorMap[itemId]
			-- not all items that can be merged have nameplates, that's OK
			if not indicatorData then
				return
			end

			indicatorData.isMerging = isMerging

			self:configureBillboardForItemId(itemId)
		end
	)

end

function ClientNamePlateManager.new(): ClientNamePlateManager
	local self = setmetatable({} :: ClientNamePlateManagerFields, ClientNamePlateManager)

	self.indicatorMap = {}

	return self
end


local singleton = ClientNamePlateManager.new()

return singleton
