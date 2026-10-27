--!strict

-- The reworked Index dialog (ported from the imported IndexFeature package): a tabbed overlay with one section per
-- rarity for dragons and eggs (a header with progress and a row reward button, then a tile per entry, silhouettes for
-- undiscovered ones), a single section for mutations and traits, and a bottom bar of category tier rewards. A claim
-- pop-up confirms row rewards; tier rewards claim at once. The HUD has an Index button and an IndexAlert button that
-- twitches while a reward the player has not looked at yet is claimable. All state comes from ClientIndexV2Data; the
-- server decides every claim.
local ClientIndexV2Manager = {}
ClientIndexV2Manager.__index = ClientIndexV2Manager

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local IndexRewardMath = require("@game/ReplicatedStorage/Shared/IndexRewardMath")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local ButtonTwitcher = require("./ButtonTwitcher")
local ClaimFeedback = require("./ClaimFeedback")
local clientIndexV2Data = require("./ClientIndexV2Data")
local ClientTicker = require("./ClientTicker")
local overlayTracker = require("./OverlayTracker")
local Types = require("./Types")

local DISPLAY_ORDER = 130
local INDEX_GUI_NAME = "PetIndex"
local SECTION_TEMPLATE_NAME = "SectionTemplate"
local TILE_TEMPLATE_NAME = "PetIconTemplate"
local REWARD_ICON_NAME = "RewardIcon"
local MILESTONE_TEMPLATE_NAME = "MilestoneTemplate"
local ROW_BUTTON_NAME = "RewardButton"
local STATE_SUFFIXES = { locked = "Locked", collect = "Collect", collected = "Collected" }
local COLLECTED_TINT = Color3.new(1, 1, 1)
local SILHOUETTE_TINT = Color3.new(0, 0, 0)
local COLLECTED_BACKGROUND = Color3.fromRGB(45, 45, 45)
local SILHOUETTE_BACKGROUND = Color3.fromRGB(120, 120, 120)
local CLAIMABLE_COLOR = Color3.fromRGB(0, 200, 60)
local INACTIVE_TAB_TRANSPARENCY = 0.6
local CLAIM_POP_SCALE = 1.15
local CLAIM_POP_SEC = 0.12
-- one press outside the panel reaches us twice (InputBegan, then the overlay's outside click), so the second report
-- within this window is ignored
local POP_UP_CONFIRM_GRACE_SEC = 0.3

-- the imported GUI names its tabs after pets and workers; the dragon and egg tabs may keep those names
local TAB_CATEGORIES: { [string]: number } = {
	PetsTab = Enums.IndexCategory.DRAGON,
	DragonsTab = Enums.IndexCategory.DRAGON,
	EggsTab = Enums.IndexCategory.EGG,
	MutationsTab = Enums.IndexCategory.MUTATION,
	TraitsTab = Enums.IndexCategory.TRAIT,
}

-- only dragons and eggs have rarity sections and row rewards; mutations and traits are one section
local RARITY_CATEGORIES: { [number]: boolean } = {
	[Enums.IndexCategory.DRAGON] = true,
	[Enums.IndexCategory.EGG] = true,
}

-- the gui's shape only exists in Studio, so its instances are untyped here
type StateTemplates = {
	locked: any,
	collect: any,
	collected: any,
}

type ClientIndexV2ManagerFields = {
	gui: any?,
	mainFrame: any?,
	scrollFrame: any?,
	sectionTemplate: any?,
	tileTemplate: any?,
	rowTemplates: StateTemplates?,
	bonusChip: any?,
	bottomBar: any?,
	milestoneTemplates: StateTemplates?,
	milestoneSingleTemplates: StateTemplates?,
	popUp: any?,
	popUpTierId: string?,
	popUpDisabled: boolean,
	popUpInputConnection: RBXScriptConnection?,
	popUpConfirmedAt: number,
	random: Random,
	indexButton: any?,
	alertButton: any?,
	twitcher: ButtonTwitcher.ButtonTwitcher?,
	seenClaimableTierIds: { [string]: boolean },
	tabButtons: { [number]: any },
	tabBadges: { [number]: any },
	selectedCategory: number,
	rewardButtonsByTierId: { [string]: any },
	panelOpen: boolean,
}

export type ClientIndexV2Manager = typeof(setmetatable({} :: ClientIndexV2ManagerFields, ClientIndexV2Manager))

type Milestone = IndexRewardMath.Milestone

local function setLabelText(parent: any, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function isPositionInside(guiObject: GuiObject, position: Vector3): boolean
	local topLeft = guiObject.AbsolutePosition
	local bottomRight = topLeft + guiObject.AbsoluteSize
	return position.X >= topLeft.X
		and position.X <= bottomRight.X
		and position.Y >= topLeft.Y
		and position.Y <= bottomRight.Y
end

-- clones the three authored state buttons out of their parent and removes the originals so authored placeholders
-- never show in the live panel
local function takeStateTemplates(parent: any, baseName: string): StateTemplates?
	local templates: any = {}
	for key, suffix in STATE_SUFFIXES do
		local name = baseName .. suffix
		local template = parent:FindFirstChild(name)
		if not template or not template:IsA("TextButton") then
			warn("ClientIndexV2Manager: missing template", name, "in", parent:GetFullName())
			return nil
		end
		templates[key] = template:Clone()
	end

	for _, child in parent:GetChildren() do
		if child:IsA("TextButton") and string.sub(child.Name, 1, #baseName) == baseName then
			child:Destroy()
		end
	end

	return templates :: StateTemplates
end

function ClientIndexV2Manager.isOpen(self: ClientIndexV2Manager): boolean
	return self.panelOpen
end

function ClientIndexV2Manager.setOpen(self: ClientIndexV2Manager, open: boolean)
	local mainFrame = self.mainFrame
	if not mainFrame or self.panelOpen == open then
		return
	end

	self.panelOpen = open
	mainFrame.Visible = open
	local gui = self.gui
	if gui then
		gui.Enabled = open
	end
	-- re-render on open so a reset (or any change) while the panel was closed is reflected
	if open then
		self:markClaimableSeen()
		self:render()
		overlayTracker:notifyBeginOverlay((self :: any) :: Types.Overlay)
	else
		self:closePopUp()
		overlayTracker:notifyEndOverlay((self :: any) :: Types.Overlay)
	end
end

function ClientIndexV2Manager.toggle(self: ClientIndexV2Manager)
	if not clientIndexV2Data:hasData() then
		warn("ClientIndexV2Manager: no Index data has arrived from the server")
		return
	end

	self:setOpen(not self.panelOpen)
end

function ClientIndexV2Manager.getGuiRoot(self: ClientIndexV2Manager): any
	return self.mainFrame
end

function ClientIndexV2Manager.getHudElements(self: ClientIndexV2Manager): { number }
	return {}
end

function ClientIndexV2Manager.doesWantBlur(self: ClientIndexV2Manager): boolean
	return false
end

-- called by the overlay tracker when another overlay takes over
function ClientIndexV2Manager.notifyForceEnd(self: ClientIndexV2Manager)
	self:closePopUp()
	self.panelOpen = false
	local mainFrame = self.mainFrame
	if mainFrame then
		mainFrame.Visible = false
	end
	local gui = self.gui
	if gui then
		gui.Enabled = false
	end
end

function ClientIndexV2Manager.notifyClickOutside(self: ClientIndexV2Manager)
	-- a press outside the whole panel while the pop-up is showing still counts as "anywhere outside the pop-up": it
	-- collects rather than closing the index
	if self.popUpTierId then
		self:confirmPopUp()
		return
	end

	if workspace:GetServerTimeNow() - self.popUpConfirmedAt < POP_UP_CONFIRM_GRACE_SEC then
		return
	end

	self:setOpen(false)
end

function ClientIndexV2Manager.selectCategory(self: ClientIndexV2Manager, category: number)
	if self.selectedCategory == category then
		return
	end

	self.selectedCategory = category
	self:updateTabVisuals()
	self:render()
end

function ClientIndexV2Manager.updateTabVisuals(self: ClientIndexV2Manager)
	for category, tab in self.tabButtons do
		local isSelected = category == self.selectedCategory
		tab.ImageTransparency = if isSelected then 0 else INACTIVE_TAB_TRANSPARENCY
		local stroke = tab:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = isSelected
		end
	end
end

function ClientIndexV2Manager.getClaimableTierIds(self: ClientIndexV2Manager, category: number?): { string }
	local tierIds: { string } = {}
	for _, categoryData in clientIndexV2Data:getCategories() do
		if category and categoryData.category ~= category then
			continue
		end

		for _, milestone in clientIndexV2Data:getMilestones(categoryData.category) do
			if milestone.isClaimable then
				table.insert(tierIds, milestone.tierId)
			end
		end
	end

	return tierIds
end

-- tab badges show raw claimability (not the HUD's "unseen" nudge) so they persist until the reward is claimed
function ClientIndexV2Manager.updateTabBadges(self: ClientIndexV2Manager)
	for category, badge in self.tabBadges do
		badge.Visible = #self:getClaimableTierIds(category) > 0
	end
end

-- the HUD alert is a nudge for rewards the player has not looked at yet, not a persistent "unclaimed" badge; opening
-- the index counts as looking
function ClientIndexV2Manager.markClaimableSeen(self: ClientIndexV2Manager)
	for _, tierId in self:getClaimableTierIds(nil) do
		self.seenClaimableTierIds[tierId] = true
	end
end

function ClientIndexV2Manager.hasUnseenClaimable(self: ClientIndexV2Manager): boolean
	for _, tierId in self:getClaimableTierIds(nil) do
		if not self.seenClaimableTierIds[tierId] then
			return true
		end
	end

	return false
end

function ClientIndexV2Manager.setProgress(
	self: ClientIndexV2Manager,
	container: any,
	collected: number,
	total: number,
	color: Color3,
	barName: string?
)
	local bar = container:FindFirstChild(barName or "ProgressBar")
	local fill = bar and bar:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(if total > 0 then collected / total else 0, 1)
		fill.BackgroundColor3 = color
	end

	local label = (bar and bar:FindFirstChild("ProgressLabel", true)) or container:FindFirstChild("ProgressLabel")
	if label and label:IsA("TextLabel") then
		label.Text = `{collected}/{total}`
	end
end

-- a claim already sent to the server shows as locked until the result lands so the button cannot be tapped twice
function ClientIndexV2Manager.pickStateTemplate(
	self: ClientIndexV2Manager,
	templates: StateTemplates,
	milestone: Milestone
): any
	if milestone.isClaimed then
		return templates.collected
	end

	if milestone.isClaimable and clientIndexV2Data:getPendingTierId() ~= milestone.tierId then
		return templates.collect
	end

	return templates.locked
end

-- row buttons open the pop-up (collect = claim flow, locked = info only); tier buttons claim at once with no pop-up
function ClientIndexV2Manager.createRewardButton(
	self: ClientIndexV2Manager,
	templates: StateTemplates,
	milestone: Milestone,
	isTier: boolean
): any
	local template = self:pickStateTemplate(templates, milestone)
	local button = template:Clone()
	button.Name = milestone.tierId
	button.Visible = true

	if template ~= templates.collected then
		local category = self:getMilestoneCategory(milestone.tierId)
		local icon = if category then clientIndexV2Data:getRewardIcon(category, milestone) else nil
		local percentLabel = button:FindFirstChild("PercentLabel")
		local iconLabel = percentLabel and percentLabel:FindFirstChild(REWARD_ICON_NAME)
		if icon and iconLabel and (iconLabel:IsA("ImageLabel") or iconLabel:IsA("ImageButton")) then
			iconLabel.Image = icon
		end
	end

	local tierId = milestone.tierId
	if template == templates.collect then
		button.Activated:Connect(function()
			if isTier then
				self:tryClaim(tierId)
			else
				self:openPopUp(tierId, false)
			end
		end)
	elseif template == templates.locked and not isTier then
		button.Activated:Connect(function()
			self:openPopUp(tierId, true)
		end)
	end

	self.rewardButtonsByTierId[tierId] = button
	return button
end

function ClientIndexV2Manager.addTile(
	self: ClientIndexV2Manager,
	parent: any,
	order: number,
	category: number,
	entry: clientIndexV2Data.Entry,
	isCollected: boolean
)
	local template = self.tileTemplate
	if not template then
		return
	end

	local tile = template:Clone()
	tile.Name = tostring(entry.key)
	tile.LayoutOrder = order
	-- only dragons and eggs have item pictures so far; the other tiles show their name until there is art
	local iconAssetId = if RARITY_CATEGORIES[category] then ItemIcons.getItemIconAssetId(tostring(entry.key)) else nil
	tile.Image = iconAssetId or ""
	tile.ImageColor3 = if isCollected then COLLECTED_TINT else SILHOUETTE_TINT
	tile.BackgroundColor3 = if isCollected then COLLECTED_BACKGROUND else SILHOUETTE_BACKGROUND
	tile.Visible = true

	local label = tile:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = if isCollected then entry.displayName else "???"
		if isCollected and RARITY_CATEGORIES[category] then
			label.TextColor3 = utils.getColorForRarity(entry.group)
		end
	end

	tile.Parent = parent
end

function ClientIndexV2Manager.addSection(
	self: ClientIndexV2Manager,
	order: number,
	category: number,
	headerText: string,
	color: Color3,
	entries: { clientIndexV2Data.Entry },
	rowMilestone: Milestone?
)
	local template = self.sectionTemplate
	local scrollFrame = self.scrollFrame
	if not template or not scrollFrame then
		return
	end

	local section = template:Clone()
	section.Name = headerText
	section.LayoutOrder = order
	section.Visible = true

	local header = section:FindFirstChild("Header")
	local tiles = section:FindFirstChild("Tiles")
	if not header or not tiles then
		warn("ClientIndexV2Manager: SectionTemplate needs Header and Tiles")
		section:Destroy()
		return
	end

	local rarityLabel = header:FindFirstChild("RarityLabel")
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = string.upper(headerText)
		rarityLabel.TextColor3 = color
	end

	local collectedCount = 0
	for tileOrder, entry in entries do
		local isCollected = clientIndexV2Data:isDiscovered(category, entry.key)
		if isCollected then
			collectedCount += 1
		end
		self:addTile(tiles, tileOrder, category, entry, isCollected)
	end
	self:setProgress(header, collectedCount, #entries, color)

	local rowTemplates = self.rowTemplates
	if rowMilestone and rowTemplates then
		local button = self:createRewardButton(rowTemplates, rowMilestone, false)
		button.Parent = header
	end

	section.Parent = scrollFrame
end

function ClientIndexV2Manager.addTierButton(
	self: ClientIndexV2Manager,
	category: number,
	categoryData: any,
	milestonesFrame: any,
	templates: StateTemplates,
	milestone: Milestone,
	order: number
)
	local button = self:createRewardButton(templates, milestone, true)
	button.LayoutOrder = order
	local tier = categoryData.tiers[milestone.tierIndex :: number]
	setLabelText(button, "PercentLabel", clientIndexV2Data:getRewardText(category, milestone))
	setLabelText(button, "RewardLabel", `{if tier then tier.requiredPercent else 0}% Completion`)
	button.Parent = milestonesFrame
end

function ClientIndexV2Manager.renderBottomBar(
	self: ClientIndexV2Manager,
	category: number,
	milestones: { Milestone }
)
	local bottomBar = self.bottomBar
	local templates = self.milestoneTemplates
	local categoryData = clientIndexV2Data:getCategory(category)
	if not bottomBar or not templates or not categoryData then
		return
	end

	local normalFrame = bottomBar:FindFirstChild("Milestones")
	local singleFrame = bottomBar:FindFirstChild("MilestonesSingle")
	local longBar = bottomBar:FindFirstChild("ProgressBarLong")
	local isSingleTier = clientIndexV2Data:isSingleTierBar()
		and self.milestoneSingleTemplates ~= nil
		and singleFrame ~= nil
		and longBar ~= nil
	if clientIndexV2Data:isSingleTierBar() and not isSingleTier then
		warn("ClientIndexV2Manager: singleTierBar needs BottomBar/MilestonesSingle with its templates and ProgressBarLong; showing every tier")
	end

	if not normalFrame then
		return
	end

	local function setShown(guiObject: any, isShown: boolean)
		if guiObject and guiObject:IsA("GuiObject") then
			guiObject.Visible = isShown
		end
	end
	setShown(normalFrame, not isSingleTier)
	setShown(bottomBar:FindFirstChild("ProgressBar"), not isSingleTier)
	setShown(singleFrame, isSingleTier)
	setShown(longBar, isSingleTier)

	local milestonesFrame: any = if isSingleTier then singleFrame else normalFrame
	local activeTemplates: StateTemplates = if isSingleTier then self.milestoneSingleTemplates :: StateTemplates else templates
	for _, child in milestonesFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local progressLabel = bottomBar:FindFirstChild("ProgressLabel")
	if progressLabel and progressLabel:IsA("GuiObject") then
		progressLabel.Position = if isSingleTier then UDim2.new(0.215, 0, 1, 0) else UDim2.new(0, 0, 1, 0)
	end

	setLabelText(bottomBar, "CategoryLabel", string.upper(categoryData.name) .. "S")

	local shown: Milestone? = nil
	local collected, total = 0, 0
	local order = 0
	for _, milestone in milestones do
		if milestone.kind ~= IndexRewardMath.Kind.TIER then
			continue
		end

		shown = milestone
		collected, total = milestone.collected, milestone.total
		if isSingleTier then
			if not milestone.isClaimed then
				break
			end
			continue
		end

		order += 1
		self:addTierButton(category, categoryData, milestonesFrame, activeTemplates, milestone, order)
	end

	if isSingleTier and shown then
		self:addTierButton(category, categoryData, milestonesFrame, activeTemplates, shown, 1)
		total = shown.threshold
		collected = math.min(collected, total)
	end

	self:setProgress(bottomBar, collected, total, CLAIMABLE_COLOR, if isSingleTier then "ProgressBarLong" else nil)
	if not isSingleTier then
		setLabelText(
			bottomBar,
			"ProgressLabel",
			`{collected}/{total} ({IndexRewardMath.getDisplayPercent(collected, total)}%)`
		)
	end
end

function ClientIndexV2Manager.render(self: ClientIndexV2Manager)
	local scrollFrame = self.scrollFrame
	if not scrollFrame or not self.sectionTemplate then
		return
	end

	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(self.rewardButtonsByTierId)

	local category = self.selectedCategory
	local categoryData = clientIndexV2Data:getCategory(category)
	if categoryData then
		local milestones = clientIndexV2Data:getMilestones(category)

		if RARITY_CATEGORIES[category] then
			local entriesByRarity: { [number]: { clientIndexV2Data.Entry } } = {}
			for _, entry in categoryData.entries do
				entriesByRarity[entry.group] = entriesByRarity[entry.group] or {}
				table.insert(entriesByRarity[entry.group], entry)
			end

			local order = 0
			for _, rarity in Enums.getAllValues(Enums.Rarity) do
				local rarityEntries = entriesByRarity[rarity]
				if not rarityEntries then
					continue
				end

				order += 1
				local rowMilestone =
					IndexRewardMath.findMilestone(milestones, IndexRewardMath.makeRowTierId(category, rarity))
				self:addSection(
					order,
					category,
					Enums.getPublicName(Enums.Rarity, rarity) :: string,
					utils.getColorForRarity(rarity),
					rarityEntries,
					rowMilestone
				)
			end
		else
			-- categories without rarities are one section with no row reward
			self:addSection(1, category, categoryData.name .. "s", COLLECTED_TINT, categoryData.entries, nil)
		end

		self:renderBottomBar(category, milestones)
	end

	scrollFrame.CanvasPosition = Vector2.zero
	self:refreshBonusChip()
	self:updateAlert()
	self:updateTabBadges()
end

function ClientIndexV2Manager.refreshBonusChip(self: ClientIndexV2Manager)
	local chip = self.bonusChip
	if chip then
		chip.Text = `Index Bonus: +{clientIndexV2Data:getIncomeBonusPercent()}%`
	end
end

function ClientIndexV2Manager.updateAlert(self: ClientIndexV2Manager)
	local alertButton = self.alertButton
	if not alertButton then
		return
	end

	if self.panelOpen then
		self:markClaimableSeen()
	end

	local isClaimable = self:hasUnseenClaimable()
	-- the alert is a sibling layered over the base button, so the base must hide or it shows through while the alert
	-- twitches
	local indexButton = self.indexButton
	if indexButton then
		indexButton.Visible = not isClaimable
	end
	alertButton.Visible = isClaimable

	local twitcher = self.twitcher
	if isClaimable and twitcher then
		twitcher:updateIfNeeded()
	end
end

function ClientIndexV2Manager.findMilestone(self: ClientIndexV2Manager, tierId: string): Milestone?
	for _, categoryData in clientIndexV2Data:getCategories() do
		local milestone =
			IndexRewardMath.findMilestone(clientIndexV2Data:getMilestones(categoryData.category), tierId)
		if milestone then
			return milestone
		end
	end

	return nil
end

function ClientIndexV2Manager.getMilestoneCategory(self: ClientIndexV2Manager, tierId: string): number?
	for _, categoryData in clientIndexV2Data:getCategories() do
		if IndexRewardMath.findMilestone(clientIndexV2Data:getMilestones(categoryData.category), tierId) then
			return categoryData.category
		end
	end

	return nil
end

function ClientIndexV2Manager.openPopUp(self: ClientIndexV2Manager, tierId: string, isDisabled: boolean)
	local popUp = self.popUp
	if not popUp or self.popUpTierId or clientIndexV2Data:isClaimPending() then
		return
	end

	local category = self:getMilestoneCategory(tierId)
	local milestone = self:findMilestone(tierId)
	if not category or not milestone or (not isDisabled and not milestone.isClaimable) then
		return
	end

	self.popUpTierId = tierId
	self.popUpDisabled = isDisabled

	local collectButton = popUp:FindFirstChild("RewardButtonCollect")
	if collectButton and collectButton:IsA("GuiObject") then
		collectButton.Visible = not isDisabled
	end
	local disabledButton = popUp:FindFirstChild("RewardButtonDisabled")
	if disabledButton and disabledButton:IsA("GuiObject") then
		disabledButton.Visible = isDisabled
	end

	local rewardText = clientIndexV2Data:getRewardText(category, milestone)
	setLabelText(popUp, "Title", rewardText)
	local outerTitle = popUp:FindFirstChild("Title")
	if outerTitle then
		setLabelText(outerTitle, "Title", rewardText)
	end
	local rarityName = if milestone.rarity then `{Enums.getPublicName(Enums.Rarity, milestone.rarity)} ` else ""
	local popUpIcon = clientIndexV2Data:getRewardIcon(category, milestone)
	local popUpIconLabel = popUp:FindFirstChild(REWARD_ICON_NAME)
	if popUpIcon and popUpIconLabel and (popUpIconLabel:IsA("ImageLabel") or popUpIconLabel:IsA("ImageButton")) then
		popUpIconLabel.Image = popUpIcon
	end
	setLabelText(popUp, "RewardDetails", `Collect every {rarityName}entry: {milestone.collected}/{milestone.total}`)

	popUp.Visible = true

	-- the pop-up's own Collect button is a descendant, so it is excluded here and handled by its Activated connection;
	-- input outside the pop-up but inside the index panel never reaches the overlay tracker's outside-click path
	self.popUpInputConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		-- the disabled pop-up dismisses on a tap anywhere, the pop-up included; the claimable one leaves taps inside to
		-- its Collect button
		if not self.popUpDisabled and isPositionInside(popUp, input.Position) then
			return
		end

		self:confirmPopUp()
	end)
end

function ClientIndexV2Manager.closePopUp(self: ClientIndexV2Manager)
	local connection = self.popUpInputConnection
	if connection then
		connection:Disconnect()
		self.popUpInputConnection = nil
	end

	self.popUpTierId = nil
	self.popUpDisabled = false
	local popUp = self.popUp
	if popUp then
		popUp.Visible = false
	end
end

function ClientIndexV2Manager.confirmPopUp(self: ClientIndexV2Manager)
	local tierId = self.popUpTierId
	if not tierId then
		return
	end

	local isDisabled = self.popUpDisabled
	self:closePopUp()
	self.popUpConfirmedAt = workspace:GetServerTimeNow()
	if not isDisabled then
		self:tryClaim(tierId)
	end
end

function ClientIndexV2Manager.tryClaim(self: ClientIndexV2Manager, tierId: string)
	if clientIndexV2Data:tryClaim(tierId) then
		local button = self.rewardButtonsByTierId[tierId]
		if button then
			button.Active = false
		end
	end
end

function ClientIndexV2Manager.popButton(self: ClientIndexV2Manager, button: GuiObject)
	local baseSize = button.Size
	local grow =
		TweenService:Create(button, TweenInfo.new(CLAIM_POP_SEC, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(
				baseSize.X.Scale * CLAIM_POP_SCALE,
				baseSize.X.Offset,
				baseSize.Y.Scale * CLAIM_POP_SCALE,
				baseSize.Y.Offset
			),
		})
	grow.Completed:Connect(function()
		TweenService:Create(button, TweenInfo.new(CLAIM_POP_SEC), { Size = baseSize }):Play()
	end)
	grow:Play()
end

-- the server's answer to a claim; the index data is already updated, so this adds the celebration
function ClientIndexV2Manager.notifyClaimResult(self: ClientIndexV2Manager, tierId: string, isSuccess: boolean)
	if not isSuccess or not self.panelOpen then
		return
	end

	local button = self.rewardButtonsByTierId[tierId]
	if button and button.Parent then
		self:popButton(button)
	end

	local gui = self.gui
	if gui then
		ClaimFeedback.play(gui, self.random)
	end
end

-- any change to the index data (it arrived, an entry was discovered, a claim finished or timed out)
function ClientIndexV2Manager.notifyDataChanged(self: ClientIndexV2Manager)
	if self.panelOpen then
		self:render()
	else
		self:updateAlert()
	end
end

-- the HUD buttons live in the main HUD ScreenGui, which ScreenGuiManager owns and wires up
function ClientIndexV2Manager.setHudButtons(self: ClientIndexV2Manager, indexButton: any, alertButton: any)
	self.indexButton = indexButton
	self.alertButton = alertButton
	self.twitcher = ButtonTwitcher.new(alertButton)
	alertButton.Visible = false
	self:updateAlert()
end

function ClientIndexV2Manager.setupGui(self: ClientIndexV2Manager, gui: any): boolean
	local mainFrame: any = gui:FindFirstChild("Main")
	local title: any = mainFrame and mainFrame:FindFirstChild("Title")
	local exitButton: any = title and title:FindFirstChild("Exit")
	local itemArea: any = mainFrame and mainFrame:FindFirstChild("ItemArea")
	local scrollFrame: any = itemArea and itemArea:FindFirstChild("PetOptionsScroll")
	local bottomBar: any = mainFrame and mainFrame:FindFirstChild("BottomBar")
	local milestonesFrame: any = bottomBar and bottomBar:FindFirstChild("Milestones")
	local popUp: any = mainFrame and mainFrame:FindFirstChild("PopUp")
	local popUpCollect: any = popUp and popUp:FindFirstChild("RewardButtonCollect")
	local tabs: any = mainFrame and mainFrame:FindFirstChild("Tabs")
	if not (mainFrame and exitButton and scrollFrame and milestonesFrame and popUpCollect and tabs) then
		warn(
			"ClientIndexV2Manager: PetIndex needs Main with Title/Exit, ItemArea/PetOptionsScroll, BottomBar/Milestones, PopUp/RewardButtonCollect and Tabs; the Index dialog is disabled"
		)
		return false
	end

	local sectionTemplate: any = scrollFrame:FindFirstChild(SECTION_TEMPLATE_NAME)
	local sectionHeader: any = sectionTemplate and sectionTemplate:FindFirstChild("Header")
	local sectionTiles: any = sectionTemplate and sectionTemplate:FindFirstChild("Tiles")
	local tileTemplate: any = sectionTiles and sectionTiles:FindFirstChild(TILE_TEMPLATE_NAME)
	if not (sectionTemplate and sectionHeader and tileTemplate) then
		warn(
			"ClientIndexV2Manager: PetIndex needs ItemArea/PetOptionsScroll/SectionTemplate with a Header and Tiles/PetIconTemplate; the Index dialog is disabled"
		)
		return false
	end

	mainFrame.Visible = false
	self.mainFrame = mainFrame
	self.scrollFrame = scrollFrame
	self.bottomBar = bottomBar
	self.popUp = popUp
	popUp.Visible = false
	self.bonusChip = title:FindFirstChild("BonusChip")

	exitButton.Activated:Connect(function()
		self:setOpen(false)
	end)
	popUpCollect.Activated:Connect(function()
		self:confirmPopUp()
	end)

	-- the clone keeps the header and tiles, minus the authored placeholder tile and row buttons
	local sectionClone = sectionTemplate:Clone()
	self.tileTemplate = tileTemplate:Clone()
	local cloneTile = sectionClone.Tiles:FindFirstChild(TILE_TEMPLATE_NAME)
	if cloneTile then
		cloneTile:Destroy()
	end
	self.rowTemplates = takeStateTemplates(sectionClone.Header, ROW_BUTTON_NAME)
	self.sectionTemplate = sectionClone

	-- the authored placeholder sections are design-time filler; real sections are cloned per rarity
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	self.milestoneTemplates = takeStateTemplates(milestonesFrame, MILESTONE_TEMPLATE_NAME)
	local milestonesSingleFrame: any = bottomBar:FindFirstChild("MilestonesSingle")
	if milestonesSingleFrame then
		self.milestoneSingleTemplates = takeStateTemplates(milestonesSingleFrame, MILESTONE_TEMPLATE_NAME)
	end

	for _, tab in tabs:GetChildren() do
		if not tab:IsA("ImageButton") then
			continue
		end

		local category = TAB_CATEGORIES[tab.Name]
		if not category then
			tab.ImageTransparency = INACTIVE_TAB_TRANSPARENCY
			tab.AutoButtonColor = false
			continue
		end

		self.tabButtons[category] = tab
		local badge = tab:FindFirstChild("Alert")
		if badge and badge:IsA("GuiObject") then
			self.tabBadges[category] = badge
		else
			warn(`ClientIndexV2Manager: Index tab {tab.Name} has no Alert badge`)
		end

		tab.Activated:Connect(function()
			self:selectCategory(category)
		end)
	end
	self:updateTabVisuals()

	return true
end

function ClientIndexV2Manager.init(self: ClientIndexV2Manager)
	clientIndexV2Data:addChangedListener(function()
		self:notifyDataChanged()
	end)
	clientIndexV2Data:addClaimListener(function(tierId: string, isSuccess: boolean)
		self:notifyClaimResult(tierId, isSuccess)
	end)

	ClientTicker.every(1, function()
		local alertButton = self.alertButton
		local twitcher = self.twitcher
		if alertButton and alertButton.Visible and twitcher then
			twitcher:updateIfNeeded()
		end
	end)

	-- authored in Studio, so a missing one must not hang client startup
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui: any = playerGui:WaitForChild(INDEX_GUI_NAME, 10)
	if not gui then
		warn("ClientIndexV2Manager: the PetIndex gui is missing from PlayerGui; the Index dialog is disabled")
		return
	end

	-- the sections are cloned from templates at runtime, so a respawn must not recreate the gui from StarterGui
	gui.ResetOnSpawn = false
	gui.DisplayOrder = DISPLAY_ORDER
	-- ScreenGuiManager disables every unlisted gui at startup, so the dialog enables its gui when it opens
	gui.Enabled = false
	if self:setupGui(gui) then
		self.gui = gui
	end
end

function ClientIndexV2Manager.new(): ClientIndexV2Manager
	local self = setmetatable({} :: ClientIndexV2ManagerFields, ClientIndexV2Manager)

	self.gui = nil
	self.mainFrame = nil
	self.scrollFrame = nil
	self.sectionTemplate = nil
	self.tileTemplate = nil
	self.rowTemplates = nil
	self.bonusChip = nil
	self.bottomBar = nil
	self.milestoneTemplates = nil
	self.milestoneSingleTemplates = nil
	self.popUp = nil
	self.popUpTierId = nil
	self.popUpDisabled = false
	self.popUpInputConnection = nil
	self.popUpConfirmedAt = 0
	self.random = Random.new()
	self.indexButton = nil
	self.alertButton = nil
	self.twitcher = nil
	self.seenClaimableTierIds = {}
	self.tabButtons = {}
	self.tabBadges = {}
	self.selectedCategory = Enums.IndexCategory.DRAGON
	self.rewardButtonsByTierId = {}
	self.panelOpen = false

	return self
end

local singleton = ClientIndexV2Manager.new()

return singleton
