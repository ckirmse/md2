--!strict
local utils = require("@game/ReplicatedStorage/Shared/utils")

-- nothing references TopBarPlus, but requiring it loads and configures the vendored library
-- (this is its only require site as of 2026-august-12)
local _TopBarPlus = require("./TopBarPlus")


local cameraManager = require("./CameraManager")
local clientAbilityStore = require("./ClientAbilityStore")
local clientAnalyticsManager = require("./ClientAnalyticsManager")
local clientAudioManager = require("./ClientAudioManager")
local clientBuyStore = require("./ClientBuyStore")
local clientChestManager = require("./ClientChestManager")
local clientClaimableCrystalManager = require("./ClientClaimableCrystalManager")
local clientConsumableCropManager = require("./ClientConsumableCropManager")
local clientContextualFtueManager = require("./ClientContextualFtueManager")
local clientCritterManager = require("./ClientCritterManager")
local clientCropManager = require("./ClientCropManager")
local clientCrystalManager = require("./ClientCrystalManager")
local clientDevTools = require("./ClientDevTools")
local clientDragonManager = require("./ClientDragonManager")
local clientEventHandlers = require("./ClientEventHandlers")
local clientExpansionTeleporter = require("./ClientExpansionTeleporter")
local clientFirstSessionOfferManager = require("./ClientFirstSessionOfferManager")
local clientFtueManager = require("./ClientFtueManager")
local clientGameConfigManager = require("./ClientGameConfigManager")
local clientGemManager = require("./ClientGemManager")
local clientIndexManager = require("./ClientIndexManager")
local clientLuckBillboardManager = require("./ClientLuckBillboardManager")
local clientLuckInfoManager = require("./ClientLuckInfoManager")
local clientMergeController = require("./ClientMergeController")
local clientMutationManager = require("./ClientMutationManager")
local clientMutationStore = require("./ClientMutationStore")
local clientNamePlateManager = require("./ClientNamePlateManager")
local clientNewBlueprintManager = require("./ClientNewBlueprintManager")
local clientNewMutationItemManager = require("./ClientNewMutationItemManager")
local clientNodeManager = require("./ClientNodeManager")
local clientOpenableCrateManager = require("./ClientOpenableCrateManager")
local clientOpenableCrystalManager = require("./ClientOpenableCrystalManager")
local clientOpenablePackManager = require("./ClientOpenablePackManager")
local clientOptionsManager = require("./ClientOptionsManager")
local clientPickupController = require("./ClientPickupController")
local clientPlayerManager = require("./ClientPlayerManager")
local clientPlayerAnimationManager = require("./ClientPlayerAnimationManager")
local clientPremiumStore = require("./ClientPremiumStore")
local clientPromptGroupManager = require("./ClientPromptGroupManager")
local clientShadowManager = require("./ClientShadowManager")
local clientSellStore = require("./ClientSellStore")
local clientTradePlayerList = require("./ClientTradePlayerList")
local clientTradeRequestedOverlay = require("./ClientTradeRequestedOverlay")
local clientTradingManager = require("./ClientTradingManager")
local clientVanityExpansionsManager = require("./ClientVanityExpansionsManager")
local clientVanityFencesManager = require("./ClientVanityFencesManager")
local clientVanityLockedManager = require("./ClientVanityLockedManager")
local clientVanityPlotsManager = require("./ClientVanityPlotsManager")
local clientVanityPreviewManager = require("./ClientVanityPreviewManager")
local clientVanityStore = require("./ClientVanityStore")
local clientVanityUnlockedManager = require("./ClientVanityUnlockedManager")
local clientWelcomeBackManager = require("./ClientWelcomeBackManager")
local overlayTracker = require("./OverlayTracker")
local clientRideController = require("./ClientRideController")
local screenGuiManager = require("./ScreenGuiManager")
local teleporters = require("./Teleporters")
local Version = require("./Version")

-- the modules that used to lazily require() each other inside init() (which made luau-lsp's
-- module graph cyclic) now receive their late-bound singletons here, mirroring the server's
-- GameController.initClasses() dependency injection; initClass must run before any :init()
local function initClasses()
	local deps = {
		clientAudioManager = clientAudioManager,
		clientBuyStore = clientBuyStore,
		clientDragonManager = clientDragonManager,
		clientFtueManager = clientFtueManager,
		clientPlayerAnimationManager = clientPlayerAnimationManager,
		clientRideController = clientRideController,
		clientTradePlayerList = clientTradePlayerList,
		clientVanityExpansionsManager = clientVanityExpansionsManager,
		clientVanityFencesManager = clientVanityFencesManager,
		clientVanityPlotsManager = clientVanityPlotsManager,
		clientVanityUnlockedManager = clientVanityUnlockedManager,
		screenGuiManager = screenGuiManager,
		teleporters = teleporters,
	}

	clientDevTools.initClass(deps)
	clientFtueManager.initClass(deps)
	clientOptionsManager.initClass(deps)
	clientRideController.initClass(deps)
	clientVanityUnlockedManager.initClass(deps)
	overlayTracker.initClass(deps)
	screenGuiManager.initClass(deps)
end

-- from https://devforum.roblox.com/t/resetbuttoncallback-has-not-been-registered-by-the-corescripts/78470/5

local coreCall: (string, ...any) -> ...any do
	local MAX_RETRIES = 500

	local StarterGui = game:GetService("StarterGui")

	function coreCall(method: string, ...: any): ...any
		local result = {}
		for retries = 1, MAX_RETRIES do
			result = {pcall((StarterGui :: any)[method], StarterGui, ...)}
			if result[1] then
				break
			end
			task.wait(0.2)
		end
		return unpack(result)
	end
end


local function initRobloxCore()
	coreCall("SetCoreGuiEnabled", Enum.CoreGuiType.Backpack, false)
	coreCall("SetCore", "ResetButtonCallback", false)
end

local function initSatchel()
	--print("hack overriding rich text on items")

	local function setupInventorySlot(slot: any)
		local toolName = slot:FindFirstChild("ToolName")
		if toolName then
			toolName.RichText = true
			toolName.Size = UDim2.new(1, 0, 1, 0)
			toolName.TextSize = 14
		end

		local toolNumber = slot:FindFirstChild("Number")
		if toolNumber then
			toolNumber.Size = UDim2.new(0.2, 0, 0.2, 0)
		end

	end

	local player = game:GetService("Players").LocalPlayer :: Player
	local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance
	-- the backpack gui's shape only exists at runtime, so it is untyped here
	local root: any = (PlayerGui :: any).BackpackGui
	root.DescendantAdded:Connect(
		function(descendant: any)
			if descendant.name ~= "ToolName" then
				return
			end

			setupInventorySlot(descendant.Parent)
		end
	)
	local toolTextLabels = utils.getAllDescendantsByName(root, "ToolName") :: { any }
	for _, textLabel in toolTextLabels do
		setupInventorySlot(textLabel.Parent)
	end

	local scrollbarWidth = 20

	local backpackGui: any = (PlayerGui :: any).BackpackGui
	local Backpack = backpackGui:WaitForChild("Backpack")
	local Inventory = Backpack:WaitForChild("Inventory")
	local ScrollingFrame = Inventory:WaitForChild("ScrollingFrame")
	ScrollingFrame.Size = UDim2.new(ScrollingFrame.Size.X.Scale, scrollbarWidth + 1, ScrollingFrame.Size.Y.Scale, ScrollingFrame.Size.Y.Offset)
	ScrollingFrame.ScrollBarThickness = scrollbarWidth
	ScrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 0, 0)

end

local function init()
	print("Version commit", Version.commit)

	initRobloxCore()

	initSatchel()

	initClasses()

	clientAnalyticsManager:init()

	clientPlayerManager:init()

	clientGameConfigManager:init()
	clientAbilityStore:init()
	clientBuyStore:init()
	-- legacy/dormant (2026-august-20): gem-selling removed, Sell Store kept but never initialized
	-- clientSellStore:init()
	clientOptionsManager:init()
	clientPremiumStore:init()
	clientVanityStore:init()
	clientMutationStore:init()
	clientIndexManager:init()
	teleporters:init()
	clientExpansionTeleporter:init()

	clientShadowManager:init()

	clientNamePlateManager:init()

	clientCropManager:init()
	clientDragonManager:init()
	clientCrystalManager:init()
	-- legacy/dormant (2026-august-20): gems no longer spawn, so nothing to animate/collect
	-- clientGemManager:init()
	clientConsumableCropManager:init()
	clientOpenableCrystalManager:init()
	clientOpenablePackManager:init()
	clientOpenableCrateManager:init()
	clientClaimableCrystalManager:init()
	clientNodeManager:init()
	clientChestManager:init()
	clientMutationManager:init()
	clientFtueManager:init()
	clientContextualFtueManager:init()
	clientFirstSessionOfferManager:init()
	clientLuckInfoManager:init()
	clientTradePlayerList:init()
	clientTradeRequestedOverlay:init()
	clientTradingManager:init()
	clientVanityLockedManager:init()
	clientVanityUnlockedManager:init()
	clientVanityPlotsManager:init()
	clientVanityPreviewManager:init()
	clientVanityFencesManager:init()
	clientVanityExpansionsManager:init()
	clientCritterManager:init()
	clientNewBlueprintManager:init()
	clientNewMutationItemManager:init()
	clientPromptGroupManager:init()
	clientLuckBillboardManager:init()
	clientWelcomeBackManager:init()

	clientMergeController:init()
	clientPickupController:init()
	clientRideController:init()

	overlayTracker:init()
	screenGuiManager:init()
	cameraManager:init()

	clientAudioManager:init()
	clientPlayerAnimationManager:init()

	--print("initializing client event handlers")
	clientEventHandlers:init()

end

init()
