--!strict

local ClientIndexManager = {}
ClientIndexManager.__index = ClientIndexManager

local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local Abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local indexCatalog = require("@game/ReplicatedStorage/Shared/IndexCatalog")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = game:GetService("Players").LocalPlayer :: Player

local playerGui = player:FindFirstChild("PlayerGui") :: Instance
-- the gui's shape only exists in Studio, so these are untyped here
local indexGui: any = playerGui:WaitForChild("Index")
local screenGui: any = playerGui:WaitForChild("ScreenGui")
local hudIndexFrame: any = screenGui:WaitForChild("IndexFrame")
local indexNotificationDot: any = hudIndexFrame:WaitForChild("NotificationDot")

indexGui.DisplayOrder = 130

local SIDEBAR_BUTTON_NAME_TO_CATEGORY = {
	Dragons = indexCatalog.Category.DRAGONS,
	Plants = indexCatalog.Category.PLANTS,
	Crystals = indexCatalog.Category.CRYSTALS,
	Mutations = indexCatalog.Category.MUTATIONS,
	Abilities = indexCatalog.Category.ABILITIES,
	Blueprints = indexCatalog.Category.BLUEPRINTS,
}

local ELEMENT_NAME_TO_PRIMARY_ELEMENT = {
	Nature = enums.PrimaryElements.NATURE,
	Water = enums.PrimaryElements.WATER,
	Fire = enums.PrimaryElements.FIRE,
}

local MILESTONE_CLAIMABLE_COLOR = Color3.fromRGB(186, 141, 94)
local MILESTONE_CLAIMED_COLOR = Color3.fromRGB(159, 219, 103)
local MILESTONE_LOCKED_COLOR = Color3.fromRGB(141, 100, 58)

local CHAIN_REWARD_LOCKED_COLOR = Color3.fromRGB(41, 56, 30)
local CHAIN_REWARD_CLAIMABLE_LIGHTEN_FACTOR = 0.3
local CHAIN_REWARD_CLAIMED_DARKEN_FACTOR = 0.6
local CHAIN_REWARD_CLAIM_TEXT = "CLAIM"
local CHAIN_REWARD_COMPLETE_TEXT = "COMPLETE"

local MUTATION_STROKE_DARKEN_FACTOR = 0.6
local MUTATION_CARD_FAST_CYCLE_SEC = 1
local MUTATION_CARD_SLOW_CYCLE_SEC = 4

local LEVEL_ZERO_LABEL = {
	[indexCatalog.Category.DRAGONS] = "Egg",
	[indexCatalog.Category.PLANTS] = "Seed",
	[indexCatalog.Category.CRYSTALS] = "Shard",
}

local BLUEPRINT_SECTION_DISPLAY_NAMES = {
	[enums.VanitySection.MAIN_INNER] = "Main Inner",
	[enums.VanitySection.MAIN_OUTER] = "Main Outer",
	[enums.VanitySection.MAIN_FENCE] = "Main Fence",
	[enums.VanitySection.EXPANSION_INNER] = "Expansion Inner",
	[enums.VanitySection.EXPANSION_OUTER] = "Expansion Outer",
}

local SECTION_HEADER_GAP = 10

local ROW_CELL_BIND_BUFFER_COUNT = 1

local ITEM_VIEWPORT_ENABLED = true -- master switch: when false, details panel always shows the static icon instead of a viewport
local ITEM_VIEWPORT_ROTATION_SEC = 5
local ITEM_VIEWPORT_DEFAULT_CAMERA_POSITION = Vector3.new(0, 2, 5)
local ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR = Color3.fromRGB(40, 40, 40)

-- categories whose models rotate/frame around their own pivot instead of their bounding-box center, which looks off-center for uneven geometry (e.g. plants) --
local ITEM_VIEWPORT_PIVOT_ROTATION_CATEGORIES = {
	[indexCatalog.Category.PLANTS] = true,
}

local INDEX_GRID_DEFAULT_SIZE_Y_SCALE = 0.615
local INDEX_GRID_DETAILS_OPEN_SIZE_Y_SCALE = 0.45

local function setFilterButtonActive(button, isActive)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = isActive
	end
end

local SELECTION_STROKE_COMMON_COLOR = Color3.new(0, 0, 0)

local function setCellSelectionStrokeEnabled(cell, isEnabled)
	local isCommon = isEnabled and cell:GetAttribute("rarity") == enums.Rarity.COMMON

	local stroke = cell:FindFirstChild("SelectionStroke")
	if stroke then
		if isCommon then
			stroke.Color = SELECTION_STROKE_COMMON_COLOR
		end
		stroke.Enabled = isEnabled
	end

	local fallbackText = cell:FindFirstChild("FallbackText")
	local fallbackStroke: any = fallbackText and fallbackText:FindFirstChild("SelectionStroke")
	if fallbackStroke then
		if isCommon then
			fallbackStroke.Color = SELECTION_STROKE_COMMON_COLOR
		end
		fallbackStroke.Enabled = isEnabled
	end
end

local function getAbilityIconAssetId(ability: any): string?
	local assetId = Abilities.getStoreImageAssetIdForAbility(ability)
	if not assetId then
		return nil
	end
	return "rbxassetid://" .. tostring(assetId)
end

local function darkenColor(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function lightenColor(color: Color3, factor: number): Color3
	return Color3.new(
		color.R + (1 - color.R) * factor,
		color.G + (1 - color.G) * factor,
		color.B + (1 - color.B) * factor
	)
end

local function doesChainPassFilters(
	chainPrimaryElement,
	chainRarity,
	chainSection,
	activeElements,
	activeRarities,
	activeSections
)
	local hasElementFilter = next(activeElements) ~= nil
	local hasRarityFilter = next(activeRarities) ~= nil
	local hasSectionFilter = next(activeSections) ~= nil

	local passesElement = true
	if hasElementFilter then
		passesElement = chainPrimaryElement ~= nil and activeElements[chainPrimaryElement] == true
	end

	local passesRarity = true
	if hasRarityFilter then
		passesRarity = chainRarity ~= nil and activeRarities[chainRarity] == true
	end

	local passesSection = true
	if hasSectionFilter then
		passesSection = chainSection ~= nil and activeSections[chainSection] == true
	end

	return passesElement and passesRarity and passesSection
end

local function isMutationsCategory(category)
	return category == indexCatalog.Category.MUTATIONS
end

local function isAbilitiesCategory(category)
	return category == indexCatalog.Category.ABILITIES
end

local function isBlueprintsCategory(category)
	return category == indexCatalog.Category.BLUEPRINTS
end

type ClientIndexManagerFields = {
	detailsMutationColorConnection: any, -- pseudo-connection from startMutationColorCycle
	mutationCardColorConnections: { any },
	mutationColorCyclers: { any },
	mutationColorCyclersConnection: any,
	activeElements: { [any]: any },
	activeRarities: { [any]: any },
	activeSections: { [any]: any },
	blueprintRowTemplate: any,
	categoryFill: any,
	categoryFracLabel: any,
	chainGrid: any,
	chainGridScrollDirty: any,
	columnHeaderTemplate: any,
	columnHeadersContainer: any,
	cornerLabel: any,
	currentCategory: any,
	detailsIcon: any,
	detailsLockedIcon: any,
	detailsNameLabel: any,
	detailsOwnedLabel: any,
	detailsPanel: any,
	detailsSubtitleLabel: any,
	detailsViewportCamera: any,
	detailsViewportFrame: any,
	detailsViewportModel: any,
	detailsViewportModelCenter: any,
	detailsViewportRotateConnect: any,
	discoveredLabel: any,
	elementColors: { [any]: any },
	elementFiltersContainer: any,
	filterContainers: any,
	headerRow: any,
	indexData: any,
	isEnabled: any,
	milestoneButtonTemplate: any,
	milestoneButtonsContainer: any,
	mutationCardTemplate: any,
	mutationGrid: any,
	rarityColors: { [any]: any },
	rarityFiltersContainer: any,
	renderedColumnHeaders: { [any]: any },
	renderedMilestoneButtons: { [any]: any },
	renderedMutationCards: { [any]: any },
	renderedRowCells: { [any]: any },
	renderedRowChainData: { [any]: any },
	renderedRows: { [any]: any },
	renderedSections: { [any]: any },
	rowTemplate: any,
	sectionFiltersContainer: any,
	sectionHeaderTemplate: any,
	sectionsGrid: any,
	selectedCell: any,
	sidebarButtons: { [any]: any },
}

export type ClientIndexManager = typeof(setmetatable({} :: ClientIndexManagerFields, ClientIndexManager))

function ClientIndexManager.getGuiRoot(self: ClientIndexManager)
	return indexGui
end

function ClientIndexManager.notifyForceEnd(self: ClientIndexManager)
	self:cleanupIndex()
end

function ClientIndexManager.notifyClickOutside(self: ClientIndexManager)
	self:notifyForceEnd()
end

function ClientIndexManager.getHudElements(self: ClientIndexManager)
	return { enums.HudElements.COINS }
end

function ClientIndexManager.setEnabled(self: ClientIndexManager, isEnabled: any)
	self.isEnabled = isEnabled

	if not isEnabled and indexGui.Enabled then
		self:cleanupIndex()
	end
end

function ClientIndexManager.beginIndex(self: ClientIndexManager)
	if not self.isEnabled then
		return
	end

	indexGui.Enabled = true

	overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)

	RemoteEvents.TryRefreshIndexData:FireServer()

	self.mutationColorCyclersConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:updateMutationColorCyclers(deltaTime)
	end)
end

function ClientIndexManager.toggleIndex(self: ClientIndexManager)
	if indexGui.Enabled then
		self:cleanupIndex()
	else
		self:beginIndex()
	end
end

function ClientIndexManager.cleanupIndex(self: ClientIndexManager)
	indexGui.Enabled = false

	overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)

	self:switchCategory(indexCatalog.Category.DRAGONS)

	local mutationColorCyclersConnection = self.mutationColorCyclersConnection
	if mutationColorCyclersConnection then
		mutationColorCyclersConnection:Disconnect()
		self.mutationColorCyclersConnection = nil
	end
end

function ClientIndexManager.hasAnyClaimableReward(self: ClientIndexManager)
	if not self.indexData then
		return false
	end

	for _, categoryData in self.indexData.milestonesByCategory do
		for _, milestone in categoryData.categoryMilestones do
			if milestone.isClaimable then
				return true
			end
		end

		for _, chain in categoryData.chains do
			for _, milestone in chain.milestones do
				if milestone.isClaimable then
					return true
				end
			end
		end
	end

	return false
end

function ClientIndexManager.updateNotificationDot(self: ClientIndexManager)
	indexNotificationDot.Visible = self:hasAnyClaimableReward()
end

function ClientIndexManager.notifyHasClaimableReward(self: ClientIndexManager)
	indexNotificationDot.Visible = true
end

function ClientIndexManager.notifyIndexData(self: ClientIndexManager, indexData: any)
	self.indexData = indexData
	self:applyIndexFilters()
	self:renderBottomBar()
	self:updateNotificationDot()
end

function ClientIndexManager.notifyIndexDataRefreshed(self: ClientIndexManager, refreshedData: any)
	if not self.indexData then
		return
	end

	self.indexData.itemOwnedCounts = refreshedData.ownedCounts
	self.indexData.milestonesByCategory = refreshedData.milestonesByCategory

	self:applyIndexFilters()
	self:renderBottomBar()
	self:updateNotificationDot()
end

function ClientIndexManager.notifyItemDiscovered(self: ClientIndexManager, category: any, chainKey: any, itemName: any)
	if not self.indexData then
		return
	end

	self.indexData.indexDiscoveredItems[itemName] = true
end

function ClientIndexManager.notifyMutationDiscovered(self: ClientIndexManager, mutationTier: any)
	if not self.indexData then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[indexCatalog.Category.MUTATIONS]
	if not categoryData or not categoryData.mutationTiers then
		return
	end

	for _, tierData in categoryData.mutationTiers do
		if tierData.mutationTier == mutationTier then
			tierData.isDiscovered = true
			break
		end
	end
end

function ClientIndexManager.notifyAbilityStatuses(self: ClientIndexManager, abilityStatuses: any)
	if not self.indexData then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[indexCatalog.Category.ABILITIES]
	if not categoryData then
		return
	end

	local normalizedAbilityStatuses = {}
	for abilityStr, abilityStatus in abilityStatuses do
		normalizedAbilityStatuses[tonumber(abilityStr)] = abilityStatus
	end

	for _, chain in categoryData.chains do
		for _, abilityEntry in chain.abilities do
			local abilityStatus = normalizedAbilityStatuses[abilityEntry.ability]
			abilityEntry.isDiscovered = abilityStatus ~= nil and abilityStatus ~= enums.AbilityStatus.LOCKED
		end
	end
end

function ClientIndexManager.resetFilters(self: ClientIndexManager)
	self.activeElements = {}
	self.activeRarities = {}
	self.activeSections = {}

	if not self.filterContainers then
		return
	end

	for _, container in self.filterContainers do
		for _, button in container:GetChildren() do
			if not button:IsA("GuiButton") then
				continue
			end

			setFilterButtonActive(button, false)
		end
	end
end

function ClientIndexManager.applyIndexFilters(self: ClientIndexManager)
	if isMutationsCategory(self.currentCategory) then
		self:renderMutationsGrid()
	elseif isBlueprintsCategory(self.currentCategory) then
		self:renderSectionsGrid()
	else
		self:renderChainGrid()
	end
end

function ClientIndexManager.onElementFilterButtonClicked(self: ClientIndexManager, elementValue: any, button: any)
	if self.activeElements[elementValue] then
		self.activeElements[elementValue] = nil
	else
		self.activeElements[elementValue] = true
	end

	setFilterButtonActive(button, self.activeElements[elementValue] == true)
	self:applyIndexFilters()
end

function ClientIndexManager.onRarityFilterButtonClicked(self: ClientIndexManager, rarityValue: any, button: any)
	if self.activeRarities[rarityValue] then
		self.activeRarities[rarityValue] = nil
	else
		self.activeRarities[rarityValue] = true
	end

	setFilterButtonActive(button, self.activeRarities[rarityValue] == true)
	self:applyIndexFilters()
end

function ClientIndexManager.onSectionFilterButtonClicked(self: ClientIndexManager, sectionValue: any, button: any)
	if self.activeSections[sectionValue] then
		self.activeSections[sectionValue] = nil
	else
		self.activeSections[sectionValue] = true
	end

	setFilterButtonActive(button, self.activeSections[sectionValue] == true)
	self:applyIndexFilters()
end

function ClientIndexManager.initFilterButtons(self: ClientIndexManager, dialogFit: any)
	local filterRow = dialogFit:WaitForChild("FilterRow")
	self.elementFiltersContainer = filterRow:WaitForChild("ElementFilters")
	self.rarityFiltersContainer = filterRow:WaitForChild("RarityFilters")
	self.sectionFiltersContainer = filterRow:WaitForChild("SectionFilters")

	self.filterContainers = { self.elementFiltersContainer, self.rarityFiltersContainer, self.sectionFiltersContainer }

	for _, button in self.elementFiltersContainer:GetChildren() do
		if not button:IsA("GuiButton") then
			continue
		end

		local elementValue = ELEMENT_NAME_TO_PRIMARY_ELEMENT[button.Name]
		if not elementValue then
			warn("element filter button name doesn't match a known element", button.Name)
			continue
		end

		self.elementColors[elementValue] = button.BackgroundColor3

		setFilterButtonActive(button, false)

		button.Activated:Connect(function()
			self:onElementFilterButtonClicked(elementValue, button)
		end)
	end

	for _, button in self.rarityFiltersContainer:GetChildren() do
		if not button:IsA("GuiButton") then
			continue
		end

		local rarityValue = (enums.Rarity :: { [string]: any })[string.upper(button.Name)]
		if not rarityValue then
			warn("rarity filter button name doesn't match a Rarity enum key", button.Name)
			continue
		end

		self.rarityColors[rarityValue] = button.BackgroundColor3

		setFilterButtonActive(button, false)

		button.Activated:Connect(function()
			self:onRarityFilterButtonClicked(rarityValue, button)
		end)
	end

	for _, button in self.sectionFiltersContainer:GetChildren() do
		if not button:IsA("GuiButton") then
			continue
		end

		local sectionValue = (enums.VanitySection :: { [string]: any })[string.upper(button.Name)]
		if not sectionValue then
			warn("section filter button name doesn't match a VanitySection enum key", button.Name)
			continue
		end

		setFilterButtonActive(button, false)

		button.Activated:Connect(function()
			self:onSectionFilterButtonClicked(sectionValue, button)
		end)
	end
end

function ClientIndexManager.initChainGrid(self: ClientIndexManager, dialogFit: any)
	self.chainGrid = dialogFit:WaitForChild("ChainGrid")
	self.chainGrid.ScrollingDirection = Enum.ScrollingDirection.Y
	self.chainGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y

	self.headerRow = self.chainGrid:WaitForChild("HeaderRow")
	self.cornerLabel = self.headerRow:WaitForChild("CornerLabel")
	self.columnHeadersContainer = self.headerRow:WaitForChild("ColumnHeadersContainer")
	self.columnHeaderTemplate = self.columnHeadersContainer:WaitForChild("ColumnHeaderTemplate")
	self.columnHeaderTemplate.Visible = false

	self.rowTemplate = self.chainGrid:WaitForChild("RowTemplate")
	self.rowTemplate.Visible = false

	self.chainGrid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self.chainGridScrollDirty = true
	end)

	RunService.Heartbeat:Connect(function()
		if not self.chainGridScrollDirty then
			return
		end

		self.chainGridScrollDirty = self:updateChainGridCellBinding()
	end)
end

function ClientIndexManager.initMutationsGrid(self: ClientIndexManager, dialogFit: any)
	self.mutationGrid = dialogFit:WaitForChild("MutationGrid")
	self.mutationCardTemplate = self.mutationGrid:WaitForChild("MutationCardTemplate")
	self.mutationCardTemplate.Visible = false
end

function ClientIndexManager.initSectionsGrid(self: ClientIndexManager, dialogFit: any)
	self.sectionsGrid = dialogFit:WaitForChild("SectionsGrid")

	self.sectionHeaderTemplate = self.sectionsGrid:WaitForChild("SectionHeaderTemplate")
	self.sectionHeaderTemplate.Visible = false

	self.blueprintRowTemplate = self.sectionsGrid:WaitForChild("BlueprintRowTemplate")
	self.blueprintRowTemplate.Visible = false
end

function ClientIndexManager.initDetailsPanel(self: ClientIndexManager, dialogFit: any)
	self.detailsPanel = dialogFit:WaitForChild("DetailsPanel")
	self.detailsIcon = self.detailsPanel:WaitForChild("Icon")
	self.detailsIcon.ScaleType = Enum.ScaleType.Fit
	self.detailsLockedIcon = self.detailsPanel:WaitForChild("LockedIcon")

	if ITEM_VIEWPORT_ENABLED then
		self.detailsViewportFrame = Instance.new("ViewportFrame")
		self.detailsViewportFrame.Name = "ItemViewport"
		self.detailsViewportFrame.Size = UDim2.new(
			self.detailsIcon.Size.X.Scale * 2,
			self.detailsIcon.Size.X.Offset * 2,
			self.detailsIcon.Size.Y.Scale,
			self.detailsIcon.Size.Y.Offset
		)
		self.detailsViewportFrame.Position = self.detailsIcon.Position
		self.detailsViewportFrame.AnchorPoint = self.detailsIcon.AnchorPoint
		self.detailsViewportFrame.ZIndex = self.detailsIcon.ZIndex
		self.detailsViewportFrame.BackgroundTransparency = 1
		self.detailsViewportFrame.Active = false
		self.detailsViewportFrame.Selectable = false
		self.detailsViewportFrame.Visible = false
		self.detailsViewportFrame.Parent = self.detailsIcon.Parent

		for _, child in self.detailsIcon:GetChildren() do
			if child:IsA("UICorner") then
				child:Clone().Parent = self.detailsViewportFrame
			end
		end

		local aspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
		aspectRatioConstraint.AspectRatio = 1
		aspectRatioConstraint.DominantAxis = Enum.DominantAxis.Width
		aspectRatioConstraint.Parent = self.detailsViewportFrame

		local border = Instance.new("UIStroke")
		border.Thickness = 2
		border.Color = Color3.fromRGB(255, 255, 255)
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Parent = self.detailsViewportFrame

		self:setupItemViewport()
	end

	local textDetails = self.detailsPanel:WaitForChild("TextDetails")
	self.detailsNameLabel = textDetails:WaitForChild("NameLabel")
	self.detailsSubtitleLabel = textDetails:WaitForChild("SubtitleLabel")
	self.detailsOwnedLabel = textDetails:WaitForChild("OwnedLabel")

	self:clearItemDetails()
end

function ClientIndexManager.setupItemViewport(self: ClientIndexManager)
	local camera = Instance.new("Camera")
	camera.Parent = self.detailsViewportFrame
	self.detailsViewportFrame.CurrentCamera = camera
	self.detailsViewportCamera = camera
end

function ClientIndexManager.showItemViewport(self: ClientIndexManager, templatePath: any, cameraPosition: any, backgroundColor: any)
	self:hideItemViewport()

	if not self.detailsViewportFrame or not templatePath then
		return false
	end

	local template = utils.getPathReference(GameAssets, templatePath)
	if not template then
		return false
	end

	local model: any = template:Clone()
	model.Parent = self.detailsViewportFrame

	local boundingBoxCenter = model:GetBoundingBox().Position
	local pivotPosition = model:GetPivot().Position

	local center = ITEM_VIEWPORT_PIVOT_ROTATION_CATEGORIES[self.currentCategory] and pivotPosition or boundingBoxCenter

	local cameraTarget = Vector3.new(center.X, boundingBoxCenter.Y, center.Z)
	local offset = cameraPosition or ITEM_VIEWPORT_DEFAULT_CAMERA_POSITION
	self.detailsViewportCamera.CFrame = CFrame.new(cameraTarget + offset, cameraTarget)

	self.detailsViewportModel = model
	self.detailsViewportModelCenter = center
	self.detailsViewportFrame.BackgroundColor3 = backgroundColor or ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR
	self.detailsViewportFrame.BackgroundTransparency = 0
	self.detailsViewportFrame.Visible = true

	self.detailsViewportRotateConnect = RunService.Heartbeat:Connect(function(deltaTime)
		if not self.detailsViewportModel then
			return
		end

		local modelCenter = self.detailsViewportModelCenter
		local rotationStep = CFrame.Angles(0, math.rad(360 * deltaTime / ITEM_VIEWPORT_ROTATION_SEC), 0)
		local rotateAboutCenter = CFrame.new(modelCenter) * rotationStep * CFrame.new(-modelCenter)

		self.detailsViewportModel:PivotTo(rotateAboutCenter * self.detailsViewportModel:GetPivot())
	end)

	return true
end

function ClientIndexManager.hideItemViewport(self: ClientIndexManager)
	if self.detailsViewportRotateConnect then
		self.detailsViewportRotateConnect:Disconnect()
		self.detailsViewportRotateConnect = nil
	end

	if self.detailsViewportModel then
		self.detailsViewportModel:Destroy()
		self.detailsViewportModel = nil
		self.detailsViewportModelCenter = nil
	end

	if self.detailsViewportFrame then
		self.detailsViewportFrame.Visible = false
	end
end

function ClientIndexManager.setGridSizeYScale(self: ClientIndexManager, grid: any, yScale: any)
	grid.Size = UDim2.new(grid.Size.X.Scale, grid.Size.X.Offset, yScale, grid.Size.Y.Offset)
end

function ClientIndexManager.setIndexGridsSizeYScale(self: ClientIndexManager, yScale: any)
	self:setGridSizeYScale(self.chainGrid, yScale)
	self:setGridSizeYScale(self.sectionsGrid, yScale)
	self:setGridSizeYScale(self.mutationGrid, yScale)
end

function ClientIndexManager.clearItemDetails(self: ClientIndexManager)
	self:hideItemViewport()
	self:clearDetailsMutationColorCycle()

	self:setIndexGridsSizeYScale(INDEX_GRID_DEFAULT_SIZE_Y_SCALE)

	self.detailsPanel.Visible = false
	self.detailsIcon.Image = ""
	self.detailsIcon.BackgroundTransparency = 0
	self.detailsIcon.Visible = false
	self.detailsLockedIcon.Visible = false
	self.detailsNameLabel.Text = "Tap an item to inspect it."
	self.detailsSubtitleLabel.Text = ""
	self.detailsOwnedLabel.Visible = false
end

function ClientIndexManager.toggleCellSelection(self: ClientIndexManager, cell: any, showDetailsFunc: any)
	if self.selectedCell == cell then
		self:deselectCurrentCell()
		return
	end

	self:deselectCurrentCell()

	setCellSelectionStrokeEnabled(cell, true)

	self.selectedCell = cell
	self.detailsPanel.Visible = true
	self:setIndexGridsSizeYScale(INDEX_GRID_DETAILS_OPEN_SIZE_Y_SCALE)
	showDetailsFunc()
end

function ClientIndexManager.deselectCurrentCell(self: ClientIndexManager)
	if not self.selectedCell then
		return
	end

	setCellSelectionStrokeEnabled(self.selectedCell, false)

	self.selectedCell = nil
	self:clearItemDetails()
end

function ClientIndexManager.initBottomBar(self: ClientIndexManager, dialogFit: any)
	local bottomBar = dialogFit:WaitForChild("BottomBar")

	local categoryProgressRow = bottomBar:WaitForChild("CategoryProgressRow")
	self.categoryFill = categoryProgressRow:WaitForChild("FillBar"):WaitForChild("Fill")
	self.categoryFracLabel = bottomBar:WaitForChild("FracLabel")

	self.discoveredLabel = bottomBar:WaitForChild("DiscoveredLabel")

	self.milestoneButtonsContainer = bottomBar:WaitForChild("MilestoneButtons")
	self.milestoneButtonTemplate = self.milestoneButtonsContainer:WaitForChild("MilestoneButtonTemplate")
	self.milestoneButtonTemplate.Visible = false
end

function ClientIndexManager.clearRenderedMilestoneButtons(self: ClientIndexManager)
	for _, button in self.renderedMilestoneButtons do
		button:Destroy()
	end
	self.renderedMilestoneButtons = {}
end

function ClientIndexManager.onMilestoneButtonClicked(self: ClientIndexManager, milestone: any)
	if not milestone.isClaimable then
		return
	end

	RemoteEvents.TryClaimIndexReward:FireServer(
		self.currentCategory,
		indexHelpers.Scope.CATEGORY,
		nil,
		milestone.tierIndex
	)
end

function ClientIndexManager.onChainRewardClicked(self: ClientIndexManager, chainKey: any, chainMilestone: any)
	if not chainMilestone or not chainMilestone.isClaimable then
		return
	end

	RemoteEvents.TryClaimIndexReward:FireServer(
		self.currentCategory,
		indexHelpers.Scope.CHAIN,
		chainKey,
		chainMilestone.tierIndex
	)
end

function ClientIndexManager.renderBottomBar(self: ClientIndexManager)
	self:clearRenderedMilestoneButtons()

	if not self.indexData or not self.currentCategory then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[self.currentCategory]
	if not categoryData then
		return
	end

	local categoryDisplay = indexCatalog.CategoryDisplay[self.currentCategory]
	self.discoveredLabel.Text = (categoryDisplay and categoryDisplay.name or self.currentCategory) .. " Discovered"

	local discoveredCount = 0
	local totalCount = 0

	if isMutationsCategory(self.currentCategory) then
		for _, tierData in categoryData.mutationTiers do
			totalCount += 1
			if tierData.isDiscovered then
				discoveredCount += 1
			end
		end
	elseif isAbilitiesCategory(self.currentCategory) then
		for _, chain in categoryData.chains do
			totalCount += #chain.abilities
			for _, abilityEntry in chain.abilities do
				if abilityEntry.isDiscovered then
					discoveredCount += 1
				end
			end
		end
	else
		local discoveredItems = self.indexData.indexDiscoveredItems
		for _, chain in categoryData.chains do
			totalCount += #chain.itemNames
			for _, itemName in chain.itemNames do
				if discoveredItems[itemName] then
					discoveredCount += 1
				end
			end
		end
	end

	local fillFrac = totalCount > 0 and (discoveredCount / totalCount) or 0
	self.categoryFill.Size = UDim2.new(fillFrac, 0, self.categoryFill.Size.Y.Scale, self.categoryFill.Size.Y.Offset)
	self.categoryFracLabel.Text = string.format("%d/%d (%d%%)", discoveredCount, totalCount, math.round(fillFrac * 100))

	for _, milestone in categoryData.categoryMilestones do
		local button = self.milestoneButtonTemplate:Clone()

		local percentLabel = button:WaitForChild("PercentLabel")
		local rewardLabel = button:WaitForChild("RewardLabel")
		local claimLabel = button:WaitForChild("ClaimLabel")

		percentLabel.Text = milestone.displayPercent .. "%"
		rewardLabel.Text = milestone.displayText

		percentLabel.Visible = not milestone.isClaimable
		rewardLabel.Visible = not milestone.isClaimable
		claimLabel.Visible = milestone.isClaimable

		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = milestone.isClaimable
		end

		if milestone.isClaimed then
			button.BackgroundColor3 = MILESTONE_CLAIMED_COLOR
		elseif milestone.isClaimable then
			button.BackgroundColor3 = MILESTONE_CLAIMABLE_COLOR
		else
			button.BackgroundColor3 = MILESTONE_LOCKED_COLOR
		end

		button.Activated:Connect(function()
			self:onMilestoneButtonClicked(milestone)
		end)

		button.Visible = true
		button.Parent = self.milestoneButtonsContainer
		table.insert(self.renderedMilestoneButtons, button)
	end
end

function ClientIndexManager.clearRenderedChainGrid(self: ClientIndexManager)
	self:deselectCurrentCell()

	for _, columnHeader in self.renderedColumnHeaders do
		columnHeader:Destroy()
	end
	self.renderedColumnHeaders = {}

	for _, row in self.renderedRows do
		row:Destroy()
	end
	self.renderedRows = {}
	self.renderedRowCells = {}
	self.renderedRowChainData = {}
end

function ClientIndexManager.clearRenderedMutationCards(self: ClientIndexManager)
	self:deselectCurrentCell()

	for _, connection in self.mutationCardColorConnections do
		connection:Disconnect()
	end
	self.mutationCardColorConnections = {}

	for _, card in self.renderedMutationCards do
		card:Destroy()
	end
	self.renderedMutationCards = {}
end

function ClientIndexManager.clearRenderedSections(self: ClientIndexManager)
	self:deselectCurrentCell()

	for _, instance in self.renderedSections do
		instance:Destroy()
	end
	self.renderedSections = {}
end

function ClientIndexManager.clearDetailsMutationColorCycle(self: ClientIndexManager)
	local detailsMutationColorConnection = self.detailsMutationColorConnection
	if detailsMutationColorConnection then
		detailsMutationColorConnection:Disconnect()
		self.detailsMutationColorConnection = nil
	end
end

function ClientIndexManager.showMutationDetails(self: ClientIndexManager, card: any)
	self:hideItemViewport()

	local isDiscovered = card:GetAttribute("isDiscovered")
	local publicName = card:GetAttribute("publicName")
	local mutationTier = card:GetAttribute("mutationTier")

	if not isDiscovered then
		self.detailsIcon.Visible = false
		self.detailsLockedIcon.BackgroundColor3 = ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR
		self.detailsLockedIcon.Text = "?"
		self.detailsLockedIcon.Visible = true
	else
		self.detailsIcon.Image = ""
		self.detailsIcon.ImageTransparency = 1
		self.detailsIcon.BackgroundTransparency = 0
		self.detailsIcon.Visible = true
		self.detailsLockedIcon.Visible = false
		self.detailsMutationColorConnection = self:startMutationColorCycle(mutationTier, function(color)
			self.detailsIcon.BackgroundColor3 = color
		end)
	end

	self.detailsNameLabel.Text = isDiscovered and publicName or "??? (Locked)"
	self.detailsSubtitleLabel.Text = ""
	self.detailsOwnedLabel.Visible = false
end

function ClientIndexManager.showItemDetails(self: ClientIndexManager, cell: any)
	local itemName = cell:GetAttribute("itemName")
	local displayName = cell:GetAttribute("displayName") or itemName
	local isDiscovered = cell:GetAttribute("isDiscovered")
	local level = cell:GetAttribute("level")
	local primaryElement = cell:GetAttribute("primaryElement")
	local rarity = cell:GetAttribute("rarity")

	local templatePath = cell:GetAttribute("templatePath")
	local cameraPosition = cell:GetAttribute("cameraPosition")
	local shownViewport = isDiscovered
		and self:showItemViewport(templatePath, cameraPosition, self.rarityColors[rarity])

	if shownViewport then
		self.detailsIcon.Visible = false
		self.detailsLockedIcon.Visible = false
	else
		self:hideItemViewport()

		if not isDiscovered then
			self.detailsIcon.Visible = false
			self.detailsLockedIcon.BackgroundColor3 = self.rarityColors[rarity]
				or ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR
			self.detailsLockedIcon.Text = "?"
			self.detailsLockedIcon.Visible = true
		else
			local iconAssetId = ItemIcons.getItemIconAssetId(itemName)
			self.detailsIcon.Image = iconAssetId or ""
			self.detailsIcon.BackgroundTransparency = iconAssetId and 1 or 0
			self.detailsIcon.Visible = iconAssetId ~= nil
			self.detailsLockedIcon.Visible = false
		end
	end

	self.detailsNameLabel.Text = isDiscovered and displayName or "??? (Locked)"

	local subtitleParts: { any } = {}
	if primaryElement then
		table.insert(subtitleParts, enums.getPublicName(enums.PrimaryElements, primaryElement))
	end
	if rarity then
		table.insert(subtitleParts, enums.getPublicName(enums.Rarity, rarity))
	end
	if level then
		table.insert(subtitleParts, "Level " .. tostring(level))
	end
	self.detailsSubtitleLabel.Text = table.concat(subtitleParts, " \u{00B7} ")

	if isDiscovered then
		local ownedCount = self.indexData.itemOwnedCounts[itemName] or 0
		self.detailsOwnedLabel.Text = "Owned: " .. tostring(ownedCount)
		self.detailsOwnedLabel.Visible = true
	else
		self.detailsOwnedLabel.Visible = false
	end
end

function ClientIndexManager.showAbilityDetails(self: ClientIndexManager, cell: any)
	self:hideItemViewport()

	local isDiscovered = cell:GetAttribute("isDiscovered")
	local ability = cell:GetAttribute("ability")
	local displayName = cell:GetAttribute("displayName")
	local primaryElement = cell:GetAttribute("primaryElement")

	if not isDiscovered then
		self.detailsIcon.Visible = false
		self.detailsLockedIcon.BackgroundColor3 = self.elementColors[primaryElement]
			or ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR
		self.detailsLockedIcon.Text = "?"
		self.detailsLockedIcon.Visible = true
	else
		local iconAssetId = getAbilityIconAssetId(ability)
		self.detailsIcon.Image = iconAssetId or ""
		self.detailsIcon.BackgroundTransparency = iconAssetId and 1 or 0
		self.detailsIcon.Visible = iconAssetId ~= nil
		self.detailsLockedIcon.Visible = false
	end

	self.detailsNameLabel.Text = isDiscovered and displayName or "??? (Locked)"
	self.detailsSubtitleLabel.Text = ""
	self.detailsOwnedLabel.Visible = false
end

function ClientIndexManager.renderChainGrid(self: ClientIndexManager)
	self:clearRenderedChainGrid()

	self.chainGrid.CanvasPosition = Vector2.new(0, 0)

	if not self.indexData or not self.currentCategory then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[self.currentCategory]
	if not categoryData then
		return
	end

	local isAbilities = isAbilitiesCategory(self.currentCategory)
	local discoveredItems = self.indexData.indexDiscoveredItems
	local columnCount = 0

	for _, chain in categoryData.chains do
		local chainColumnCount = isAbilities and #chain.abilities or #chain.itemNames
		columnCount = math.max(columnCount, chainColumnCount)
	end

	local availableWidth = self.columnHeadersContainer.AbsoluteSize.X
	local columnHeadersListLayout = self.columnHeadersContainer:FindFirstChildOfClass("UIListLayout")
	local columnPadding = columnHeadersListLayout and columnHeadersListLayout.Padding.Offset or 0
	local cellSize = columnCount > 0 and math.max(0, (availableWidth - columnPadding * (columnCount - 1)) / columnCount)
		or 0

	self.cornerLabel.Text = "Rewards"

	for i = 1, columnCount do
		local columnHeader = self.columnHeaderTemplate:Clone()
		columnHeader.Text = isAbilities and ""
			or ((i == 1) and (LEVEL_ZERO_LABEL[self.currentCategory] or "0") or tostring(i - 1))
		columnHeader.LayoutOrder = i
		columnHeader.Visible = true
		columnHeader.Size = UDim2.new(0, cellSize, columnHeader.Size.Y.Scale, columnHeader.Size.Y.Offset)
		columnHeader.Parent = self.columnHeadersContainer
		table.insert(self.renderedColumnHeaders, columnHeader)
	end

	local columnHeadersLayout = self.columnHeadersContainer:FindFirstChildWhichIsA("UIGridStyleLayout")
	local columnsAbsoluteWidth = columnHeadersLayout and columnHeadersLayout.AbsoluteContentSize.X or 0

	local rowLayoutOrder = 0
	for _, chain in categoryData.chains do
		if
			not doesChainPassFilters(
				chain.primaryElement,
				chain.rarity,
				chain.section,
				self.activeElements,
				self.activeRarities,
				self.activeSections
			)
		then
			continue
		end

		rowLayoutOrder += 1

		local row = self.rowTemplate:Clone()
		row.LayoutOrder = rowLayoutOrder

		local discoveredCount = 0
		local totalCount = 0
		if isAbilities then
			totalCount = #chain.abilities
			for _, abilityEntry in chain.abilities do
				if abilityEntry.isDiscovered then
					discoveredCount += 1
				end
			end
		else
			totalCount = #chain.itemNames
			for _, itemName in chain.itemNames do
				if discoveredItems[itemName] then
					discoveredCount += 1
				end
			end
		end

		local fillFrac = totalCount > 0 and (discoveredCount / totalCount) or 0

		local chainProgressRow = row:WaitForChild("ChainProgressRow")
		row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 0, cellSize + chainProgressRow.Size.Y.Offset)

		local fillBar = chainProgressRow:WaitForChild("FillBar")
		local fill = fillBar:WaitForChild("Fill")
		fill.Size = UDim2.new(fillFrac, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)

		local fracLabel = chainProgressRow:WaitForChild("FracLabel")
		fracLabel.Text = string.format("%d/%d (%d%%)", discoveredCount, totalCount, math.round(fillFrac * 100))

		local rewardRow = row:WaitForChild("RewardRow")
		rewardRow.Size = UDim2.new(rewardRow.Size.X.Scale, rewardRow.Size.X.Offset, 0, cellSize)

		local cellStrip = rewardRow:WaitForChild("CellStrip")
		cellStrip.Size = UDim2.new(cellStrip.Size.X.Scale, cellStrip.Size.X.Offset, 0, cellSize)

		if columnsAbsoluteWidth > 0 then
			fillBar.Size = UDim2.new(0, columnsAbsoluteWidth, fillBar.Size.Y.Scale, fillBar.Size.Y.Offset)
		end

		local chainReward = rewardRow:WaitForChild("ChainReward")
		chainReward.Size = UDim2.new(chainReward.Size.X.Scale, chainReward.Size.X.Offset, 0, cellSize)

		local colorDot = chainReward:WaitForChild("ColorDot")
		local rewardText = chainReward:WaitForChild("RewardText")

		colorDot.BackgroundColor3 = self.elementColors[chain.primaryElement] or colorDot.BackgroundColor3

		local chainMilestone = chain.milestones and chain.milestones[1]

		if chainMilestone and chainMilestone.isClaimable then
			rewardText.Text = CHAIN_REWARD_CLAIM_TEXT
		elseif chainMilestone and chainMilestone.isClaimed then
			rewardText.Text = CHAIN_REWARD_COMPLETE_TEXT
		else
			rewardText.Text = chainMilestone and chainMilestone.displayText or ""
		end

		local chainRewardStroke = chainReward:FindFirstChildOfClass("UIStroke")
		if chainRewardStroke then
			chainRewardStroke.Enabled = chainMilestone ~= nil and chainMilestone.isClaimable
		end

		local isChainRewardInteractable = not (chainMilestone and chainMilestone.isClaimed)
		chainReward.Active = isChainRewardInteractable
		chainReward.AutoButtonColor = isChainRewardInteractable

		if chainMilestone then
			if chainMilestone.isClaimed then
				chainReward.BackgroundColor3 =
					darkenColor(CHAIN_REWARD_LOCKED_COLOR, CHAIN_REWARD_CLAIMED_DARKEN_FACTOR)
			elseif chainMilestone.isClaimable then
				chainReward.BackgroundColor3 =
					lightenColor(CHAIN_REWARD_LOCKED_COLOR, CHAIN_REWARD_CLAIMABLE_LIGHTEN_FACTOR)
			else
				chainReward.BackgroundColor3 = CHAIN_REWARD_LOCKED_COLOR
			end
		end

		chainReward.Activated:Connect(function()
			self:onChainRewardClicked(chain.chainKey, chainMilestone)
		end)

		local cellTemplate = cellStrip:WaitForChild("CellTemplate")
		cellTemplate.Visible = false

		self.renderedRowChainData[rowLayoutOrder] = {
			chain = chain,
			cellStrip = cellStrip,
			cellTemplate = cellTemplate,
			cellSize = cellSize,
			columnCount = columnCount,
			isAbilities = isAbilities,
			discoveredItems = discoveredItems,
		}

		row.Visible = true
		row.Parent = self.chainGrid
		table.insert(self.renderedRows, row)
	end

	while self:updateChainGridCellBinding() do
	end

	self.chainGridScrollDirty = true
end

function ClientIndexManager.bindRowCells(self: ClientIndexManager, rowIndex: any)
	if self.renderedRowCells[rowIndex] then
		return
	end

	local rowData = self.renderedRowChainData[rowIndex]
	if not rowData then
		return
	end

	local chain = rowData.chain
	local cellStrip = rowData.cellStrip
	local cellTemplate = rowData.cellTemplate
	local cellSize = rowData.cellSize
	local columnCount = rowData.columnCount
	local isAbilities = rowData.isAbilities
	local discoveredItems = rowData.discoveredItems

	local rowCells = {}

	for i = 1, columnCount do
		local cellColor = isAbilities and self.elementColors[chain.primaryElement] or self.rarityColors[chain.rarity]

		local cell: any = cellTemplate:Clone()
		cell.Visible = true
		cell.ScaleType = Enum.ScaleType.Fit
		cell.Size = UDim2.new(0, cellSize, 0, cellSize)
		cell.BackgroundColor3 = cellColor or cell.BackgroundColor3

		local fallbackText = cell:WaitForChild("FallbackText")
		fallbackText.BackgroundColor3 = cellColor or fallbackText.BackgroundColor3

		if isAbilities then
			local abilityEntry = chain.abilities[i]

			if abilityEntry then
				cell:SetAttribute("ability", abilityEntry.ability)
				cell:SetAttribute("isDiscovered", abilityEntry.isDiscovered)
				cell:SetAttribute("displayName", abilityEntry.displayName)
				cell:SetAttribute("primaryElement", chain.primaryElement)

				local iconAssetId = abilityEntry.isDiscovered and getAbilityIconAssetId(abilityEntry.ability) or nil
				if iconAssetId then
					cell.Image = iconAssetId
					cell.BackgroundTransparency = 0
					fallbackText.Visible = false
				else
					cell.Image = ""
					cell.BackgroundTransparency = 0
					fallbackText.Visible = true
					fallbackText.Text = abilityEntry.isDiscovered and "\u{2713}" or "?"
				end

				cell.Activated:Connect(function()
					self:toggleCellSelection(cell, function()
						self:showAbilityDetails(cell)
					end)
				end)
			else
				cell.Image = ""
				fallbackText.Visible = false
			end
		else
			local itemName = chain.itemNames[i]

			if itemName then
				local isDiscovered = discoveredItems[itemName] == true

				cell:SetAttribute("itemName", itemName)
				cell:SetAttribute(
					"displayName",
					(chain.itemDisplayNames and chain.itemDisplayNames[itemName]) or itemName
				)
				cell:SetAttribute("isDiscovered", isDiscovered)
				cell:SetAttribute("level", i - 1)
				cell:SetAttribute("primaryElement", chain.primaryElement)
				cell:SetAttribute("rarity", chain.rarity)
				cell:SetAttribute("templatePath", chain.itemTemplatePaths and chain.itemTemplatePaths[itemName])

				local cameraPositionData = chain.itemCameraPositions and chain.itemCameraPositions[itemName]
				if cameraPositionData then
					cell:SetAttribute(
						"cameraPosition",
						Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
					)
				end

				local iconAssetId = isDiscovered and ItemIcons.getItemIconAssetId(itemName) or nil
				if iconAssetId then
					cell.Image = iconAssetId
					cell.BackgroundTransparency = 0
					fallbackText.Visible = false
				else
					cell.Image = ""
					cell.BackgroundTransparency = 0
					fallbackText.Visible = true
					fallbackText.Text = isDiscovered and tostring(i - 1) or "?"
				end

				cell.Activated:Connect(function()
					self:toggleCellSelection(cell, function()
						self:showItemDetails(cell)
					end)
				end)
			else
				cell.Image = ""
				fallbackText.Visible = false
			end
		end

		table.insert(rowCells, cell)
		cell.Parent = cellStrip
	end

	self.renderedRowCells[rowIndex] = rowCells
end

function ClientIndexManager.updateChainGridCellBinding(self: ClientIndexManager)
	local viewMinY = self.chainGrid.AbsolutePosition.Y
	local viewMaxY = viewMinY + self.chainGrid.AbsoluteSize.Y

	for rowIndex, row in self.renderedRows do
		if self.renderedRowCells[rowIndex] or not self.renderedRowChainData[rowIndex] then
			continue
		end

		local rowHeight = row.AbsoluteSize.Y
		local bufferedMinY = viewMinY - rowHeight * ROW_CELL_BIND_BUFFER_COUNT
		local bufferedMaxY = viewMaxY + rowHeight * ROW_CELL_BIND_BUFFER_COUNT

		local rowMinY = row.AbsolutePosition.Y
		local rowMaxY = rowMinY + rowHeight

		if rowMaxY >= bufferedMinY and rowMinY <= bufferedMaxY then
			self:bindRowCells(rowIndex)
			return true
		end
	end

	return false
end

function ClientIndexManager.renderSectionsGrid(self: ClientIndexManager)
	self:clearRenderedSections()

	self.sectionsGrid.CanvasPosition = Vector2.new(0, 0)

	if not self.indexData or not self.currentCategory then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[self.currentCategory]
	if not categoryData then
		return
	end

	local discoveredItems = self.indexData.indexDiscoveredItems
	local layoutOrder = 0
	local lastRenderedSection = nil

	local maxColumnCount = 0
	for _, chain in categoryData.chains do
		maxColumnCount = math.max(maxColumnCount, #chain.itemNames)
	end

	local templateCellStrip = self.blueprintRowTemplate:WaitForChild("RewardRow"):WaitForChild("CellStrip")
	local availableWidth = templateCellStrip.AbsoluteSize.X
	local templateCellStripListLayout = templateCellStrip:FindFirstChildOfClass("UIListLayout")
	local padding = templateCellStripListLayout and templateCellStripListLayout.Padding.Offset or 0
	local cellSize = maxColumnCount > 0
			and math.max(0, (availableWidth - padding * (maxColumnCount - 1)) / maxColumnCount)
		or 0

	for _, chain in categoryData.chains do
		if
			not doesChainPassFilters(
				chain.primaryElement,
				chain.rarity,
				chain.section,
				self.activeElements,
				self.activeRarities,
				self.activeSections
			)
		then
			continue
		end

		if chain.section ~= lastRenderedSection then
			if lastRenderedSection ~= nil then
				layoutOrder += 1

				local spacer = Instance.new("Frame")
				spacer.Name = "SectionGap"
				spacer.LayoutOrder = layoutOrder
				spacer.BackgroundTransparency = 1
				spacer.Size = UDim2.new(1, 0, 0, SECTION_HEADER_GAP)
				spacer.Parent = self.sectionsGrid
				table.insert(self.renderedSections, spacer)
			end

			layoutOrder += 1

			local header = self.sectionHeaderTemplate:Clone()
			header.LayoutOrder = layoutOrder
			header:WaitForChild("SectionTitle").Text = BLUEPRINT_SECTION_DISPLAY_NAMES[chain.section] or chain.section
			header.Visible = true
			header.Parent = self.sectionsGrid
			table.insert(self.renderedSections, header)

			lastRenderedSection = chain.section
		end

		layoutOrder += 1

		local row = self.blueprintRowTemplate:Clone()
		row.LayoutOrder = layoutOrder

		local discoveredCount = 0
		local totalCount = #chain.itemNames
		for _, itemName in chain.itemNames do
			if discoveredItems[itemName] then
				discoveredCount += 1
			end
		end

		local fillFrac = totalCount > 0 and (discoveredCount / totalCount) or 0

		local chainProgressRow = row:WaitForChild("ChainProgressRow")
		local fillBar = chainProgressRow:WaitForChild("FillBar")
		local fill = fillBar:WaitForChild("Fill")
		fill.Size = UDim2.new(fillFrac, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)

		local fracLabel = chainProgressRow:WaitForChild("FracLabel")
		fracLabel.Text = string.format("%d/%d (%d%%)", discoveredCount, totalCount, math.round(fillFrac * 100))

		local rewardRow = row:WaitForChild("RewardRow")

		local cellStrip = rewardRow:WaitForChild("CellStrip")
		local cellStripLayout = cellStrip:FindFirstChildWhichIsA("UIGridStyleLayout")

		local chainReward = rewardRow:WaitForChild("ChainReward")
		local colorDot = chainReward:WaitForChild("ColorDot")
		local rewardText = chainReward:WaitForChild("RewardText")

		colorDot.BackgroundColor3 = self.rarityColors[chain.rarity] or colorDot.BackgroundColor3

		local chainMilestone = chain.milestones and chain.milestones[1]

		if chainMilestone and chainMilestone.isClaimable then
			rewardText.Text = CHAIN_REWARD_CLAIM_TEXT
		elseif chainMilestone and chainMilestone.isClaimed then
			rewardText.Text = CHAIN_REWARD_COMPLETE_TEXT
		else
			rewardText.Text = chainMilestone and chainMilestone.displayText or ""
		end

		local chainRewardStroke = chainReward:FindFirstChildOfClass("UIStroke")
		if chainRewardStroke then
			chainRewardStroke.Enabled = chainMilestone ~= nil and chainMilestone.isClaimable
		end

		local isChainRewardInteractable = not (chainMilestone and chainMilestone.isClaimed)
		chainReward.Active = isChainRewardInteractable
		chainReward.AutoButtonColor = isChainRewardInteractable

		if chainMilestone then
			if chainMilestone.isClaimed then
				chainReward.BackgroundColor3 =
					darkenColor(CHAIN_REWARD_LOCKED_COLOR, CHAIN_REWARD_CLAIMED_DARKEN_FACTOR)
			elseif chainMilestone.isClaimable then
				chainReward.BackgroundColor3 =
					lightenColor(CHAIN_REWARD_LOCKED_COLOR, CHAIN_REWARD_CLAIMABLE_LIGHTEN_FACTOR)
			else
				chainReward.BackgroundColor3 = CHAIN_REWARD_LOCKED_COLOR
			end
		end

		chainReward.Activated:Connect(function()
			self:onChainRewardClicked(chain.chainKey, chainMilestone)
		end)

		row.Visible = true
		row.Parent = self.sectionsGrid

		row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 0, cellSize + chainProgressRow.Size.Y.Offset)
		chainReward.Size = UDim2.new(chainReward.Size.X.Scale, chainReward.Size.X.Offset, 0, cellSize)
		cellStrip.Size = UDim2.new(cellStrip.Size.X.Scale, cellStrip.Size.X.Offset, 0, cellSize)
		rewardRow.Size = UDim2.new(rewardRow.Size.X.Scale, rewardRow.Size.X.Offset, 0, cellSize)

		local cellTemplate = cellStrip:WaitForChild("CellTemplate")
		cellTemplate.Visible = false

		for _, itemName in chain.itemNames do
			local isDiscovered = discoveredItems[itemName] == true

			local chip: any = cellTemplate:Clone()
			chip.Visible = true
			chip.ScaleType = Enum.ScaleType.Fit
			chip.Size = UDim2.new(0, cellSize, 0, cellSize)
			chip.BackgroundColor3 = self.rarityColors[chain.rarity] or chip.BackgroundColor3

			local fallbackText = chip:WaitForChild("FallbackText")
			fallbackText.BackgroundColor3 = self.rarityColors[chain.rarity] or fallbackText.BackgroundColor3

			chip:SetAttribute("itemName", itemName)
			chip:SetAttribute("displayName", (chain.itemDisplayNames and chain.itemDisplayNames[itemName]) or itemName)
			chip:SetAttribute("isDiscovered", isDiscovered)
			chip:SetAttribute("rarity", chain.rarity)
			chip:SetAttribute("templatePath", chain.itemTemplatePaths and chain.itemTemplatePaths[itemName])

			local cameraPositionData = chain.itemCameraPositions and chain.itemCameraPositions[itemName]
			if cameraPositionData then
				chip:SetAttribute(
					"cameraPosition",
					Vector3.new(cameraPositionData[1], cameraPositionData[2], cameraPositionData[3])
				)
			end

			local iconAssetId = isDiscovered and ItemIcons.getItemIconAssetId(itemName) or nil
			if iconAssetId then
				chip.Image = iconAssetId
				chip.BackgroundTransparency = 0
				fallbackText.Visible = false
			else
				chip.Image = ""
				chip.BackgroundTransparency = 0
				fallbackText.Visible = true
				fallbackText.Text = isDiscovered and "\u{2713}" or "?"
			end

			chip.Activated:Connect(function()
				self:toggleCellSelection(chip, function()
					self:showItemDetails(chip)
				end)
			end)

			chip.Parent = cellStrip
		end

		if cellStripLayout then
			fillBar.Size =
				UDim2.new(0, cellStripLayout.AbsoluteContentSize.X, fillBar.Size.Y.Scale, fillBar.Size.Y.Offset)
		end

		table.insert(self.renderedSections, row)
	end
end

function ClientIndexManager.updateMutationColorCyclers(self: ClientIndexManager, deltaTime: number)
	for _, cycler in self.mutationColorCyclers do
		cycler.colorTime += deltaTime
		if cycler.colorTime > cycler.perColorSec then
			cycler.colorTime -= cycler.perColorSec
			cycler.colorIndex = (cycler.colorIndex % #cycler.colors) + 1
		end

		local nextColor = cycler.colors[(cycler.colorIndex % #cycler.colors) + 1]
		cycler.applyColor(cycler.colors[cycler.colorIndex]:Lerp(nextColor, cycler.colorTime / cycler.perColorSec))
	end
end

-- returns a Disconnect-able pseudo-connection when a cycle was started, nil for static colors
function ClientIndexManager.startMutationColorCycle(self: ClientIndexManager, mutationTier: any, applyColor: (Color3) -> ()): any
	local colors = utils.getColorsForMutation(mutationTier)

	if #colors == 1 then
		applyColor(colors[1])
		return nil
	end

	local perColorSec = utils.isMutationFastCycle(mutationTier) and MUTATION_CARD_FAST_CYCLE_SEC
		or MUTATION_CARD_SLOW_CYCLE_SEC

	local cycler: any = {
		colors = colors,
		perColorSec = perColorSec,
		colorIndex = 1,
		colorTime = 0,
		applyColor = applyColor,
	}

	applyColor(colors[1])

	table.insert(self.mutationColorCyclers, cycler)

	return {
		Disconnect = function()
			local index = table.find(self.mutationColorCyclers, cycler)
			if index then
				table.remove(self.mutationColorCyclers, index)
			end
		end,
	}
end

function ClientIndexManager.renderMutationsGrid(self: ClientIndexManager)
	self:clearRenderedMutationCards()

	if not self.indexData then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[indexCatalog.Category.MUTATIONS]
	if not categoryData or not categoryData.mutationTiers then
		return
	end

	for _, tierData in categoryData.mutationTiers do
		local card = self.mutationCardTemplate:Clone()

		card:SetAttribute("mutationTier", tierData.mutationTier)
		card:SetAttribute("publicName", tierData.publicName)
		card:SetAttribute("isDiscovered", tierData.isDiscovered)

		local cardIcon = card:WaitForChild("CardIcon")
		local fallbackText = card:WaitForChild("FallbackText")
		local nameLabel = card:WaitForChild("NameLabel")

		cardIcon.Visible = false

		if tierData.isDiscovered then
			fallbackText.Visible = false
			nameLabel.Text = tierData.publicName
		else
			fallbackText.Visible = true
			fallbackText.Text = "?"
			nameLabel.Text = "???"
		end

		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = true
		end

		local function applyMutationCardColor(color)
			card.BackgroundColor3 = color
			if stroke then
				stroke.Color = darkenColor(color, MUTATION_STROKE_DARKEN_FACTOR)
			end
		end

		if tierData.isDiscovered then
			local connection = self:startMutationColorCycle(tierData.mutationTier, applyMutationCardColor)
			if connection then
				table.insert(self.mutationCardColorConnections, connection)
			end
		else
			applyMutationCardColor(ITEM_VIEWPORT_DEFAULT_BACKGROUND_COLOR)
		end

		card.Activated:Connect(function()
			self:toggleCellSelection(card, function()
				self:showMutationDetails(card)
			end)
		end)

		card.Visible = true
		card.Parent = self.mutationGrid
		table.insert(self.renderedMutationCards, card)
	end
end

function ClientIndexManager.updateFilterRowVisibility(self: ClientIndexManager)
	local categoryAxes = indexCatalog.CategoryAxes[self.currentCategory]

	self.elementFiltersContainer.Visible = categoryAxes ~= nil and categoryAxes.element == true
	self.rarityFiltersContainer.Visible = categoryAxes ~= nil and categoryAxes.rarity == true
	self.sectionFiltersContainer.Visible = categoryAxes ~= nil and categoryAxes.section == true
end

function ClientIndexManager.updateSidebarActiveState(self: ClientIndexManager)
	for category, button in self.sidebarButtons do
		setFilterButtonActive(button, category == self.currentCategory)
	end
end

function ClientIndexManager.updateGridVisibility(self: ClientIndexManager)
	local isMutations = isMutationsCategory(self.currentCategory)
	local isBlueprints = isBlueprintsCategory(self.currentCategory)

	self.chainGrid.Visible = not isMutations and not isBlueprints
	self.mutationGrid.Visible = isMutations
	self.sectionsGrid.Visible = isBlueprints
end

function ClientIndexManager.switchCategory(self: ClientIndexManager, category: any)
	if isMutationsCategory(self.currentCategory) and not isMutationsCategory(category) then
		self:clearRenderedMutationCards()
	end

	self.currentCategory = category

	self:resetFilters()
	self:updateFilterRowVisibility()
	self:updateGridVisibility()
	self:applyIndexFilters()
	self:renderBottomBar()
	self:updateSidebarActiveState()
	self:clearItemDetails()
end

function ClientIndexManager.initSidebar(self: ClientIndexManager, dialogFit: any)
	local sidebar = dialogFit:WaitForChild("Sidebar")

	for _, button in sidebar:GetChildren() do
		if not button:IsA("GuiButton") then
			continue
		end

		local category = SIDEBAR_BUTTON_NAME_TO_CATEGORY[button.Name]
		if not category then
			warn("sidebar button name doesn't match a known Index category", button.Name)
			continue
		end

		self.sidebarButtons[category] = button

		button.Activated:Connect(function()
			self:switchCategory(category)
		end)
	end
end

function ClientIndexManager.notifyClaimStatus(self: ClientIndexManager, isSuccess: any, category: any, scope: any, chainKey: any, tierId: any, milestoneViewModels: any)
	if not isSuccess or not milestoneViewModels or not self.indexData then
		return
	end

	local categoryData = self.indexData.milestonesByCategory[category]
	if not categoryData then
		return
	end

	if scope == indexHelpers.Scope.CATEGORY then
		categoryData.categoryMilestones = milestoneViewModels
	else
		for _, chain in categoryData.chains do
			if chain.chainKey == chainKey then
				chain.milestones = milestoneViewModels
				break
			end
		end
	end

	if category == self.currentCategory then
		self:applyIndexFilters()
		self:renderBottomBar()
	end

	self:updateNotificationDot()
end

function ClientIndexManager.init(self: ClientIndexManager)
	local dialogFit = indexGui:WaitForChild("DialogFit")
	local header = dialogFit:WaitForChild("Header")
	local exitButton = header:WaitForChild("ExitButton")

	exitButton.Activated:Connect(function()
		self:cleanupIndex()
	end)

	self:initSidebar(dialogFit)
	self:initFilterButtons(dialogFit)
	self:initChainGrid(dialogFit)
	self:initMutationsGrid(dialogFit)
	self:initSectionsGrid(dialogFit)
	self:initDetailsPanel(dialogFit)
	self:initBottomBar(dialogFit)
	self:switchCategory(indexCatalog.Category.DRAGONS)
end

function ClientIndexManager.new(): ClientIndexManager
	local self = setmetatable({} :: ClientIndexManagerFields, ClientIndexManager)

	self.indexData = nil

	self.isEnabled = true

	self.selectedCell = nil

	self.currentCategory = nil
	self.sidebarButtons = {}
	self.activeElements = {}
	self.activeRarities = {}
	self.activeSections = {}
	self.filterContainers = nil
	self.elementFiltersContainer = nil
	self.rarityFiltersContainer = nil
	self.sectionFiltersContainer = nil
	self.elementColors = {}
	self.rarityColors = {}

	self.chainGrid = nil
	self.cornerLabel = nil
	self.columnHeadersContainer = nil
	self.columnHeaderTemplate = nil
	self.rowTemplate = nil
	self.renderedColumnHeaders = {}
	self.renderedRows = {}
	self.renderedRowCells = {}
	self.renderedRowChainData = {}
	self.chainGridScrollDirty = false

	self.mutationGrid = nil
	self.mutationCardTemplate = nil
	self.renderedMutationCards = {}
	self.mutationCardColorConnections = {}
	self.mutationColorCyclers = {}
	self.mutationColorCyclersConnection = nil

	self.sectionsGrid = nil
	self.sectionHeaderTemplate = nil
	self.blueprintRowTemplate = nil
	self.renderedSections = {}

	self.detailsIcon = nil
	self.detailsLockedIcon = nil
	self.detailsMutationColorConnection = nil
	self.detailsNameLabel = nil
	self.detailsSubtitleLabel = nil
	self.detailsOwnedLabel = nil

	self.detailsViewportFrame = nil
	self.detailsViewportCamera = nil
	self.detailsViewportModel = nil
	self.detailsViewportModelCenter = nil
	self.detailsViewportRotateConnect = nil

	self.categoryFill = nil
	self.categoryFracLabel = nil
	self.discoveredLabel = nil
	self.milestoneButtonsContainer = nil
	self.milestoneButtonTemplate = nil
	self.renderedMilestoneButtons = {}

	return self
end

local singleton = ClientIndexManager.new()

return singleton
