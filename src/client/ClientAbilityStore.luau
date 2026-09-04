--!strict

local runService = game:GetService("RunService")

local ClientAbilityStore = {}
ClientAbilityStore.__index = ClientAbilityStore

local marketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local MainElements = GameAssets:WaitForChild("MainElements")
local DragonMaster = MainElements:WaitForChild("DragonMaster")
local UX = GameAssets:WaitForChild("UX")
local UnlockedIndicator = UX:WaitForChild("UnlockedIndicator")

local Abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local PlayerAttributeKeys = require("@game/ReplicatedStorage/Shared/PlayerAttributeKeys")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local clientPlayerVariables = require("./ClientPlayerVariables")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")
local ProximityThresholdTracker = require("./ProximityThresholdTracker")

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("ElementalAbilities")

local FLOATING_CIRCLE_PART_RADIUS = 3

local MAX_ABILITIES_PER_ELEMENT = 15

local GREETING_DISTANCE = 10

-- the store auto-opens when the player gets this close to the vendor; deliberately smaller than
-- GREETING_DISTANCE (whose leave event closes the store) so the open/close thresholds have
-- hysteresis instead of flickering at one boundary
local AUTO_OPEN_DISTANCE = 8

-- this is all stuff for the exclamation point--somewhat strangely named,
-- copied over from claimable crystals
local UNLOCKED_INDICATOR_NAME = "DmUnlockedIndicator"
local CLAIMABLE_BASE_HEIGHT = 3
local CLAIMABLE_PULSE_AMPLITUDE = 0.5

local EXCLAMATION_PULSE_DURATION = 1
local EXCLAMATION_PULSE_AMPLITUDE = 1

type ClientAbilityStoreFields = {
	abilityDetailDialogEquipButtonConnect: any,
	abilityDetailDialogExitButtonConnect: any,
	abilityDetailDialogOutsideBackgroundConnect: any,
	abilityDetailDialogUnequipButtonConnect: any,
	abilitySlotDetailDialogBuyConnect: any,
	abilitySlotDetailDialogExitButtonConnect: any,
	abilitySlotDetailDialogOutsideBackgroundConnect: any,
	abilityStatuses: { [any]: any },
	autoOpenTracker: any,
	dragonMasterFolder: any,
	emptySlotCount: any,
	hoverAnimationTrack: any,
	moteSpeedFactor: number,
	proximityThresholdTracker: any,
	robuxPriceMap: { [any]: any },
	unlockedIndicator: any,
	waveAnimationTrack: any,
}

export type ClientAbilityStore = typeof(setmetatable({} :: ClientAbilityStoreFields, ClientAbilityStore))

function ClientAbilityStore.getGuiRoot(self: ClientAbilityStore)
	return GuiRoot
end

function ClientAbilityStore.notifyForceEnd(self: ClientAbilityStore)
	self:cleanupStore()
end

function ClientAbilityStore.notifyClickOutside(self: ClientAbilityStore)
	self:notifyForceEnd()
end

function ClientAbilityStore.doAllowStoreAutoOpen(self: ClientAbilityStore): boolean
	return true
end

-- opens the store as if the player had used the old proximity prompt; called from the auto-open
-- tracker's enter event
local function tryAutoOpenStore(self: ClientAbilityStore)
	if GuiRoot.Enabled then
		-- already open
		return
	end
	if not overlayTracker:canStoreAutoOpen() then
		return
	end

	self:beginStore()
end

function ClientAbilityStore.getHudElements(self: ClientAbilityStore)
	-- gems no longer used for ability costs (2026-august-20); was: {COINS, GEMS}
	return {enums.HudElements.COINS}
end

function ClientAbilityStore.beginStore(self: ClientAbilityStore)
	self:updatePlayerLevels()
	self:updateAbilityDisplay()
	self:updateEquippedAbilityDisplay()

	local AbilityDetail = GuiRoot:WaitForChild("AbilityDetail")
	AbilityDetail.Visible = false

	local AbilitySlotDetail = GuiRoot:WaitForChild("AbilitySlotDetail")
	AbilitySlotDetail.Visible = false

	local rig = self.dragonMasterFolder:FindFirstChild("DragonMaster")

	local audioBeginStore = rig:FindFirstChild("AudioDmBeginStore")
	audioBeginStore:Play()

	self:setDragonMasterAnimationDefault()
	self:removeDragonMasterExclamationPoint()
	self.moteSpeedFactor = 1

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientAbilityStore.cleanupStore(self: ClientAbilityStore)
	GuiRoot.Enabled = false

	self:cleanupAbilityDisplay()

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
end

function ClientAbilityStore.updatePlayerLevels(self: ClientAbilityStore)
	local Main = GuiRoot:WaitForChild("Main")

	local PlayerLevels = Main:WaitForChild("PlayerLevels")

	for _, inst in PlayerLevels:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end

		if string.sub(inst.Name, 1, 10) == "Configured" then
			-- leftover from last configure, destroy it
			inst:Destroy()
			continue
		end


		inst.Visible = false
	end

	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		local playerAttributeKeyIsUnlocked = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
		local isUnlocked = clientPlayerAttributesManager:get(playerAttributeKeyIsUnlocked)
		if not isUnlocked then
			local path = Elements.getAbilityStoreLockedLevelPathForPrimaryElement(primaryElement)
			local levelTemplate = utils.getPathReference(Main, path)
			if not levelTemplate then
				continue
			end

			local levelElement: any = levelTemplate:Clone()
			levelElement.Name = "Configured" .. levelElement.Name
			levelElement.Visible = true
			levelElement.Parent = PlayerLevels
			continue
		end

		local path = Elements.getAbilityStoreLevelPathForPrimaryElement(primaryElement)
		local levelTemplate = utils.getPathReference(Main, path)
		if not levelTemplate then
			continue
		end

		local levelElement: any = levelTemplate:Clone()
		levelElement.Name = "Configured" .. levelElement.Name

		local textLabel: any = utils.findFirstDescendant(levelElement, "TextLabel")
		if not textLabel then
			continue
		end

		local playerAttributeKeyLevel = Elements.getLevelKeyForPrimaryElement(primaryElement)
		local level = clientPlayerAttributesManager:get(playerAttributeKeyLevel)
		textLabel.Text = tonumber(level)

		levelElement.Visible = true
		levelElement.Parent = PlayerLevels
	end

end

function ClientAbilityStore.beginAbilitySlotDialog(self: ClientAbilityStore, primaryElement: any, level: any)
	local rig = self.dragonMasterFolder:FindFirstChild("DragonMaster")

	local audioBeginStore = rig:FindFirstChild("AudioDmBeginStore")
	audioBeginStore:Play()

	local AbilitySlotDetail = GuiRoot:WaitForChild("AbilitySlotDetail")
	local outsideBackground = AbilitySlotDetail:WaitForChild("OutsideBackground")
	self.abilitySlotDetailDialogOutsideBackgroundConnect = outsideBackground.Activated:Connect(
		function()
			local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

			local audioClick = rig:FindFirstChild("AudioDmClick")
			audioClick:Play()

			self:cleanupAbilitySlotDialog()
		end
	)

	local AbilitySlotDialog = AbilitySlotDetail:WaitForChild("AbilitySlotDialog")

	for _, inst in AbilitySlotDialog:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end
	end

	if primaryElement == enums.PrimaryElements.NONE then
		local LockedDetail = AbilitySlotDialog:FindFirstChild("LockedDetail")
		local Item = LockedDetail:FindFirstChild("Item")
		Item.Visible = false
		local AbilityDescription = LockedDetail:FindFirstChild("AbilityDescription")
		AbilityDescription.Text = string.format("Select any unlocked skill to equip in this slot")
		AbilityDescription.TextColor3 = Color3.fromRGB(192, 192, 192)

		local UnlockNowLocked = AbilitySlotDialog:FindFirstChild("UnlockNowLocked")
		UnlockNowLocked.Visible = false

		local UnlockForRobux = AbilitySlotDialog:FindFirstChild("UnlockForRobux")
		UnlockForRobux.Visible = false
	else

		local LockedDetail = AbilitySlotDialog:FindFirstChild("LockedDetail")
		local Item = LockedDetail:FindFirstChild("Item")
		Item.Visible = true
		local AbilityDescription = LockedDetail:FindFirstChild("AbilityDescription")
		AbilityDescription.Text = string.format("Unlock this slot at Elemental Level %i", level)
		AbilityDescription.TextColor3 = utils.get2DColorForPrimaryElement(primaryElement)

		local UnlockNowLocked = AbilitySlotDialog:FindFirstChild("UnlockNowLocked")
		UnlockNowLocked.Visible = true

		local UnlockForRobux = AbilitySlotDialog:FindFirstChild("UnlockForRobux")
		local robuxProductId = Elements.getUnlockAbilitySlotRobuxProductIdForPrimaryElement(primaryElement)
		if self.robuxPriceMap[robuxProductId] then
			UnlockForRobux.Visible = true
			local Price = UnlockForRobux:FindFirstChild("Price")
			Price.Text = tostring(self.robuxPriceMap[robuxProductId])

			self.abilitySlotDetailDialogBuyConnect = UnlockForRobux.Activated:Connect(
				function()
					--print("prompting to buy ability slot for robux here")
					local isSuccess, errorMessage = pcall(
						function()
							marketplaceService:PromptProductPurchase(player, robuxProductId)
						end
					)

					if isSuccess then
						--print("yes prompted")
					else
						warn("error prompting for robux purchase", errorMessage)
					end

					self:cleanupAbilitySlotDialog()
				end
			)
		else
			UnlockForRobux.Visible = false
		end

	end

	local header = AbilitySlotDialog:FindFirstChild("Header")

	local exitButton = header:WaitForChild("ExitButton")
	self.abilitySlotDetailDialogExitButtonConnect = exitButton.Activated:Connect(
		function()
			local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

			local audioClick = rig:FindFirstChild("AudioDmClick")
			audioClick:Play()

			self:cleanupAbilitySlotDialog()
		end
	)

	header.Visible = true

	AbilitySlotDetail.Visible = true
end

function ClientAbilityStore.cleanupAbilitySlotDialog(self: ClientAbilityStore)
	if self.abilitySlotDetailDialogOutsideBackgroundConnect then
		self.abilitySlotDetailDialogOutsideBackgroundConnect:Disconnect()
		self.abilitySlotDetailDialogOutsideBackgroundConnect = nil
	end

	if self.abilitySlotDetailDialogBuyConnect then
		self.abilitySlotDetailDialogBuyConnect:Disconnect()
		self.abilitySlotDetailDialogBuyConnect = nil
	end

	if self.abilitySlotDetailDialogExitButtonConnect then
		self.abilitySlotDetailDialogExitButtonConnect:Disconnect()
		self.abilitySlotDetailDialogExitButtonConnect = nil
	end

	local AbilitySlotDetail = GuiRoot:WaitForChild("AbilitySlotDetail")
	AbilitySlotDetail.Visible = false
end


function ClientAbilityStore.beginAbilityDialog(self: ClientAbilityStore, ability: any)
	local rig = self.dragonMasterFolder:FindFirstChild("DragonMaster")

	local audioBeginStore = rig:FindFirstChild("AudioDmBeginStore")
	audioBeginStore:Play()

	local AbilityDetail = GuiRoot:WaitForChild("AbilityDetail")
	local outsideBackground = AbilityDetail:WaitForChild("OutsideBackground")
	self.abilityDetailDialogOutsideBackgroundConnect = outsideBackground.Activated:Connect(
		function()
			local audioClick = rig:FindFirstChild("AudioDmClick")
			audioClick:Play()

			self:cleanupAbilityDialog()
		end
	)

	local AbilityDialog = AbilityDetail:WaitForChild("AbilityDialog")

	for _, inst in AbilityDialog:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end

		inst.Visible = false
	end

	local primaryElement = Abilities.getPrimaryElementForAbility(ability)

	local templateName = Elements.getAbilityStoreDetailTemplateForPrimaryElement(primaryElement)
	local detail = AbilityDialog:FindFirstChild(templateName)
	detail.Visible = true

	local bigImage = detail:WaitForChild("Item")
	bigImage.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))

	local description = detail:WaitForChild("AbilityDescription")
	description.Text = Abilities.getDescriptionForAbility(ability)
	local status = enums.AbilityStatus.LOCKED
	if self.abilityStatuses[ability] then
		status = self.abilityStatuses[ability]
	end

	if status == enums.AbilityStatus.LOCKED then
		local lockedName = Elements.getAbilityStoreDetailLockedTemplateForPrimaryElement(primaryElement)
		local locked = AbilityDialog:FindFirstChild(lockedName)
		locked.Text = string.format("UNLOCKS AT LEVEL %i", Abilities.getUnlockLevelForAbility(ability))
		locked.Visible = true
	elseif status == enums.AbilityStatus.UNLOCKED then
		-- legacy (2026-august-20): ability costs used to be per-element gems, now unified coins
		-- local playerAttributesKeyGems = Elements.getGemsKeyForPrimaryElement(primaryElement)
		-- local playerGemCount = clientPlayerAttributesManager:get(playerAttributesKeyGems)
		local playerCoinCount = clientPlayerAttributesManager:get(PlayerAttributeKeys.COINS)

		local isSlotAvailable = (self.emptySlotCount > 0)
		local replaceAbility = Abilities.getReplaceAbilityForAbility(ability)
		if replaceAbility and self.abilityStatuses[replaceAbility] == enums.AbilityStatus.EQUIPPED then
			isSlotAvailable = true
		end

		if not isSlotAvailable then
			local noAvailableSlotsName = Elements.getAbilityStoreDetailNoAvailableSlotsTemplateForPrimaryElement(primaryElement)
			local noAvailableSlots = AbilityDialog:FindFirstChild(noAvailableSlotsName)
			local price = noAvailableSlots:WaitForChild("Price")
			price.Text = tostring(Abilities.getEquipCoinCostForAbility(ability))
			noAvailableSlots.Visible = true

			local equipTextLabel = AbilityDialog:FindFirstChild("EquipTextLabel")
			equipTextLabel.Visible = true

		elseif Abilities.getEquipCoinCostForAbility(ability) > playerCoinCount then
			-- legacy (2026-august-20): used to pick a per-element "not enough gems" template;
			-- costs are now unified coins, so Elements.luau maps every element to the same
			-- "NotEnoughCoins" instance (abilityStoreDetailNotEnoughCoinsTemplate)
			-- local notEnoughGemsName = Elements.getAbilityStoreDetailNotEnoughGemsTemplateForPrimaryElement(primaryElement)
			local notEnoughCoinsName = Elements.getAbilityStoreDetailNotEnoughCoinsTemplateForPrimaryElement(primaryElement)
			local notEnoughCoins = AbilityDialog:FindFirstChild(notEnoughCoinsName)
			local price = notEnoughCoins:WaitForChild("Price")
			price.Text = tostring(Abilities.getEquipCoinCostForAbility(ability))
			notEnoughCoins.Visible = true

			local equipTextLabel = AbilityDialog:FindFirstChild("EquipTextLabel")
			equipTextLabel.Visible = true
		else

			local equipName = Elements.getAbilityStoreDetailEquipTemplateForPrimaryElement(primaryElement)
			local equipButton = AbilityDialog:FindFirstChild(equipName)
			equipButton.Visible = true
			self.abilityDetailDialogEquipButtonConnect = equipButton.Activated:Connect(
				function()
					--print("try equip")
					RemoteEvents.TryEquipAbility:FireServer(ability)

					-- either wait for info from server or immediately close...
					self:cleanupAbilityDialog()
				end
			)
			local price = equipButton:WaitForChild("Price")
			price.Text = tostring(Abilities.getEquipCoinCostForAbility(ability))

			local equipTextLabel = AbilityDialog:FindFirstChild("EquipTextLabel")
			equipTextLabel.Visible = true
		end
	elseif status == enums.AbilityStatus.EQUIPPED then
		local unequipName = Elements.getAbilityStoreDetailUnequipTemplateForPrimaryElement(primaryElement)
		local unequipButton = AbilityDialog:FindFirstChild(unequipName)
		unequipButton.Visible = true
		self.abilityDetailDialogUnequipButtonConnect = unequipButton.Activated:Connect(
			function()
				--print("try unequip", ability)
				RemoteEvents.TryUnequipAbility:FireServer(ability)

				self:cleanupAbilityDialog()

				local audioClick = rig:FindFirstChild("AudioDmClick")
				audioClick:Play()
			end
		)
	elseif status == enums.AbilityStatus.REPLACED then
		-- can't get here
	else
		warn("unknown ability status", ability, status)
	end

	local header = AbilityDialog:FindFirstChild("Header")
	local title = header:FindFirstChild("TextLabel")
	title.Text = Abilities.getDisplayNameForAbility(ability)

	local exitButton = header:WaitForChild("ExitButton")
	self.abilityDetailDialogExitButtonConnect = exitButton.Activated:Connect(
		function()
			local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

			local audioClick = rig:FindFirstChild("AudioDmClick")
			audioClick:Play()

			self:cleanupAbilityDialog()
		end
	)

	header.Visible = true

	AbilityDetail.Visible = true
end

function ClientAbilityStore.cleanupAbilityDialog(self: ClientAbilityStore)
	if self.abilityDetailDialogEquipButtonConnect then
		self.abilityDetailDialogEquipButtonConnect:Disconnect()
		self.abilityDetailDialogEquipButtonConnect = nil
	end

	if self.abilityDetailDialogUnequipButtonConnect then
		self.abilityDetailDialogUnequipButtonConnect:Disconnect()
		self.abilityDetailDialogUnequipButtonConnect = nil
	end

	if self.abilityDetailDialogOutsideBackgroundConnect then
		self.abilityDetailDialogOutsideBackgroundConnect:Disconnect()
		self.abilityDetailDialogOutsideBackgroundConnect = nil
	end

	if self.abilityDetailDialogExitButtonConnect then
		self.abilityDetailDialogExitButtonConnect:Disconnect()
		self.abilityDetailDialogExitButtonConnect = nil
	end

	local AbilityDetail = GuiRoot:WaitForChild("AbilityDetail")
	AbilityDetail.Visible = false
end

function ClientAbilityStore.updateAbilityDisplay(self: ClientAbilityStore)
	local Main = GuiRoot:WaitForChild("Main")
	local AbilitiesDialog = Main:WaitForChild("Abilities")

	local AbilityIconScroll = AbilitiesDialog:WaitForChild("AbilityIconScroll")

	-- remove elements under AbilityIconScroll or make them all invisible
	for _, inst in AbilityIconScroll:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			if inst.ClassName == "UIGridLayout" then
				inst.FillDirectionMaxCells = MAX_ABILITIES_PER_ELEMENT
			end
			continue
		end

		if string.sub(inst.Name, 1, 10) == "Configured" then
			-- leftover from last configure, destroy it
			inst:Destroy()
			continue
		end

		inst.Visible = false
		continue
	end

	-- now copy the template for each primary element
	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		-- get all abilities in this element, in sorted order
		local realAbilityCount = 0
		local abilities = Abilities.getAbilitiesSortedByPrimaryElement(primaryElement)
		for _, ability in abilities do
			realAbilityCount += 1
			local status = enums.AbilityStatus.LOCKED
			if self.abilityStatuses[ability] then
				status = self.abilityStatuses[ability]
			else
				print("do not have status for", ability)
			end

			local button
			if status == enums.AbilityStatus.LOCKED then
				local template = AbilityIconScroll:FindFirstChild(Elements.getAbilityStoreLockedTemplateForPrimaryElement(primaryElement))
				button = template:Clone()
				button.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))
				button.Activated:Connect(
					function()
						self:beginAbilityDialog(ability)
					end
				)
				local textLabel = button:FindFirstChild("TextLabel")
				textLabel.Text = Abilities.getUnlockLevelForAbility(ability)
			elseif status == enums.AbilityStatus.UNLOCKED then
				local template = AbilityIconScroll:FindFirstChild(Elements.getAbilityStoreUnlockedTemplateForPrimaryElement(primaryElement))
				button = template:Clone()
				button.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))
				button.Activated:Connect(
					function()
						self:beginAbilityDialog(ability)
					end
				)
				local badge = button:FindFirstChild("Badge")
				local replaceAbility = Abilities.getReplaceAbilityForAbility(ability)
				if replaceAbility and self.abilityStatuses[replaceAbility] ~= enums.AbilityStatus.REPLACED then
					-- equipped will replace/upgrade others
					local textLabel = button:FindFirstChild("TextLabel")
					textLabel.Text = "UPGRADE"
					badge.Visible = true
					badge.Text = Abilities.getUpgradeBadgeTextForAbility(ability)
				else
					badge.Visible = false
				end

			elseif status == enums.AbilityStatus.EQUIPPED then
				local template = AbilityIconScroll:FindFirstChild(Elements.getAbilityStoreEquippedTemplateForPrimaryElement(primaryElement))
				button = template:Clone()
				button.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))
				button.Activated:Connect(
					function()
						self:beginAbilityDialog(ability)
					end
				)
				local badge = button:FindFirstChild("Badge")
				if Abilities.getReplaceAbilityForAbility(ability) then
					badge.Visible = true
					badge.Text = Abilities.getUpgradeBadgeTextForAbility(ability)
				else
					badge.Visible = false
				end
			elseif status == enums.AbilityStatus.REPLACED then
				local template = AbilityIconScroll:FindFirstChild(Elements.getAbilityStoreLockedTemplateForPrimaryElement(primaryElement))
				button = template:Clone()
				button.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))
				local textLabel = button:FindFirstChild("TextLabel")
				textLabel:Destroy()
				local lock = button:FindFirstChild("Lock")
				lock:Destroy()
			else
				warn("unknown ability status", ability, status)
				continue
			end

			button.Name = "Configured" .. button.Name

			button.Visible = true
			button.Parent = AbilityIconScroll
		end

		for i = realAbilityCount + 1, MAX_ABILITIES_PER_ELEMENT do
			local template = AbilityIconScroll:FindFirstChild(Elements.getAbilityStoreComingSoonTemplateForPrimaryElement(primaryElement))
			local button: any = template:Clone()

			button.Visible = true
			button.Parent = AbilityIconScroll
		end

	end
end

function ClientAbilityStore.cleanupAbilityDisplay(self: ClientAbilityStore)
	local Main = GuiRoot:WaitForChild("Main")
	local AbilitiesDialog = Main:WaitForChild("Abilities")

	local AbilityIconScroll = AbilitiesDialog:WaitForChild("AbilityIconScroll")

	-- remove elements under AbilityIconScroll that we created
	for _, inst in AbilityIconScroll:GetChildren() do
		if string.sub(inst.Name, 1, 10) == "Configured" then
			-- leftover from last configure, destroy it
			inst:Destroy()
			continue
		end
	end
end

function ClientAbilityStore.updateEquippedAbilityDisplay(self: ClientAbilityStore)
	local Main = GuiRoot:WaitForChild("Main")
	local EquippedAbilities = Main:WaitForChild("EquippedAbilities")
	local ScrollingFrame = EquippedAbilities:WaitForChild("ScrollingFrame")

	local templateEquippedAbility
	local templateEmptySlot

	-- remove elements under ScrollingFrame or make them all invisible
	for _, inst in ScrollingFrame:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end

		if string.sub(inst.Name, 1, 10) == "Configured" then
			-- leftover from last configure, destroy it
			inst:Destroy()
			continue
		end

		if inst.Name == "TemplateEquippedAbility" then
			templateEquippedAbility = inst
		end

		if inst.Name == "TemplateEmptySlot" then
			templateEmptySlot = inst
		end

		inst.Visible = false
	end

	local countEquipped = 0
	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		local abilities = Abilities.getAbilitiesSortedByPrimaryElement(primaryElement)
		for _, ability in abilities do
			if self.abilityStatuses[ability] ~= enums.AbilityStatus.EQUIPPED then
				continue
			end

			local equippedAbility: any = templateEquippedAbility:Clone()
			equippedAbility.Name = "Configured" .. equippedAbility.Name
			equippedAbility.Image = "rbxassetid://" .. tostring(Abilities.getStoreImageAssetIdForAbility(ability))

			equippedAbility.Activated:Connect(
				function()
					self:beginAbilityDialog(ability)
				end
			)
			equippedAbility.Visible = true
			equippedAbility.Parent = ScrollingFrame

			countEquipped += 1
		end
	end

	local unlockedAbilitySlotCount = clientPlayerVariables:get(Attributes.UNLOCKED_ABILITY_SLOTS)

	self.emptySlotCount = unlockedAbilitySlotCount - countEquipped

	for i = countEquipped + 1, unlockedAbilitySlotCount do
		local emptySlot: any = templateEmptySlot:Clone()
		emptySlot.Name = "Configured" .. emptySlot.Name
		emptySlot.Visible = true
		emptySlot.Activated:Connect(
			function()
				self:beginAbilitySlotDialog(enums.PrimaryElements.NONE)
			end
		)
		emptySlot.Parent = ScrollingFrame
	end

	local lockedSlotsStr = clientPlayerVariables:get(Attributes.UNLOCKABLE_ABILITY_SLOT_DATA)
	local iterFunc = string.gmatch(lockedSlotsStr, "%S+")

	while true do
		local primaryElementStr = iterFunc()
		if not primaryElementStr then
			break
		end

		local primaryElement = tonumber(primaryElementStr) :: number
		local level = tonumber(iterFunc())

		local lockedSlotName = Elements.getAbilityStoreSlotLockedTemplateForPrimaryElement(primaryElement)
		local templateLockedSlot = ScrollingFrame:FindFirstChild(lockedSlotName)
		if not templateLockedSlot then
			warn("missing template for locked ability slot", lockedSlotName)
			continue
		end

		local lockedSlot: any = templateLockedSlot:Clone()
		lockedSlot.Name = "Configured" .. lockedSlot.Name
		lockedSlot.Text = tostring(level)
		lockedSlot.Activated:Connect(
			function()
				self:beginAbilitySlotDialog(primaryElement, level)
			end
		)
		lockedSlot.Visible = true
		lockedSlot.Parent = ScrollingFrame
	end

end

function ClientAbilityStore.resetAbilityDisplay(self: ClientAbilityStore)
	self:cleanupAbilityDisplay()

	self:updatePlayerLevels()
	self:updateAbilityDisplay()
	self:updateEquippedAbilityDisplay()
end

function ClientAbilityStore.setPlayerAbilityStatuses(self: ClientAbilityStore, abilityStatuses: any)
	--sadly, roblox network messages convent non-sequential numerically-keyed dictionaries into string keys; we need to undo that
	self.abilityStatuses = {}
	for abilityStr, abilityStatus in abilityStatuses do
		local ability = tonumber(abilityStr)
		self.abilityStatuses[ability] = abilityStatus
	end

	if GuiRoot.Enabled then
		--print("updating ability display")
		self:resetAbilityDisplay()
	end

end

function ClientAbilityStore.notifyAbilityStatuses(self: ClientAbilityStore, abilityStatuses: any)
	self:setPlayerAbilityStatuses(abilityStatuses)

	if not GuiRoot.Enabled then
		local areAnyUnlocked = false
		for abilityStr, abilityStatus in abilityStatuses do
			if abilityStatus ~= enums.AbilityStatus.UNLOCKED then
				continue
			end

			areAnyUnlocked = true
			break
		end

		if areAnyUnlocked then
			self:setDragonMasterAnimationWave()
			self:setDragonMasterExclamationPoint()
			self.moteSpeedFactor = 2
		end
	end
end

function ClientAbilityStore.notifyEquipAbilityStatus(self: ClientAbilityStore, isSuccess: any)
	local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

	if isSuccess then
		local audioEquipAbility = rig:FindFirstChild("AudioDmEquipAbility")
		audioEquipAbility:Play()
	else
		local audioInvalidClick = rig:FindFirstChild("AudioDmInvalidClick")
		audioInvalidClick:Play()
	end
end

function ClientAbilityStore.notifyUpdatePurchasedSlotUnlocks(self: ClientAbilityStore)
	if GuiRoot.Enabled then
		self:resetAbilityDisplay()
	end
end

function ClientAbilityStore.notifyPlayerLevelChanged(self: ClientAbilityStore)
	if GuiRoot.Enabled then
		-- not sure how you could gain a level while the store is up, but this will enable anything now unlocked if it happens
		self:resetAbilityDisplay()
	end
end

function ClientAbilityStore.setDragonMasterAnimationDefault(self: ClientAbilityStore)
	-- make the dragon master move up/down

	if not self.hoverAnimationTrack then
		local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

		local humanoid = rig:WaitForChild("Humanoid")
		local animator = humanoid:WaitForChild("Animator")
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://73148151591226"
		self.hoverAnimationTrack = animator:LoadAnimation(animation)
		self.hoverAnimationTrack.Looped = true
	end

	if self.waveAnimationTrack then
		self.waveAnimationTrack:Stop()
	end
	self.hoverAnimationTrack:Play()
end

function ClientAbilityStore.setDragonMasterAnimationWave(self: ClientAbilityStore)
	-- make the dragon master wave to the player a bit

	if not self.waveAnimationTrack then
		local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

		local humanoid = rig:WaitForChild("Humanoid")
		local animator = humanoid:WaitForChild("Animator")
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://118547860722887"
		self.waveAnimationTrack = animator:LoadAnimation(animation)
		self.waveAnimationTrack.Looped = true
	end

	if self.hoverAnimationTrack then
		self.hoverAnimationTrack:Stop()
	end
	self.waveAnimationTrack:Play()
end

function ClientAbilityStore.setDragonMasterExclamationPoint(self: ClientAbilityStore)
	local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")
	local instHeight = utils.getInstanceHeight(rig)

	local dragonMasterPosition = rig:getPivot().Position

	local unlockedIndicator: any = UnlockedIndicator:Clone()
	unlockedIndicator.Name = UNLOCKED_INDICATOR_NAME
	utils.setPropertyTreeBaseParts(unlockedIndicator, "Anchored", true)

	local unlockedIndicatorBottomY = dragonMasterPosition.Y + CLAIMABLE_BASE_HEIGHT + CLAIMABLE_PULSE_AMPLITUDE + instHeight + math.max(3, instHeight * 0.15)
	local unlockedIndicatorTopY = unlockedIndicatorBottomY + EXCLAMATION_PULSE_AMPLITUDE * 2
	local unlockedPosition = Vector3.new(dragonMasterPosition.X, unlockedIndicatorBottomY, dragonMasterPosition.Z)
	local unlockedCFrame = CFrame.new(unlockedPosition) * CFrame.Angles(0, math.rad(90), 0)
	local unlockedTopPosition = Vector3.new(dragonMasterPosition.X, unlockedIndicatorTopY, dragonMasterPosition.Z)
	local topCFrame = CFrame.new(unlockedTopPosition) * CFrame.Angles(0, math.rad(90), 0)

	unlockedIndicator:PivotTo(unlockedCFrame)
	unlockedIndicator.Parent = workspace

	local duration = EXCLAMATION_PULSE_DURATION
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true, -- reverses afterwards
		0
	)

	PivotToTween(unlockedIndicator, tweenInfo, topCFrame):Play()

	self.unlockedIndicator = unlockedIndicator
end

function ClientAbilityStore.removeDragonMasterExclamationPoint(self: ClientAbilityStore)
	if self.unlockedIndicator then
		self.unlockedIndicator:Destroy()
		self.unlockedIndicator = nil
	end
end

function ClientAbilityStore.initWorldInterface(self: ClientAbilityStore)
	local dragonMasterFolder: any = DragonMaster:Clone()
	dragonMasterFolder.Parent = workspace

	self.dragonMasterFolder = dragonMasterFolder

	local rig = self.dragonMasterFolder:WaitForChild("DragonMaster")

	local objProximityPrompt: any = utils.findFirstDescendant(self.dragonMasterFolder, "ProximityPrompt")
	objProximityPrompt.Enabled = false

	local Main = GuiRoot:WaitForChild("Main")
	local Abilities = Main:WaitForChild("Abilities")
	Abilities:WaitForChild("Header"):WaitForChild("ExitButton").Activated:Connect(
		function()
			local audioClick = rig:FindFirstChild("AudioDmClick")
			audioClick:Play()

			self:cleanupStore()
		end
	)

	self.proximityThresholdTracker = ProximityThresholdTracker.new(rig:GetPivot().Position, GREETING_DISTANCE)

	self.proximityThresholdTracker:getEnterEvent():Connect(
		function()
			--print("need cooldown, but could greet here")

			local audioHello = rig:FindFirstChild("AudioDmHello")
			audioHello:Play()
		end
	)

	self.proximityThresholdTracker:getLeaveEvent():Connect(
		function()
			if not GuiRoot.Enabled then
				return
			end

			self:cleanupStore()
		end
	)

	self.autoOpenTracker = ProximityThresholdTracker.new(rig:GetPivot().Position, AUTO_OPEN_DISTANCE)

	self.autoOpenTracker:getEnterEvent():Connect(function()
		tryAutoOpenStore(self)
	end)

	self:setDragonMasterAnimationDefault()

	-- make the parts circle the dragon master

	local humanoidRootPart = rig:WaitForChild("HumanoidRootPart")

	local redPart = dragonMasterFolder:FindFirstChild("RedMote"):FindFirstChild("CenterPart")
	local greenPart = dragonMasterFolder:FindFirstChild("GreenMote"):FindFirstChild("CenterPart")
	local bluePart = dragonMasterFolder:FindFirstChild("BlueMote"):FindFirstChild("CenterPart")

	self.moteSpeedFactor = 1

	local time = 0
	local baseCFrame = CFrame.new(Vector3.new(FLOATING_CIRCLE_PART_RADIUS, 0, 0))
	runService.PostSimulation:Connect(
		function(deltaTime)
			time = (time + deltaTime)
			local redAngle = time * 3.25 * self.moteSpeedFactor
			local greenAngle = time * 2.25 * self.moteSpeedFactor
			local blueAngle = -time * 2 * self.moteSpeedFactor

			local redCFrame = (CFrame.fromEulerAnglesXYZ(0, redAngle, 0) * baseCFrame) + humanoidRootPart.Position
			redPart:PivotTo(redCFrame)

			local greenCFrame = (CFrame.fromEulerAnglesXYZ(0, greenAngle, 0) * baseCFrame) + humanoidRootPart.Position
			greenPart:PivotTo(greenCFrame)

			local blueCFrame = (CFrame.fromEulerAnglesXYZ(0, blueAngle, 0) * baseCFrame) + humanoidRootPart.Position
			bluePart:PivotTo(blueCFrame)
		end
	)
end

function ClientAbilityStore.init(self: ClientAbilityStore)
	self:initWorldInterface()

	local primaryElements = Elements.getPrimaryElementsSorted()
	for _, primaryElement in primaryElements do
		local robuxProductId = Elements.getUnlockAbilitySlotRobuxProductIdForPrimaryElement(primaryElement)

		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(robuxProductId, Enum.InfoType.Product)
					end
				)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						self.robuxPriceMap[robuxProductId] = productInfo.PriceInRobux
					else
						print("unlock ability slot product not for robux sale", primaryElement, productInfo)
					end
				end
			end
		)
	end

end

function ClientAbilityStore.new(): ClientAbilityStore
	local self = setmetatable({} :: ClientAbilityStoreFields, ClientAbilityStore)

	self.abilityStatuses = {}

	-- map from robux product id to price
	self.robuxPriceMap = {}

	return self
end

local singleton = ClientAbilityStore.new()

return singleton
