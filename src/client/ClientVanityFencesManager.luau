--!strict

local ClientVanityFencesManager = {}
ClientVanityFencesManager.__index = ClientVanityFencesManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")
local clientVanityPreviewManager = require("./ClientVanityPreviewManager")
local clientVanityUnlockedManager = require("./ClientVanityUnlockedManager")

local player = game:GetService("Players").LocalPlayer :: Player

local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so it is untyped here
local GuiRoot: any = PlayerGui:WaitForChild("VanityFences")

type ClientVanityFencesManagerFields = {
	selectedTabIndex: number,
	vanityPlacement: number?,
	connections: { RBXScriptConnection },
	isPreviewing: boolean,
}

export type ClientVanityFencesManager = typeof(setmetatable({} :: ClientVanityFencesManagerFields, ClientVanityFencesManager))

function ClientVanityFencesManager.getVanityPlacementByIndex(index: number): number?
	if index == 1 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_1
	elseif index == 2 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_2
	elseif index == 3 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_3
	elseif index == 4 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_4
	elseif index == 5 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_5
	elseif index == 6 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_6
	elseif index == 7 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_7
	elseif index == 8 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_8
	elseif index == 9 then
		return enums.VanityPlacements.MAIN_PLOT_FENCE_9
	end

	warn("unknown fence vanity placement index", index)

	return nil
end

function ClientVanityFencesManager.getGuiRoot(self: ClientVanityFencesManager): Instance
	return GuiRoot
end

function ClientVanityFencesManager.notifyForceEnd(self: ClientVanityFencesManager)
	self:cleanupDialog()
end

function ClientVanityFencesManager.notifyClickOutside(self: ClientVanityFencesManager)
	self:notifyForceEnd()
end

function ClientVanityFencesManager.doZoomCamera(self: ClientVanityFencesManager): boolean
	return false
end

function ClientVanityFencesManager.getHudElements(self: ClientVanityFencesManager): { number }
	return {}
end

function ClientVanityFencesManager.setupVanityOptions(self: ClientVanityFencesManager)
	local Main = GuiRoot:WaitForChild("Main")

	local VanityOptions = Main:WaitForChild("VanityOptions")
	local Header = VanityOptions:WaitForChild("Header")
	local Title = Header:FindFirstChild("Title")
	Title.Text = string.format("Fence Section %i", self.selectedTabIndex)

	local VanityOptionsScroll = VanityOptions:WaitForChild("VanityOptionsScroll")

	for _, inst in VanityOptionsScroll:GetChildren() do
		if string.sub(inst.ClassName, 1, 2) == "UI" then
			continue
		end

		inst.Visible = false
	end

	local VanityEquippedTemplate = VanityOptionsScroll:WaitForChild("VanityEquippedTemplate")
	local VanityReadyToEquipTemplate = VanityOptionsScroll:WaitForChild("VanityReadyToEquipTemplate")
	local VanityLockedTemplate = VanityOptionsScroll:WaitForChild("VanityLockedTemplate")
	local VanityReadyToUnlockTemplate = VanityOptionsScroll:WaitForChild("VanityReadyToUnlockTemplate")

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)
	local vanityDataFolder = splendidDataFolder:WaitForChild("Vanity")
	local vanityPlacementsDataFolder: any = vanityDataFolder:FindFirstChild(Constants.VANITY_PLACEMENTS_NAME)

	local vanityPlacement = self.vanityPlacement :: number
	local vanityPlacementName = enums.getName(enums.VanityPlacements, vanityPlacement) :: string

	local children = vanityDataFolder:WaitForChild(Constants.VANITY_FENCE_NAME):GetChildren()
	table.sort(children,
		function (a, b)
			return (a:GetAttribute(Attributes.INDEX) :: number) < (b:GetAttribute(Attributes.INDEX) :: number)
		end
	)
	for _, inst in children do
		--print("adding to list", inst)
		local vanityComponentName = inst.Name

		local vanityComponentState = inst:GetAttribute(Attributes.STATE)
		local rarity = inst:GetAttribute(Attributes.RARITY) :: number
		local isUnlockable = inst:GetAttribute(Attributes.UNLOCKABLE)

		local vanityInst: any
		if vanityComponentState == enums.VanityComponentState.LOCKED then
			--print("vanityComponentName", vanityComponentName, "is locked")
			if isUnlockable then
				-- player is holding the blueprint
				vanityInst = (VanityReadyToUnlockTemplate :: any):Clone()
				local titleTextLabel = vanityInst:FindFirstChild("ItemName")
				titleTextLabel.Text = inst:GetAttribute(Attributes.DISPLAY_NAME)
				titleTextLabel.TextColor3 = utils.getColorForRarity(rarity)
				titleTextLabel:FindFirstChild("UIStroke").Color = utils.getContrastingColor(titleTextLabel.TextColor3)

				local activatedConnection: RBXScriptConnection = vanityInst.Activated:Connect(
					function()
						self.isPreviewing = true

						local canUnlock = true
						clientVanityPreviewManager:beginPreview(
							function()
								self:beginDialog()
							end,
							vanityPlacement, inst.Name, vanityPlacementName, rarity, canUnlock)
					end
				)
				table.insert(self.connections, activatedConnection)
			else
				vanityInst = (VanityLockedTemplate :: any):Clone()
				local titleTextLabel = vanityInst:FindFirstChild("ItemName")
				titleTextLabel.Text = inst:GetAttribute(Attributes.DISPLAY_NAME)
				titleTextLabel.TextColor3 = utils.getColorForRarity(rarity)
				titleTextLabel:FindFirstChild("UIStroke").Color = utils.getContrastingColor(titleTextLabel.TextColor3)

				vanityInst:FindFirstChild("BlueprintNeeded").Text = "Need Blueprint"
				local activatedConnection: RBXScriptConnection = vanityInst.Activated:Connect(
					function()
						self.isPreviewing = true

						local canUnlock = false
						clientVanityPreviewManager:beginPreview(
							function()
								self:beginDialog()
							end,
							vanityPlacement, inst.Name, vanityPlacementName, rarity, canUnlock)
					end
				)
				table.insert(self.connections, activatedConnection)
			end
		elseif vanityComponentState == enums.VanityComponentState.UNLOCKED then
			local isEquipped
			local vanityPlacementInst: any = vanityPlacementsDataFolder:FindFirstChild(vanityPlacementName)
			if vanityPlacementInst then
				local equippedVanityComponentName = vanityPlacementInst:GetAttribute(Attributes.VANITY_COMPONENT_NAME)
				--print("equipped name", equippedVanityComponentName)
				isEquipped = (equippedVanityComponentName == vanityComponentName)
				local destroyingConnection: RBXScriptConnection = vanityPlacementInst.Destroying:Connect(
					function()
						--print("no longer equipped", vanityPlacementInst)
						self:cleanupVanityOptions()
						self:setupVanityOptions()
					end
				)
				table.insert(self.connections, destroyingConnection)
				local attributeChangedConnection: RBXScriptConnection = vanityPlacementInst:GetAttributeChangedSignal(Attributes.VANITY_COMPONENT_NAME):Connect(
					function()
						--print("changed")
						self:cleanupVanityOptions()
						self:setupVanityOptions()
					end
				)
				table.insert(self.connections, attributeChangedConnection)
			else
				isEquipped = false
				local childAddedConnection: RBXScriptConnection = vanityPlacementsDataFolder.ChildAdded:Connect(
					function(child: Instance)
						if child.Name ~= vanityPlacementName then
							return
						end
						--print("equipped something for our placement", vanityPlacementName)
						self:cleanupVanityOptions()
						self:setupVanityOptions()
					end
				)
				table.insert(self.connections, childAddedConnection)
			end
			--print("vanityComponentName", vanityComponentName, "is unlocked. Equipped?", isEquipped)

			if isEquipped then
				vanityInst = (VanityEquippedTemplate :: any):Clone()
				vanityInst.Text = inst:GetAttribute(Attributes.DISPLAY_NAME)
				local activatedConnection: RBXScriptConnection = vanityInst.Activated:Connect(
					function()
						--print("trying to unequip vanity placement", vanityPlacement)
						RemoteEvents.TryUnequipVanityPlacement:FireServer(vanityPlacement)
					end
				)
				table.insert(self.connections, activatedConnection)
			else
				vanityInst = (VanityReadyToEquipTemplate :: any):Clone()
				vanityInst.Text = inst:GetAttribute(Attributes.DISPLAY_NAME)
				local activatedConnection: RBXScriptConnection = vanityInst.Activated:Connect(
					function()
						--print("trying to equip vanity component", vanityComponentName)
						RemoteEvents.TryEquipVanityComponent:FireServer(vanityPlacement, vanityComponentName)

						local gnome: any = utils.findFirstDescendant(workspace, "Gnome")
						local audioEquipVanity = gnome:FindFirstChild("AudioEquipVanity")
						audioEquipVanity:Play()
					end
				)
				table.insert(self.connections, activatedConnection)
			end
		else
			warn("unknown vanity component state", inst, vanityComponentState)
		end
		if vanityInst then
			vanityInst.Visible = true
			vanityInst.Parent = VanityOptionsScroll
			end
	end
end

function ClientVanityFencesManager.cleanupVanityOptions(self: ClientVanityFencesManager)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

function ClientVanityFencesManager.beginDialog(self: ClientVanityFencesManager)
	self:setupVanityOptions()

	self.isPreviewing = false

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityFencesManager.cleanupDialog(self: ClientVanityFencesManager)
	self:cleanupVanityOptions()

	GuiRoot.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if not self.isPreviewing then
		clientVanityUnlockedManager:notifyVanityDialogClosed()
	end
end

function ClientVanityFencesManager.init(self: ClientVanityFencesManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Tabs = Main:FindFirstChild("Tabs")
	for i = 1, 9 do
		local tab = Tabs:FindFirstChild(string.format("FenceSection%02iTabNotSelected", i))
		tab.Activated:Connect(
			function()
				self.selectedTabIndex = i
				self.vanityPlacement = self.getVanityPlacementByIndex(self.selectedTabIndex)

				self:cleanupVanityOptions()
				self:setupVanityOptions()

				for j = 1, 9 do
					local selectedTab = Tabs:FindFirstChild(string.format("FenceSection%02iTabSelected", j))
					local notSelectedTab = Tabs:FindFirstChild(string.format("FenceSection%02iTabNotSelected", j))
					if i == j then
						selectedTab.Visible = true
						notSelectedTab.Visible = false
					else
						selectedTab.Visible = false
						notSelectedTab.Visible = true
					end
				end
			end
		)
	end

	local exitButton: any = utils.findFirstDescendant(GuiRoot, "ExitButton")
	exitButton.Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
end

function ClientVanityFencesManager.new(): ClientVanityFencesManager
	local self = setmetatable({} :: ClientVanityFencesManagerFields, ClientVanityFencesManager)

	self.selectedTabIndex = 1
	self.vanityPlacement = self.getVanityPlacementByIndex(self.selectedTabIndex)
	self.isPreviewing = false

	self.connections = {}

	return self
end


local singleton = ClientVanityFencesManager.new()

return singleton
