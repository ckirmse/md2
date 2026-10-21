--!strict

local NumberItem = require("./NumberItem")
local super = NumberItem

local MItem = {}
MItem.__index = setmetatable(MItem, super)

local Types = require("./Types")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local modificationsData = require("@game/ServerScriptService/GameData/Control/Modifications")
local mutationsData = require("@game/ServerScriptService/GameData/Control/Mutations")


export type MItemFields = Types.MItemFields
export type MItem = Types.MItem

function MItem.getBestMutation(mutation1: number?, mutation2: number?): number
	for _, mutation in {enums.Mutations.CELESTIAL, enums.Mutations.RAINBOW, enums.Mutations.CRIMSON, enums.Mutations.AZURE, enums.Mutations.VERDANT, enums.Mutations.GOLD, enums.Mutations.SILVER, enums.Mutations.BRONZE} do
		if mutation1 == mutation or mutation2 == mutation then
			return mutation
		end
	end
	return enums.Mutations.NORMAL
end

function MItem.compareMutations(mutation1: number?, mutation2: number?): boolean
	local bestMutation = MItem.getBestMutation(mutation1, mutation2)
	-- lua sort comparators (of which this is one) must return true ONLY if a should strictly come before b
	-- otherwise you get an exception
	return bestMutation == mutation1 and bestMutation ~= mutation2
end

function MItem.getMutationBonus(mutation: number): number
	if not mutationsData.bonusMultiplier[mutation] then
		warn("unknown bonus multiplier for mutation", mutation)
		return 0
	end

	return mutationsData.bonusMultiplier[mutation]
end

function MItem.getCombinedModifications(modifications1: { number }, modifications2: { number }): { number }
	return utils.getArrayUnion(modifications1, modifications2)
end

function MItem.getDataDumpString(self: MItem): string
	local text = super.getDataDumpString(self)
	text = text .. "\nMutation: " .. tostring(enums.getName(enums.Mutations, self.mutation))

	text = text .. "\nTraits: "
	if #self.traits > 0 then
		local names = {}
		for _, trait in self.traits do
			table.insert(names, tostring(enums.getName(enums.Trait, trait)))
		end
		text = text .. table.concat(names, ", ")
	else
		text = text .. "(none)"
	end

	text = text .. "\nModifications: "
	if #self.modifications > 0 then
		for i, modification in self.modifications do
			if i > 1 then
				text = text .. ", "
				end
			text = text .. tostring(enums.getName(enums.Modifications, modification))
		end
	else
		text = text .. "(none)"
	end

	return text
end

function MItem.canStackWith(self: MItem, item: any): boolean
	if not self:isMItemIdentical(item) then
		return false
	end

	--print("mitem can stack", self, item)
	return true
end

function MItem.getMutation(self: MItem): number
	return self.mutation
end

function MItem.hasIdenticalMutation(self: MItem, item: any): boolean
	return self.mutation == item.mutation
end

function MItem.hasIdenticalModifications(self: MItem, item: any): boolean
	if #self.modifications ~= #item.modifications then
		return false
	end

	for i = 1, #self.modifications do
		if self.modifications[i] ~= item.modifications[i] then
			return false
		end
	end

	return true
end

function MItem.hasIdenticalTraits(self: MItem, item: any): boolean
	if #self.traits ~= #item.traits then
		return false
	end

	for _, trait in self.traits do
		if not utils.doesArrayContain(item.traits, trait) then
			return false
		end
	end

	return true
end

function MItem.isMItemIdentical(self: MItem, item: any): boolean
	return self:hasIdenticalMutation(item) and self:hasIdenticalModifications(item) and self:hasIdenticalTraits(item)
end

function MItem.getTraits(self: MItem): { number }
	return utils.shallowCopy(self.traits)
end

function MItem.hasTrait(self: MItem, trait: number): boolean
	return utils.doesArrayContain(self.traits, trait)
end

function MItem.processTraitsChanged(self: MItem)
	if #self.traits == 0 then
		self:getObj():SetAttribute(Attributes.TRAITS, nil)
	else
		self:getObj():SetAttribute(Attributes.TRAITS, game:GetService("HttpService"):JSONEncode(self.traits))
	end

	self:notifyVisibleNameChanged()
end

-- returns true when the trait was new
function MItem.addTrait(self: MItem, trait: number): boolean
	if not enums.isValidValue(enums.Trait, trait) then
		warn("invalid trait, ignoring", trait, self)
		return false
	end

	if self:hasTrait(trait) then
		return false
	end

	table.insert(self.traits, trait)

	self:processTraitsChanged()

	self:updateDataDump()

	return true
end

function MItem.setTraits(self: MItem, traits: { number })
	self.traits = {}
	for _, trait in traits do
		if enums.isValidValue(enums.Trait, trait) and not utils.doesArrayContain(self.traits, trait) then
			table.insert(self.traits, trait)
		end
	end

	self:processTraitsChanged()

	self:updateDataDump()
end

function MItem.getModifications(self: MItem): { number }
	return utils.shallowCopy(self.modifications)
end

function MItem.getModificationCount(self: MItem): number
	return #self.modifications
end

function MItem.calculateModificationMultiplier(self: MItem): number
	local modificationMultiplier = 1
	for _, modification in self.modifications do
		local thisModificationMultiplier = modificationsData.defaultMultiplier
		if modificationsData.multipliers[modification] then
			thisModificationMultiplier = modificationsData.multipliers[modification]
		end
		modificationMultiplier += thisModificationMultiplier
	end
	return modificationMultiplier
end

function MItem.processMutationChanged(self: MItem)
	--print("mutation changed", self:getPart(), self.mutation)
	self:getObj():SetAttribute(Attributes.MUTATION, self.mutation)

end

function MItem.setMutation(self: MItem, mutation: number)
	if not enums.isValidValue(enums.Mutations, mutation) then
		warn("invalid mutation, ignoring", mutation, self)
		return
	end

	self.mutation = mutation

	self:processMutationChanged()

	self:notifyVisibleNameChanged()

	self:updateDataDump()
end

function MItem.doesHaveModification(self: MItem, modification: number): boolean
	return utils.doesArrayContain(self.modifications, modification)
end

function MItem.notifyModificationsChanged(self: MItem)
end

function MItem.getEncodedModifications(self: MItem): string
	return game:GetService("HttpService"):JSONEncode(self.modifications)
end

function MItem.processModificationsChanged(self: MItem)
	if #self.modifications == 0 then
		self:getObj():SetAttribute(Attributes.MODIFICATIONS, nil)
	else
		local encoded = self:getEncodedModifications()

		--print("setting modifications to", encoded)
		self:getObj():SetAttribute(Attributes.MODIFICATIONS, encoded)
	end

	self:notifyVisibleNameChanged()

	self:notifyModificationsChanged()
end

function MItem.toggleModification(self: MItem, modification: number)
	if not enums.isValidValue(enums.Modifications, modification) then
		warn("invalid modification, ignoring", modification, self)
		return
	end

	local index = utils.arrayFindIndexOf(self.modifications, modification)
	if index then
		table.remove(self.modifications, index)
	else
		table.insert(self.modifications, modification)
	end

	self:processModificationsChanged()

	self:updateDataDump()
end

function MItem.addModification(self: MItem, modification: number)
	if not enums.isValidValue(enums.Modifications, modification) then
		warn("invalid modification, ignoring", modification, self)
		return
	end

	if utils.doesArrayContain(self.modifications, modification) then
		return
	end

	table.insert(self.modifications, modification)

	self:processModificationsChanged()

	self:updateDataDump()
end

function MItem.setModifications(self: MItem, modifications: { number })
	self.modifications = utils.shallowCopy(modifications)

	self:processModificationsChanged()

	self:updateDataDump()
end

function MItem.getVisibleNameSuffix(self: MItem): string
	local mutModText = utils.getMutModText(self.mutation, self.modifications)

	local traitText = ""
	if #self.traits > 0 then
		local names = {}
		for _, trait in self.traits do
			table.insert(names, assert(enums.getPublicName(enums.Trait, trait)))
		end
		traitText = " {" .. table.concat(names, ", ") .. "}"
	end

	return mutModText .. traitText .. super.getVisibleNameSuffix(self)
end

-- itemIdMap is a map of itemId -> savedItemId, in case we want to save a reference to an item
function MItem.getSaveData(self: MItem, itemIdMap: any): any
	local retval = super.getSaveData(self, itemIdMap)

	retval.mutation = self.mutation
	retval.modifications = utils.shallowCopy(self.modifications)
	retval.traits = utils.shallowCopy(self.traits)

	return retval
end

function MItem.loadSaveData(self: MItem, itemSaveData: any, itemIdMap: any)
	super.loadSaveData(self, itemSaveData, itemIdMap)

	self.mutation = itemSaveData.mutation or enums.Mutations.NORMAL
	self.modifications = utils.shallowCopy(itemSaveData.modifications or {})
	self.traits = {}
	for _, trait in itemSaveData.traits or {} do
		if enums.isValidValue(enums.Trait, trait) and not utils.doesArrayContain(self.traits, trait) then
			table.insert(self.traits, trait)
		end
	end

	self:processMutationChanged()
	self:processModificationsChanged()
	self:processTraitsChanged()
end

function MItem.destroy(self: MItem)
	super.destroy(self)
end

function MItem.notifyNewCopy(self: MItem, sourceItem: any, count: number)
	super.notifyNewCopy(self, sourceItem, count)

	self.mutation = sourceItem.mutation
	-- this gets a copy
	self.modifications = sourceItem:getModifications()
	self.traits = sourceItem:getTraits()
end

function MItem.notifyNewClone(self: MItem)
	super.notifyNewClone(self)

	local itemData = self:getItemData()

	--print("mitem notify new clone")
	-- xxx not sure this is needed as of 2026-january-27
	self:processMutationChanged()

	self:processModificationsChanged()
	self:processTraitsChanged()

	self:getObj():SetAttribute(Attributes.MUTATION, self.mutation)
	if itemData.mutationSurfaceAppearanceName then
		self:getObj():SetAttribute(Attributes.MUTATION_SURFACE_APPEARANCE_NAME, itemData.mutationSurfaceAppearanceName)
	end

end

function MItem.new(itemId: number, itemName: string, userId: number): MItem
	local self = (setmetatable(super.new(itemId, itemName, userId), MItem) :: any) :: MItem

	local itemData = self:getItemData()

	self.mutation = enums.Mutations.NORMAL
	self.modifications = {}
	self.traits = {}

	self:processModificationsChanged()

	self:getObj():SetAttribute(Attributes.MUTATION, self.mutation)
	if itemData.mutationSurfaceAppearanceName then
		self:getObj():SetAttribute(Attributes.MUTATION_SURFACE_APPEARANCE_NAME, itemData.mutationSurfaceAppearanceName)
	end

	return self
end

return MItem
