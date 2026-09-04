--!strict

local ClientVanityPlotsManager = {}
ClientVanityPlotsManager.__index = ClientVanityPlotsManager

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
local GuiRoot: any = PlayerGui:WaitForChild("VanityMainPlot")

type ClientVanityPlotsManagerFields = {
	isInnerSelected: boolean,
	connections: { RBXScriptConnection },
	isPreviewing: boolean,
}

export type ClientVanityPlotsManager = typeof(setmetatable({} :: ClientVanityPlotsManagerFields, ClientVanityPlotsManager))

function ClientVanityPlotsManager.getGuiRoot(self: ClientVanityPlotsManager): Instance
	return GuiRoot
end

function ClientVanityPlotsManager.notifyForceEnd(self: ClientVanityPlotsManager)
	self:cleanupDialog()
end

function ClientVanityPlotsManager.notifyClickOutside(self: ClientVanityPlotsManager)
	self:notifyForceEnd()
end

function ClientVanityPlotsManager.doZoomCamera(self: ClientVanityPlotsManager): boolean
	return false
end

function ClientVanityPlotsManager.getHudElements(self: ClientVanityPlotsManager): { number }
	return {}
end

function ClientVanityPlotsManager.setupVanityOptions(self: ClientVanityPlotsManager)
	local Main = GuiRoot:WaitForChild("Main")

	local VanityOptions = Main:WaitForChild("VanityOptions")
	local Header = VanityOptions:WaitForChild("Header")
	local Title = Header:FindFirstChild("Title")
	if self.isInnerSelected then
		Title.Text = "Inner Plot"
	else
		Title.Text = "Outer Plot"
	end

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

	local vanityPlacement: number
	local vanityPlotDataFolder
	if self.isInnerSelected then
		vanityPlotDataFolder = vanityDataFolder:WaitForChild(Constants.VANITY_INNER_PLOT_NAME)
		vanityPlacement = enums.VanityPlacements.MAIN_PLOT_INNER

	else
		vanityPlotDataFolder = vanityDataFolder:WaitForChild(Constants.VANITY_OUTER_PLOT_NAME)
		vanityPlacement = enums.VanityPlacements.MAIN_PLOT_OUTER
	end
	local vanityPlacementName = enums.getName(enums.VanityPlacements, vanityPlacement) :: string

	local children = vanityPlotDataFolder:GetChildren()
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

function ClientVanityPlotsManager.cleanupVanityOptions(self: ClientVanityPlotsManager)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.connections = {}
end

function ClientVanityPlotsManager.beginDialog(self: ClientVanityPlotsManager)
	self:setupVanityOptions()

	self.isPreviewing = false

	GuiRoot.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
end

function ClientVanityPlotsManager.cleanupDialog(self: ClientVanityPlotsManager)
	self:cleanupVanityOptions()

	GuiRoot.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	if not self.isPreviewing then
		clientVanityUnlockedManager:notifyVanityDialogClosed()
	end
end

function ClientVanityPlotsManager.init(self: ClientVanityPlotsManager)
	local Main = GuiRoot:FindFirstChild("Main")
	local Tabs = Main:FindFirstChild("Tabs")
	local InnerPlotTabNotSelected = Tabs:FindFirstChild("InnerPlotTabNotSelected")
	local InnerPlotTabSelected = Tabs:FindFirstChild("InnerPlotTabSelected")
	local OuterPlotTabNotSelected = Tabs:FindFirstChild("OuterPlotTabNotSelected")
	local OuterPlotTabSelected = Tabs:FindFirstChild("OuterPlotTabSelected")

	InnerPlotTabNotSelected.Activated:Connect(
		function()
			--print("select inner plot")
			self.isInnerSelected = true
			InnerPlotTabSelected.Visible = true
			InnerPlotTabNotSelected.Visible = false
			OuterPlotTabSelected.Visible = false
			OuterPlotTabNotSelected.Visible = true

			self:cleanupVanityOptions()
			self:setupVanityOptions()
		end
	)
	OuterPlotTabNotSelected.Activated:Connect(
		function()
			--print("select outer plot")
			self.isInnerSelected = false
			InnerPlotTabSelected.Visible = false
			InnerPlotTabNotSelected.Visible = true
			OuterPlotTabSelected.Visible = true
			OuterPlotTabNotSelected.Visible = false

			self:cleanupVanityOptions()
			self:setupVanityOptions()
		end
	)

	local exitButton: any = utils.findFirstDescendant(GuiRoot, "ExitButton")
	exitButton.Activated:Connect(
		function()
			self:cleanupDialog()
		end
	)
end

function ClientVanityPlotsManager.new(): ClientVanityPlotsManager
	local self = setmetatable({} :: ClientVanityPlotsManagerFields, ClientVanityPlotsManager)

	self.isInnerSelected = true
	self.isPreviewing = false

	self.connections = {}

	return self
end


local singleton = ClientVanityPlotsManager.new()

return singleton
