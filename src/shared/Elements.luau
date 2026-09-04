--!strict

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")

local Elements = {}

export type PrimaryElementData = {
	primaryElement: number,
	sortIndex: number,
	instanceName: string,
	isUnlockedKey: string,
	levelKey: string,
	xpKey: string,
	gemsKey: string,
	applyFlameKey: string,
	gemItemName: string,
	fireballModification: number,
	abilityStoreLevelPath: string,
	abilityStoreLockedLevelPath: string,
	abilityStoreLockedTemplate: string,
	abilityStoreUnlockedTemplate: string,
	abilityStoreEquippedTemplate: string,
	abilityStoreComingSoonTemplate: string,
	abilityStoreSlotLockedTemplate: string,
	abilityStoreDetailTemplate: string,
	abilityStoreDetailEquipTemplate: string,
	abilityStoreDetailUnequipTemplate: string,
	abilityStoreDetailLockedTemplate: string,
	-- renamed from abilityStoreDetailNotEnoughGemsTemplate (2026-august-20): ability costs are now
	-- unified coins, not per-element gems; all 3 primary elements point at the same "NotEnoughCoins"
	-- instance below, kept per-element in the data table for consistency with the rest of this file.
	-- abilityStoreDetailNotEnoughGemsTemplate: string,
	abilityStoreDetailNotEnoughCoinsTemplate: string,
	abilityStoreDetailNoAvailableSlotsTemplate: string,
	unlockAbilitySlotRobuxProductId: number,
}

local primaryElementDatas: { PrimaryElementData } = {
	{
		primaryElement = enums.PrimaryElements.FIRE,
		sortIndex = 3,
		instanceName = "AffinityRed",
		isUnlockedKey = PlayerAttributeKeys.IS_UNLOCKED_FIRE,
		levelKey = PlayerAttributeKeys.LEVEL_FIRE,
		xpKey = PlayerAttributeKeys.XP_FIRE,
		gemsKey = PlayerAttributeKeys.GEMS_FIRE,
		applyFlameKey = PlayerAttributeKeys.APPLY_FLAME_FIRE,
		gemItemName = "Red Gem",
		fireballModification = enums.Modifications.RED_FLAME,
		abilityStoreLevelPath = "PlayerLevels.Red",
		abilityStoreLockedLevelPath = "PlayerLevels.LockedRed",
		abilityStoreLockedTemplate = "RedLocked",
		abilityStoreUnlockedTemplate = "RedCanEquip",
		abilityStoreEquippedTemplate = "RedEquipped",
		abilityStoreComingSoonTemplate = "ComingSoonRed",
		abilityStoreSlotLockedTemplate = "SlotLockedRed",
		abilityStoreDetailTemplate = "RedDetail",
		abilityStoreDetailEquipTemplate = "RedEquip",
		abilityStoreDetailUnequipTemplate = "RedUnequip",
		abilityStoreDetailLockedTemplate = "RedLocked",
		-- abilityStoreDetailNotEnoughGemsTemplate = "RedNotEnoughGems",
		abilityStoreDetailNotEnoughCoinsTemplate = "NotEnoughCoins",
		abilityStoreDetailNoAvailableSlotsTemplate = "RedNoSlots",
		unlockAbilitySlotRobuxProductId = 3566864868,
	},
	{
		primaryElement = enums.PrimaryElements.NATURE,
		sortIndex = 1,
		instanceName = "AffinityGreen",
		isUnlockedKey = PlayerAttributeKeys.IS_UNLOCKED_NATURE,
		levelKey = PlayerAttributeKeys.LEVEL_NATURE,
		xpKey = PlayerAttributeKeys.XP_NATURE,
		gemsKey = PlayerAttributeKeys.GEMS_NATURE,
		applyFlameKey = PlayerAttributeKeys.APPLY_FLAME_NATURE,
		gemItemName = "Green Gem",
		fireballModification = enums.Modifications.GREEN_FLAME,
		abilityStoreLevelPath = "PlayerLevels.Green",
		abilityStoreLockedLevelPath = "PlayerLevels.LockedGreen",
		abilityStoreLockedTemplate = "GreenLocked",
		abilityStoreUnlockedTemplate = "GreenCanEquip",
		abilityStoreEquippedTemplate = "GreenEquipped",
		abilityStoreComingSoonTemplate = "ComingSoonGreen",
		abilityStoreSlotLockedTemplate = "SlotLockedGreen",
		abilityStoreDetailTemplate = "GreenDetail",
		abilityStoreDetailEquipTemplate = "GreenEquip",
		abilityStoreDetailUnequipTemplate = "GreenUnequip",
		abilityStoreDetailLockedTemplate = "GreenLocked",
		-- abilityStoreDetailNotEnoughGemsTemplate = "GreenNotEnoughGems",
		abilityStoreDetailNotEnoughCoinsTemplate = "NotEnoughCoins",
		abilityStoreDetailNoAvailableSlotsTemplate = "GreenNoSlots",
		unlockAbilitySlotRobuxProductId = 3566864694,
	},
	{
		primaryElement = enums.PrimaryElements.WATER,
		sortIndex = 2,
		instanceName = "AffinityBlue",
		isUnlockedKey = PlayerAttributeKeys.IS_UNLOCKED_WATER,
		levelKey = PlayerAttributeKeys.LEVEL_WATER,
		xpKey = PlayerAttributeKeys.XP_WATER,
		gemsKey = PlayerAttributeKeys.GEMS_WATER,
		applyFlameKey = PlayerAttributeKeys.APPLY_FLAME_WATER,
		gemItemName = "Blue Gem",
		fireballModification = enums.Modifications.BLUE_FLAME,
		abilityStoreLevelPath = "PlayerLevels.Blue",
		abilityStoreLockedLevelPath = "PlayerLevels.LockedBlue",
		abilityStoreLockedTemplate = "BlueLocked",
		abilityStoreUnlockedTemplate = "BlueCanEquip",
		abilityStoreEquippedTemplate = "BlueEquipped",
		abilityStoreComingSoonTemplate = "ComingSoonBlue",
		abilityStoreSlotLockedTemplate = "SlotLockedBlue",
		abilityStoreDetailTemplate = "BlueDetail",
		abilityStoreDetailEquipTemplate = "BlueEquip",
		abilityStoreDetailUnequipTemplate = "BlueUnequip",
		abilityStoreDetailLockedTemplate = "BlueLocked",
		-- abilityStoreDetailNotEnoughGemsTemplate = "BlueNotEnoughGems",
		abilityStoreDetailNotEnoughCoinsTemplate = "NotEnoughCoins",
		abilityStoreDetailNoAvailableSlotsTemplate = "BlueNoSlots",
		unlockAbilitySlotRobuxProductId = 3566864780,
	},
}

function Elements.getPrimaryElementsSorted(): { number }
	local primaryElementsRaw = enums.getAllValues(enums.PrimaryElements)
	local primaryElements: { number } = {}
	for _, primaryElement in primaryElementsRaw do
		if primaryElement == enums.PrimaryElements.NONE then
			continue
		end
		table.insert(primaryElements, primaryElement)
	end
	table.sort(primaryElements,
		function(a: number, b: number): boolean
			local indexA = 0
			local indexB = 0
			for _, primaryElementData in primaryElementDatas do
				if primaryElementData.primaryElement == a then
					indexA = primaryElementData.sortIndex
				elseif primaryElementData.primaryElement == b then
					indexB = primaryElementData.sortIndex
				end
			end
			return indexA < indexB
		end
	)
	return primaryElements
end

function Elements.getDataForPrimaryElement(primaryElement: number?): PrimaryElementData?
	for _, primaryElementData in primaryElementDatas do
		if primaryElementData.primaryElement ~= primaryElement then
			continue
		end
		return primaryElementData
	end

	warn("primary element not found", primaryElement)

	return nil
end

function Elements.validatePrimaryElement(primaryElement: number?): boolean
	for _, primaryElementData in primaryElementDatas do
		if primaryElementData.primaryElement ~= primaryElement then
			continue
		end
		return true
	end

	return false
end

function Elements.getSortIndexForPrimaryElement(primaryElement: number): number
	if primaryElement == enums.PrimaryElements.NONE then
		return 1
	end

	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.sortIndex
end

function Elements.getIsUnlockedKeyForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.isUnlockedKey
end

function Elements.getLevelKeyForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.levelKey
end

function Elements.getXpKeyForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.xpKey
end

function Elements.getGemsKeyForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.gemsKey
end

function Elements.getApplyFlameKeyForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.applyFlameKey
end

function Elements.getGemItemNameForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.gemItemName
end

function Elements.getFireballModificationForPrimaryElement(primaryElement: number): number
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.fireballModification
end

function Elements.getAbilityStoreLevelPathForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreLevelPath
end

function Elements.getAbilityStoreLockedLevelPathForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreLockedLevelPath
end

function Elements.getAbilityStoreLockedTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreLockedTemplate
end

function Elements.getAbilityStoreUnlockedTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreUnlockedTemplate
end

function Elements.getAbilityStoreEquippedTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreEquippedTemplate
end

function Elements.getAbilityStoreComingSoonTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreComingSoonTemplate
end

function Elements.getAbilityStoreSlotLockedTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreSlotLockedTemplate
end

function Elements.getAbilityStoreDetailTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailTemplate
end

function Elements.getAbilityStoreDetailEquipTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailEquipTemplate
end

function Elements.getAbilityStoreDetailUnequipTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailUnequipTemplate
end

function Elements.getAbilityStoreDetailLockedTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailLockedTemplate
end

-- legacy (2026-august-20): this used to pick between 3 per-element "not enough gems" templates;
-- ability costs are now unified coins, so every primary element maps to the same "NotEnoughCoins"
-- instance (see abilityStoreDetailNotEnoughCoinsTemplate above), not element-themed art.
-- function Elements.getAbilityStoreDetailNotEnoughGemsTemplateForPrimaryElement(primaryElement: number): string
-- 	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
-- 	return primaryElementData.abilityStoreDetailNotEnoughGemsTemplate
-- end

function Elements.getAbilityStoreDetailNotEnoughCoinsTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailNotEnoughCoinsTemplate
end

function Elements.getAbilityStoreDetailNoAvailableSlotsTemplateForPrimaryElement(primaryElement: number): string
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.abilityStoreDetailNoAvailableSlotsTemplate
end

function Elements.getUnlockAbilitySlotRobuxProductIdForPrimaryElement(primaryElement: number): number
	local primaryElementData = assert(Elements.getDataForPrimaryElement(primaryElement))
	return primaryElementData.unlockAbilitySlotRobuxProductId
end

function Elements.getPrimaryElementByGemsKey(gemsKey: string): number
	for _, primaryElementData in primaryElementDatas do
		if primaryElementData.gemsKey ~= gemsKey then
			continue
		end
		return primaryElementData.primaryElement
	end

	warn("gems key not found", gemsKey)

	return enums.PrimaryElements.NONE
end

return Elements
