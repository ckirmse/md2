--!strict

local ClientDevTools = {}
ClientDevTools.__index = ClientDevTools

local statsService = game:GetService("Stats")

local Iris = require("./Iris")

local clientChestManager = require("./ClientChestManager")
local clientClaimableCrystalManager = require("./ClientClaimableCrystalManager")
local clientConsumableCropManager = require("./ClientConsumableCropManager")
local clientCropManager = require("./ClientCropManager")
local clientCrystalManager = require("./ClientCrystalManager")
local clientCustomerTools = require("./ClientCustomerTools")
local Types = require("./Types")
local clientDragonManager: Types.ClientDragonManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local clientGemManager = require("./ClientGemManager")
local clientMergeController = require("./ClientMergeController")
local clientMutationManager = require("./ClientMutationManager")
local clientNamePlateManager = require("./ClientNamePlateManager")
local clientNewBlueprintManager = require("./ClientNewBlueprintManager")
local clientNodeManager = require("./ClientNodeManager")
local clientOpenableCrystalManager = require("./ClientOpenableCrystalManager")
local clientOpenablePackManager = require("./ClientOpenablePackManager")
local clientPickupController = require("./ClientPickupController")
local clientPlayerManager = require("./ClientPlayerManager")
local clientPlayerAttributesManager = require("./ClientPlayerAttributesManager")
local clientRideController = require("./ClientRideController")
local clientShadowManager = require("./ClientShadowManager")
local clientWeatherManager = require("./ClientWeatherManager")
local clientNetopsTools = require("./ClientNetopsTools")

local teleporters = require("./Teleporters")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Abilities = require("@game/ReplicatedStorage/Shared/Abilities")
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local ContextualFtueCatalog = require("@game/ReplicatedStorage/Shared/ContextualFtueCatalog")
local Elements = require("@game/ReplicatedStorage/Shared/Elements")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local indexCatalog = require("@game/ReplicatedStorage/Shared/IndexCatalog")
local indexHelpers = require("@game/ReplicatedStorage/Shared/IndexHelpers")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local player = game:GetService("Players").LocalPlayer :: Player

local fenceEnums = {
	enums.VanityPlacements.MAIN_PLOT_FENCE_1,
	enums.VanityPlacements.MAIN_PLOT_FENCE_2,
	enums.VanityPlacements.MAIN_PLOT_FENCE_3,
	enums.VanityPlacements.MAIN_PLOT_FENCE_4,
	enums.VanityPlacements.MAIN_PLOT_FENCE_5,
	enums.VanityPlacements.MAIN_PLOT_FENCE_6,
	enums.VanityPlacements.MAIN_PLOT_FENCE_7,
	enums.VanityPlacements.MAIN_PLOT_FENCE_8,
	enums.VanityPlacements.MAIN_PLOT_FENCE_9,
}

local expansionInnerEnums = {
	enums.VanityPlacements.EXPANSION_1_INNER,
	enums.VanityPlacements.EXPANSION_2_INNER,
	enums.VanityPlacements.EXPANSION_3_INNER,
	enums.VanityPlacements.EXPANSION_4_INNER,
}
local expansionOuterEnums = {
	enums.VanityPlacements.EXPANSION_1_OUTER,
	enums.VanityPlacements.EXPANSION_2_OUTER,
	enums.VanityPlacements.EXPANSION_3_OUTER,
	enums.VanityPlacements.EXPANSION_4_OUTER,
}

local SCREENSHOT_CATEGORIES = { "Dragons", "DragonEggs", "Crops", "Crystals", "Packs", "Keys", "Blueprints" }
local SCREENSHOT_OBJECT_ROTATION_STEP = math.rad(5)
local SCREENSHOT_OBJECT_FACE_CAMERA_EXTRA_YAW = -math.rad(20)
local SCREENSHOT_PIVOT_ROTATION_CATEGORIES = {
	Crops = true,
}

type ClientDevToolsFields = {
	state: any,
}

export type ClientDevTools = typeof(setmetatable({} :: ClientDevToolsFields, ClientDevTools))

function ClientDevTools.init(self: ClientDevTools, devToolSettings: any)
	--print("dev tool settings", devToolSettings)


	local splendidDataFolder: any = player:WaitForChild("PlayerGui"):WaitForChild(Constants.SPLENDID_DATA_NAME)

	if self.state.debugUseBillboardsState:get() ~= devToolSettings.doUseBillboards then
		self.state.debugUseBillboardsChangeCountState:set(0)
		self.state.debugUseBillboardsState:set(devToolSettings.doUseBillboards)
	end

	self.state.debugUseCastersOtherPlayersState:set(true)
	self.state.debugShowShadowsState:set(false)

	local showStatsWindow = Iris.State(true)
	local showDevWindow = Iris.State(false)
	local showCustomerWindow = Iris.State(false)
	local showNetopsWindow = Iris.State(false)

	-- the gui's shape only exists in Studio, so it is untyped here
	local screenshotViewport: any = player:WaitForChild("PlayerGui"):WaitForChild("ItemScreenshotGui"):WaitForChild("PreviewViewport")
	screenshotViewport.LightColor = Color3.fromRGB(220, 220, 200)
	local screenshotCamera: any = nil
	local currentScreenshotClone: any = nil
	local currentScreenshotCameraPosition: any = nil
	local currentScreenshotCameraCenter: any = nil
	local currentScreenshotRotationCenter: any = nil

	local screenshotCategoryState = Iris.State("")
	local screenshotItemState = Iris.State("")
	local screenshotViewportEnabledState = Iris.State(false)
	local lastScreenshotCategory = ""

	screenshotViewport.Visible = screenshotViewportEnabledState:get()

	local function clearScreenshotPreview()
		if currentScreenshotClone then
			currentScreenshotClone:Destroy()
			currentScreenshotClone = nil
		end
		currentScreenshotCameraPosition = nil
	end

	local function updateScreenshotCameraFraming()
		if
			not currentScreenshotClone
			or not screenshotCamera
			or not currentScreenshotCameraCenter
			or not currentScreenshotCameraPosition
		then
			return
		end

		screenshotCamera.CFrame =
			CFrame.new(currentScreenshotCameraCenter + currentScreenshotCameraPosition, currentScreenshotCameraCenter)
	end

	local function spawnScreenshotItem(templatePath: any, cameraPosition: any, category: any)
		clearScreenshotPreview()

		local template = utils.getGameAssetPathReference(templatePath)
		if not template then
			return
		end

		screenshotViewportEnabledState:set(true)
		screenshotViewport.Visible = true

		local obj: any = template:Clone()
		obj.Parent = screenshotViewport
		currentScreenshotClone = obj
		currentScreenshotCameraPosition = cameraPosition

		if cameraPosition then
			local flatDirection = Vector3.new(cameraPosition.X, 0, cameraPosition.Z)
			if flatDirection.Magnitude > 0 then
				local position = obj:GetPivot().Position
				obj:PivotTo(
					CFrame.new(position, position + flatDirection.Unit)
						* CFrame.Angles(0, SCREENSHOT_OBJECT_FACE_CAMERA_EXTRA_YAW, 0)
				)
			end
		end

		local boundingBoxCenter = obj:GetBoundingBox().Position

		local rotationCenter
		if SCREENSHOT_PIVOT_ROTATION_CATEGORIES[category] then
			rotationCenter = obj:GetPivot().Position
		else
			rotationCenter = boundingBoxCenter
		end

		currentScreenshotRotationCenter = rotationCenter
		currentScreenshotCameraCenter = Vector3.new(rotationCenter.X, boundingBoxCenter.Y, rotationCenter.Z)

		if not screenshotCamera then
			screenshotCamera = Instance.new("Camera")
			screenshotCamera.Parent = screenshotViewport
		end
		screenshotViewport.CurrentCamera = screenshotCamera

		updateScreenshotCameraFraming()
	end

	local function rotateScreenshotItem(direction: number)
		if not currentScreenshotClone or not currentScreenshotRotationCenter then
			return
		end

		local angle = direction * SCREENSHOT_OBJECT_ROTATION_STEP
		local rotateAboutCenter = CFrame.new(currentScreenshotRotationCenter)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(-currentScreenshotRotationCenter)
		currentScreenshotClone:PivotTo(rotateAboutCenter * currentScreenshotClone:GetPivot())
	end

	Iris:Connect(function()
		--Iris.ShowDemoWindow()
		if not player.PlayerGui:FindFirstChild("SplendidData") then
			return
		end

		local devToolsDataFolder: any = splendidDataFolder:FindFirstChild("DevTools")
		if not devToolsDataFolder then
			return
		end

		local mergeableCount = clientMergeController:getMergeableCount()

		Iris.Window({ "Client Stats" }, {
			size = Iris.State(Vector2.new(200, 150)),
			position = Iris.State(Vector2.new(0, 50)),
			isOpened = showStatsWindow,
		})
		Iris.SameLine()
		if Iris.Button({ "Dev Window" }).clicked() then
			local state = not showDevWindow:get()
			if state then
				-- Roblox defers layout propagation to the render pass, so AutomaticSize on buttons
				-- evaluates against a zero-size container when the window is first created. A size
				-- change triggers a re-layout that fixes the computed sizes permanently.
				local size = self.state.windowSize:get()
				self.state.windowSize:set(Vector2.new(size.X + 1, size.Y))
				task.delay(0.02, function()
					self.state.windowSize:set(size)
				end)
			end
			showDevWindow:set(state)
		end
		if Iris.Button({ "Customer Window" }).clicked() then
			showCustomerWindow:set(not showCustomerWindow:get())
		end
		if Iris.Button({ "Netops Window" }).clicked() then
			showNetopsWindow:set(not showNetopsWindow:get())
		end
		Iris.End()

		Iris.Text({ string.format("Merge State: %s", clientMergeController:getMergeStatusName() :: string) })
		Iris.Text({ string.format("Mergeable: %i", mergeableCount) })
		Iris.Text({
			string.format(
				"Player: %.1f, %.1f, %.1f",
				(player.Character :: any).HumanoidRootPart.Position.X,
				(player.Character :: any).HumanoidRootPart.Position.Y,
				(player.Character :: any).HumanoidRootPart.Position.Z
			),
		})
		local plotPosition = (teleporters:getPlotCFrame() :: CFrame):ToObjectSpace((player.Character :: any).HumanoidRootPart.CFrame)
		Iris.Text({ string.format("In Plot: %.1f, %.1f, %.1f", plotPosition.X, plotPosition.Y, plotPosition.Z) })

		Iris.Text({ string.format("Physics Step Time: %i", statsService.PhysicsStepTime) })
		Iris.Text({ string.format("--- client map sizes ---") })

		Iris.Text({ string.format("Claimable Crystals: %i", clientClaimableCrystalManager:getMapSize()) })
		Iris.Text({ string.format("Consumable Crops: %i", clientConsumableCropManager:getMapSize()) })
		Iris.Text({ string.format("Crops: %i", clientCropManager:getMapSize()) })
		Iris.Text({ string.format("Crystals: %i", clientCrystalManager:getMapSize()) })
		Iris.Text({ string.format("Dragons: %i", clientDragonManager:getMapSize()) })
		Iris.Text({ string.format("Gems: %i", clientGemManager:getMapSize()) })
		Iris.Text({ string.format("Mutations: %i", clientMutationManager:getMapSize()) })
		Iris.Text({ string.format("Name Plates: %i", clientNamePlateManager:getMapSize()) })
		Iris.Text({ string.format("Nodes: %i", clientNodeManager:getMapSize()) })
		Iris.Text({ string.format("Openable Crystals: %i", clientOpenableCrystalManager:getMapSize()) })
		Iris.Text({ string.format("Openable Packs: %i", clientOpenablePackManager:getMapSize()) })
		Iris.Text({
			string.format(
				"Pickupable: %i (%i)",
				clientPickupController:getMapSize(),
				clientPickupController:getEnabledPickupableCount()
			),
		})
		Iris.Text({ string.format("Ride Targets: %i", clientRideController:getMapSize()) })
		Iris.Text({ string.format("Shadows: %i", clientShadowManager:getMapSize()) })
		Iris.Text({ string.format("Players: %i", clientPlayerManager:getMapSize()) })
		Iris.Text({ string.format("Chests: %i", clientChestManager:getMapSize()) })

		Iris.End()

		Iris.Window(
			{ "Dev Tools" },
			{ size = self.state.windowSize, position = self.state.windowPosition, isOpened = showDevWindow }
		)
		do
			Iris.SeparatorText({ "Debug" })
			local debugUseBillboardsCheckbox = Iris.Checkbox(
				{ "Use Billboards" },
				{ isChecked = self.state.debugUseBillboardsState }
			)
			if debugUseBillboardsCheckbox.checked() then
				self.state.debugUseBillboardsChangeCountState:set(
					self.state.debugUseBillboardsChangeCountState:get() + 1
				)
				if self.state.debugUseBillboardsChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setUseBillboards", true)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end
			if debugUseBillboardsCheckbox.unchecked() then
				self.state.debugUseBillboardsChangeCountState:set(
					self.state.debugUseBillboardsChangeCountState:get() + 1
				)
				if self.state.debugUseBillboardsChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setUseBillboards", false)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end
			local debugUseCastersOtherPlayersChangeCountState = Iris.State(0)
			local debugUseCastersOtherPlayers = Iris.Checkbox(
				{ "Render Casters For Other Player Shadows" },
				{ isChecked = self.state.debugUseCastersOtherPlayersState }
			)
			if debugUseCastersOtherPlayers.checked() then
				debugUseCastersOtherPlayersChangeCountState:set(debugUseCastersOtherPlayersChangeCountState:get() + 1)
				if debugUseCastersOtherPlayersChangeCountState:get() > 1 then
					clientShadowManager:setShouldProcessOtherPlayerShadows(true)
				end
			end
			if debugUseCastersOtherPlayers.unchecked() then
				debugUseCastersOtherPlayersChangeCountState:set(debugUseCastersOtherPlayersChangeCountState:get() + 1)
				if debugUseCastersOtherPlayersChangeCountState:get() > 1 then
					clientShadowManager:setShouldProcessOtherPlayerShadows(false)
				end
			end
			local debugShowShadowsChangeCountState = Iris.State(0)
			local debugShowShadows = Iris.Checkbox({ "Show Shadows" }, { isChecked = self.state.debugShowShadowsState })
			if debugShowShadows.checked() then
				debugShowShadowsChangeCountState:set(debugShowShadowsChangeCountState:get() + 1)
				if debugShowShadowsChangeCountState:get() > 1 then
					clientShadowManager:setShowShadows(true)
				end
			end
			if debugShowShadows.unchecked() then
				debugShowShadowsChangeCountState:set(debugShowShadowsChangeCountState:get() + 1)
				if debugShowShadowsChangeCountState:get() > 1 then
					clientShadowManager:setShowShadows(false)
				end
			end
			if Iris.Button({ "Recreate All Shadow Casters" }).clicked() then
				clientShadowManager:recreateAllCasters()
			end
			if Iris.Button({ "Dump Dragon Power" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpDragonPower")
			end
			if Iris.Button({ "Equip All Dragons" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("equipAllDragons")
			end
			if Iris.Button({ "Unequip All Dragons" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("unequipAllDragons")
			end
			if Iris.Button({ "Dump Server Trading State" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpServerTradingState")
			end
			Iris.SeparatorText({ "Coins" })
			if Iris.Button({ "Reset Coins" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetCoins")
			end

			local numCoins = Iris.State(50)
			Iris.InputNum({ [Iris.Args.InputNum.Text] = "", [Iris.Args.InputNum.Format] = "%i" }, { number = numCoins })
			Iris.SameLine()
			if Iris.Button({ "Get Coins" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("getCoins", numCoins:get())
			end
			if Iris.Button({ "Get Gems" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("getGems", numCoins:get())
			end
			if Iris.Button({ "Dump Gems" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpGems")
			end
			Iris.End()

			Iris.SeparatorText({ "Primary Element Affinity" })
			if Iris.Button({ "Reset Affinity Levels and XP" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetPrimaryElementProgress")
			end
			if Iris.Button({ "Reset Purchased Unlocked Slots" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetPurchasedSlotUnlocks")
			end
			Iris.SameLine()
			if Iris.Button({ "Add XP" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("addXp")
			end
			if Iris.Button({ "Add Level" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("addLevel")
			end
			Iris.End()

			Iris.SeparatorText({ "State" })

			Iris.SameLine()
			local saveOnExitState = Iris.State(true)
			local saveOnExitChangeCountState = Iris.State(0)
			if Iris.Button({ "Reset All Items" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetAllItems")
			end
			if Iris.Button({ "Erase Save Data" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("eraseSaveData")
				saveOnExitState:set(false)
			end

			local saveOnExitCheckbox = Iris.Checkbox({ "Save On Exit" }, { isChecked = saveOnExitState })
			if saveOnExitCheckbox.checked() then
				saveOnExitChangeCountState:set(saveOnExitChangeCountState:get() + 1)
				if saveOnExitChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setIfSaveOnExit", true)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end
			if saveOnExitCheckbox.unchecked() then
				RemoteEvents.TryDevTool:FireServer("setIfSaveOnExit", false)
			end
			Iris.End()

			Iris.SameLine()
			Iris.Text({ "Load Save Data" })
			if Iris.Button({ "0" }).clicked() then
				local slot = 0
				RemoteEvents.TryDevTool:FireServer("loadSaveData", slot)
			end
			if Iris.Button({ "1" }).clicked() then
				local slot = 1
				RemoteEvents.TryDevTool:FireServer("loadSaveData", slot)
			end
			if Iris.Button({ "2" }).clicked() then
				local slot = 2
				RemoteEvents.TryDevTool:FireServer("loadSaveData", slot)
			end
			Iris.End()

			Iris.SameLine()
			Iris.Text({ "Save to Slot" })
			if Iris.Button({ "0" }).clicked() then
				local slot = 0
				RemoteEvents.TryDevTool:FireServer("saveData", slot)
			end
			if Iris.Button({ "1" }).clicked() then
				local slot = 1
				RemoteEvents.TryDevTool:FireServer("saveData", slot)
			end
			if Iris.Button({ "2" }).clicked() then
				local slot = 2
				RemoteEvents.TryDevTool:FireServer("saveData", slot)
			end
			Iris.End()

			local loadGlobalName = Iris.InputText({ "", "Global Save Name" })
			if loadGlobalName.Text ~= "" then
				if Iris.Button({ "Load Global" }).clicked() then
					print("should load from", loadGlobalName.text.value)
					RemoteEvents.TryDevTool:FireServer("loadSaveDataGlobal", loadGlobalName.text.value)
				end
			end
			local saveGlobalName = Iris.InputText({ "", "Global Save Name" })
			if saveGlobalName.Text ~= "" then
				if Iris.Button({ "Save Global" }).clicked() then
					print("should save to", saveGlobalName.text.value)
					RemoteEvents.TryDevTool:FireServer("saveDataGlobal", saveGlobalName.text.value)
				end
			end

			Iris.SeparatorText({ "Item Drops" })
			if Iris.Button({ "Add Gem Pile" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("addGemPile")
			end

			-- create stuff

			local cropDataFolder: any = devToolsDataFolder:WaitForChild("Crops")
			local createCropState = Iris.State("")
			Iris.Combo({ "" }, { index = createCropState })
			do
				for _, inst in cropDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createCropState })
				end
			end
			Iris.End()
			Iris.SameLine()
			if Iris.Button({ "Create Crop" }).clicked() then
				local itemName = createCropState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end
			if Iris.Button({ "Create 100 Crops" }).clicked() then
				local itemName = createCropState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItemCount", itemName, 100)
				end
			end
			Iris.End()

			local dragonDataFolder: any = devToolsDataFolder:WaitForChild("Dragons")

			local createDragonState = Iris.State("")
			Iris.Combo({ "" }, { index = createDragonState })
			do
				for _, inst in dragonDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createDragonState })
				end
			end
			Iris.End()
			if Iris.Button({ "Create Dragon" }).clicked() then
				local itemName = createDragonState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end

			local dragonEggDataFolder: any = devToolsDataFolder:WaitForChild("DragonEggs")

			local createDragonEggState = Iris.State("")
			Iris.Combo({ "" }, { index = createDragonEggState })
			do
				for _, inst in dragonEggDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createDragonEggState })
				end
			end
			Iris.End()
			Iris.SameLine()
			if Iris.Button({ "Create Dragon Egg" }).clicked() then
				local itemName = createDragonEggState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end
			if Iris.Button({ "Create 100 Dragon Eggs" }).clicked() then
				local itemName = createDragonEggState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItemCount", itemName, 100)
				end
			end
			Iris.End()

			local crystalDataFolder: any = devToolsDataFolder:WaitForChild("Crystals")

			local createCrystalState = Iris.State("")
			Iris.Combo({ "" }, { index = createCrystalState })
			do
				for _, inst in crystalDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createCrystalState })
				end
			end
			Iris.End()
			Iris.SameLine()
			if Iris.Button({ "Create Crystal" }).clicked() then
				local itemName = createCrystalState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end
			if Iris.Button({ "Create 100 Crystals" }).clicked() then
				local itemName = createCrystalState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItemCount", itemName, 100)
				end
			end
			Iris.End()

			local packDataFolder: any = devToolsDataFolder:WaitForChild("Packs")

			local createPackState = Iris.State("")
			Iris.Combo({ "" }, { index = createPackState })
			do
				for _, inst in packDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createPackState })
				end
			end
			Iris.End()
			if Iris.Button({ "Create Pack" }).clicked() then
				local itemName = createPackState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end

			local keyDataFolder: any = devToolsDataFolder:WaitForChild("Keys")

			local createKeyState = Iris.State("")
			Iris.Combo({ "" }, { index = createKeyState })
			do
				for _, inst in keyDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createKeyState })
				end
			end
			Iris.End()

			Iris.SameLine()
			if Iris.Button({ "Create Key" }).clicked() then
				local itemName = createKeyState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end
			if Iris.Button({ "Create 100 Keys" }).clicked() then
				local itemName = createKeyState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItemCount", itemName, 100)
				end
			end
			Iris.End()

			local blueprintDataFolder: any = devToolsDataFolder:WaitForChild("Blueprints")

			local createBlueprintState = Iris.State("")
			Iris.Combo({ "" }, { index = createBlueprintState })
			do
				for _, inst in blueprintDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = createBlueprintState })
				end
			end
			Iris.End()
			if Iris.Button({ "Create Blueprint" }).clicked() then
				local itemName = createBlueprintState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("createItem", itemName)
				end
			end

			Iris.SeparatorText({ "Index" })
			if Iris.Button({ "Dump Index State" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpIndexState")
			end
			if Iris.Button({ "Reset Index Data" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetIndexData")
			end
			if Iris.Button({ "Reset Mutation Data" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetIndexMutationData")
			end
			if Iris.Button({ "Reset Index Rewards" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetIndexRewards")
			end

			Iris.Text({ "--- Discover Items ---" })

			Iris.Text({ "Category" })
			local discoverIndexCategoryState = Iris.State(indexCatalog.Category.DRAGONS)
			Iris.Combo({ "" }, { index = discoverIndexCategoryState })
			do
				for _, category in indexCatalog.getCategoriesSorted() do
					Iris.Selectable({ category, category }, { index = discoverIndexCategoryState })
				end
			end
			Iris.End()

			if Iris.Button({ "Dump Index Chains" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpIndexChains", discoverIndexCategoryState:get())
			end

			Iris.Text({ "Percent Per Chain" })
			local discoverIndexPercentState = Iris.State(30)
			Iris.InputNum(
				{ [Iris.Args.InputNum.Text] = "", [Iris.Args.InputNum.Format] = "%i" },
				{ number = discoverIndexPercentState }
			)

			if Iris.Button({ "Discover Percent For Category" }).clicked() then
				RemoteEvents.TryDevTool:FireServer(
					"discoverIndexItemsForCategory",
					discoverIndexCategoryState:get(),
					discoverIndexPercentState:get()
				)
			end

			Iris.Text({ "--- Discover Specific Mutation ---" })

			local discoverMutationState = Iris.State(enums.getName(enums.Mutations, enums.Mutations.BRONZE))
			Iris.Combo({ "" }, { index = discoverMutationState })
			do
				for _, mutation in enums.getAllValues(enums.Mutations) do
					if mutation == enums.Mutations.NORMAL then
						continue
					end
					Iris.Selectable(
						{ enums.getName(enums.Mutations, mutation), enums.getName(enums.Mutations, mutation) },
						{ index = discoverMutationState }
					)
				end
			end
			Iris.End()

			if Iris.Button({ "Discover Mutation" }).clicked() then
				local mutation = enums.getValueByName(enums.Mutations, discoverMutationState:get())
				RemoteEvents.TryDevTool:FireServer("discoverSpecificMutation", mutation)
			end

			Iris.Text({ "--- Claim Reward ---" })

			Iris.Text({ "Category" })
			local claimIndexCategoryState = Iris.State(indexCatalog.Category.DRAGONS)
			Iris.Combo({ "" }, { index = claimIndexCategoryState })
			do
				for _, category in indexCatalog.getCategoriesSorted() do
					Iris.Selectable({ category, category }, { index = claimIndexCategoryState })
				end
			end
			Iris.End()

			Iris.Text({ "Scope" })
			local claimIndexScopeState = Iris.State(indexHelpers.Scope.CATEGORY)
			Iris.Combo({ "" }, { index = claimIndexScopeState })
			do
				Iris.Selectable(
					{ indexHelpers.Scope.CATEGORY, indexHelpers.Scope.CATEGORY },
					{ index = claimIndexScopeState }
				)
				Iris.Selectable(
					{ indexHelpers.Scope.CHAIN, indexHelpers.Scope.CHAIN },
					{ index = claimIndexScopeState }
				)
			end
			Iris.End()

			local claimIndexChainKeyState = Iris.State("")
			if claimIndexScopeState:get() == indexHelpers.Scope.CHAIN then
				Iris.Text({ "Chain Key" })
				Iris.Combo({ "" }, { index = claimIndexChainKeyState })
				do
					for _, chainKey in indexCatalog.getCandidateChainKeysForCategory(claimIndexCategoryState:get()) do
						Iris.Selectable({ chainKey, chainKey }, { index = claimIndexChainKeyState })
					end
				end
				Iris.End()
			end

			Iris.Text({ "Tier Index" })
			local claimIndexTierIndexState = Iris.State(1)
			Iris.InputNum(
				{ [Iris.Args.InputNum.Text] = "", [Iris.Args.InputNum.Format] = "%i" },
				{ number = claimIndexTierIndexState }
			)

			if Iris.Button({ "Try Claim Index Reward" }).clicked() then
				local scope = claimIndexScopeState:get()
				local chainKey = scope == indexHelpers.Scope.CHAIN and claimIndexChainKeyState:get() or nil
				RemoteEvents.TryDevTool:FireServer(
					"tryClaimIndexReward",
					claimIndexCategoryState:get(),
					scope,
					chainKey,
					claimIndexTierIndexState:get()
				)
			end
			if Iris.Button({ "Dump Index Milestones" }).clicked() then
				local scope = claimIndexScopeState:get()
				local chainKey = scope == indexHelpers.Scope.CHAIN and claimIndexChainKeyState:get() or nil
				RemoteEvents.TryDevTool:FireServer(
					"dumpIndexMilestones",
					claimIndexCategoryState:get(),
					scope,
					chainKey
				)
			end

			Iris.Text({ "--- Stat Buffs ---" })

			local abilityAttributeNames = Abilities.getAttributeNames()
			local statBuffAttributeState = Iris.State(abilityAttributeNames[1])
			Iris.Combo({ "" }, { index = statBuffAttributeState })
			do
				for _, attributeName in abilityAttributeNames do
					Iris.Selectable({ attributeName, attributeName }, { index = statBuffAttributeState })
				end
			end
			Iris.End()

			local statBuffAmountState = Iris.State(0)
			Iris.InputNum(
				{ [Iris.Args.InputNum.Text] = "", [Iris.Args.InputNum.Format] = "%.4f" },
				{ number = statBuffAmountState }
			)

			if Iris.Button({ "Grant Index Stat Buff" }).clicked() then
				RemoteEvents.TryDevTool:FireServer(
					"grantIndexStatBuff",
					statBuffAttributeState:get(),
					statBuffAmountState:get()
				)
			end

			if Iris.Button({ "Dump Index Stat Buffs" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpIndexStatBuffs")
			end

			Iris.Text({ "--- Mutation Chance ---" })

			local mutationChanceAmountState = Iris.State(0)
			Iris.InputNum(
				{ [Iris.Args.InputNum.Text] = "", [Iris.Args.InputNum.Format] = "%.2f" },
				{ number = mutationChanceAmountState }
			)

			if Iris.Button({ "Grant Index Mutation Chance Buff" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("grantIndexMutationChanceBuff", mutationChanceAmountState:get())
			end

			if Iris.Button({ "Dump Index Mutation Chance Buff" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("dumpIndexMutationChanceBuff")
			end

			Iris.SeparatorText({ "Stores" })
			if Iris.Button({ "Restock Random" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("restockBuyStoreRandom")
			end
			if Iris.Button({ "Reset Starter Offer Progress" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetStarterOfferProgress")
			end
			if Iris.Button({ "Reset Codes Redeemed" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetCodesRedeemed")
			end
			if Iris.Button({ "Reset Vanity Discount" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetVanityDiscount")
			end
			if Iris.Button({ "Reset Prompt Group Time" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetPromptGroupTime")
			end

			Iris.SeparatorText({ "Nodes" })
			if Iris.Button({ "Refill Nodes" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("refillNodes")
			end
			if Iris.Button({ "Restock Islands" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("restockIslands")
			end
			local islandDataFolder: any = devToolsDataFolder:WaitForChild("Islands")
			local restockIslandState = Iris.State("")
			Iris.Combo({ "" }, { index = restockIslandState })
			do
				for _, inst in islandDataFolder:GetChildren() do
					local itemName = inst.Name
					Iris.Selectable({ itemName, itemName }, { index = restockIslandState })
				end
			end
			Iris.End()
			if Iris.Button({ "Restock Fixed Islands" }).clicked() then
				local itemName = restockIslandState:get()
				if itemName ~= "" then
					RemoteEvents.TryDevTool:FireServer("restockFixedIslands", restockIslandState:get())
				end
			end

			local tool = utils.findFirstDescendantOfClass(player.Character :: any, "Tool")
			local helperItemId = nil
			if tool then
				local obj = tool:FindFirstChild("Handle")
				if obj then
					helperItemId = obj:GetAttribute(Attributes.ITEM_ID)
				end
			end
			if clientRideController:isRiding() then
				local ridingObj = clientRideController:getRidingObj()
				helperItemId = ridingObj:GetAttribute(Attributes.ITEM_ID)
			end

			Iris.SeparatorText({ "Client Helpers" })
			if helperItemId then
				if Iris.Button({ "Destroy Item" }).clicked() then
					RemoteEvents.TryDevTool:FireServer("destroyItem", helperItemId)
				end

				local openableCrystalCount = clientCrystalManager:getOpenableCrystalCount()
				if openableCrystalCount > 0 then
					if Iris.Button({ "Activate Crystal" }).clicked() then
						RemoteEvents.TryDevTool:FireServer("activateCrystal")
					end
				else
					Iris.Text({ "Begin activating a crystal to do it instantly here" })
				end

				local setMutationState = Iris.State(enums.getName(enums.Mutations, enums.Mutations.NORMAL))
				Iris.Combo({ "" }, { index = setMutationState })
				do
					local mutations = enums.getAllValues(enums.Mutations)
					for _, mutation in mutations do
						Iris.Selectable(
							{ enums.getName(enums.Mutations, mutation), enums.getName(enums.Mutations, mutation) },
							{ index = setMutationState }
						)
					end
				end
				Iris.End()
				if Iris.Button({ "Set Mutation" }).clicked() then
					local mutationName = setMutationState:get()
					local mutation = enums.getValueByName(enums.Mutations, mutationName)
					RemoteEvents.TryDevTool:FireServer("setMutation", helperItemId, mutation)
				end
				local toggleModificationState = Iris.State("")
				Iris.Combo({ "" }, { index = toggleModificationState })
				do
					local modifications = enums.getAllValues(enums.Modifications)
					for _, modification in modifications do
						Iris.Selectable({
							enums.getName(enums.Modifications, modification),
							enums.getName(enums.Modifications, modification),
						}, { index = toggleModificationState })
					end
				end
				Iris.End()
				if Iris.Button({ "Toggle Modification" }).clicked() then
					local modificationName = toggleModificationState:get()
					local modification = enums.getValueByName(enums.Modifications, modificationName)
					RemoteEvents.TryDevTool:FireServer("toggleModification", helperItemId, modification)
				end
			else
				Iris.Text({ "Equip or Ride an item to edit" })
			end

			local openableCrystalCount = clientCrystalManager:getOpenableCrystalCount()
			if openableCrystalCount > 0 then
				if Iris.Button({ "Activate Crystal" }).clicked() then
					RemoteEvents.TryDevTool:FireServer("activateCrystal")
				end
			else
				Iris.Text({ "Begin activating a crystal to do it instantly here" })
			end

			if Iris.Button({ "Reset Full Player State" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetFullPlayerState")
			end
			if clientRideController:isRiding() then
				if Iris.Button({ "Add Stamina" }).clicked() then
					RemoteEvents.TryDevTool:FireServer("addStamina")
				end
			else
				Iris.Text({ "Ride a dragon to add stamina" })
			end
			if helperItemId then
				if Iris.Button({ "Setup Standard Merge" }).clicked() then
					RemoteEvents.TryDevTool:FireServer("setupStandardMerge", helperItemId)
				end
				if Iris.Button({ "Setup Enhanced Merge" }).clicked() then
					RemoteEvents.TryDevTool:FireServer("setupEnhancedMerge", helperItemId)
				end
			else
				Iris.Text({ "Equip or Ride an item to access merge tools" })
			end

			if Iris.Button({ "Fully Grow Crops" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("fullyGrowCrops")
			end

			if Iris.Button({ "Go To Nearest Island" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("goToIsland")
			end

			local eatFastState = Iris.State(false)
			local eatFastChangeCountState = Iris.State(0)
			local eatFastCheckbox = Iris.Checkbox({ "Eat Fast" }, { isChecked = eatFastState })
			if eatFastCheckbox.checked() then
				eatFastChangeCountState:set(eatFastChangeCountState:get() + 1)
				if eatFastChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setEatFast", true)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end
			if eatFastCheckbox.unchecked() then
				eatFastChangeCountState:set(eatFastChangeCountState:get() + 1)
				if eatFastChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setEatFast", false)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end

			if Iris.Button({ "Erase Save Data" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("eraseSaveData")
				saveOnExitState:set(false)
			end
			Iris.SameLine()
			Iris.Text({ "Go To Plot" })
			for i = 1, 6 do
				if Iris.Button({ tostring(i) }).clicked() then
					RemoteEvents.TryDevTool:FireServer("goToPlot", i)
				end
			end
			Iris.End()

			local weatherDataFolder: any = splendidDataFolder:WaitForChild("Weather")
			local clientWeatherDatas = clientWeatherManager:getClientWeatherDatas()

			Iris.SeparatorText({ "Weather Control" })

			Iris.SameLine()
			for _, inst in weatherDataFolder:GetChildren() do
				local weatherName = inst.Name
				local isWeatherActive = false
				for _, clientWeatherData in clientWeatherDatas do
					if clientWeatherData.name == weatherName then
						isWeatherActive = true
					end
				end
				local weatherCheckbox = Iris.Checkbox({ weatherName }, { isChecked = isWeatherActive })
				if weatherCheckbox.checked() then
					if not clientWeatherManager:isWeatherActive(weatherName) then
						RemoteEvents.TryDevTool:FireServer("activateWeather", weatherName)
					end
				end
				if weatherCheckbox.unchecked() then
					if clientWeatherManager:isWeatherActive(weatherName) then
						RemoteEvents.TryDevTool:FireServer("deactivateWeather", weatherName)
					end
				end
			end
			Iris.End()

			Iris.SeparatorText({ "Element Unlocks" })

			Iris.SameLine()
			for _, primaryElement in enums.getAllValues(enums.PrimaryElements) do
				if primaryElement == enums.PrimaryElements.NONE then
					continue
				end

				local primaryElementName = enums.getPublicName(enums.PrimaryElements, primaryElement)

				local isUnlockedKey = Elements.getIsUnlockedKeyForPrimaryElement(primaryElement)
				local isUnlocked = clientPlayerAttributesManager:get(isUnlockedKey)
				local elementChangeCountState = Iris.State(0)
				local unlockCheckbox = Iris.Checkbox({ primaryElementName }, { isChecked = isUnlocked })
				if unlockCheckbox.checked() then
					elementChangeCountState:set(elementChangeCountState:get() + 1)
					if elementChangeCountState:get() > 1 then
						if not clientPlayerAttributesManager:get(isUnlockedKey) then
							RemoteEvents.TryDevTool:FireServer("unlockPrimaryElement", primaryElement)
						end
					end
				end
				if unlockCheckbox.unchecked() then
					elementChangeCountState:set(elementChangeCountState:get() + 1)
					if elementChangeCountState:get() > 1 then
						if clientPlayerAttributesManager:get(isUnlockedKey) then
							RemoteEvents.TryDevTool:FireServer("lockPrimaryElement", primaryElement)
						end
					end
				end
			end
			Iris.End()

			Iris.SeparatorText({ "FTUE" })

			Iris.SameLine()
			if Iris.Button({ "Restart" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("restartFtueProgress")
			end
			if Iris.Button({ "Clear" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetFtueProgress")
			end
			Iris.End()

			Iris.SeparatorText({ "Contextual FTUE" })

			local triggerContextualFtueState = Iris.State("")
			Iris.Combo({ "" }, { index = triggerContextualFtueState })
			do
				for _, entry in ContextualFtueCatalog.getAllEntries() do
					Iris.Selectable({ entry.title, entry.title }, { index = triggerContextualFtueState })
				end
			end
			Iris.End()
			Iris.SameLine()
			if Iris.Button({ "Trigger" }).clicked() then
				local title = triggerContextualFtueState:get()
				for _, entry in ContextualFtueCatalog.getAllEntries() do
					if entry.title == title then
						RemoteEvents.TryDevTool:FireServer("triggerContextualFtue", entry.id)
						break
					end
				end
			end
			if Iris.Button({ "Clear" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetContextualFtueState")
			end
			Iris.End()

			Iris.SeparatorText({ "First Session Offer" })

			Iris.SameLine()
			if Iris.Button({ "Restart" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("restartFirstSessionOfferState")
			end
			if Iris.Button({ "Set Redeemable" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("setRedeemableFirstSessionOfferState")
			end
			if Iris.Button({ "Clear" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetFirstSessionOfferState")
			end
			Iris.End()

			Iris.SeparatorText({ "Vanity" })
			local vanityDataFolder: any = splendidDataFolder:WaitForChild("Vanity")

			local playerVanityState = Iris.State(enums.PlayerVanityState.LOCKED)
			local playerVanityChangeCountState = Iris.State(0)
			local playerVanityCheckbox = Iris.Checkbox(
				{ "Player Vanity Unlocked" },
				{ isChecked = playerVanityState:get() == enums.PlayerVanityState.UNLOCKED }
			)
			if playerVanityCheckbox.checked() then
				playerVanityChangeCountState:set(playerVanityChangeCountState:get() + 1)
				if playerVanityChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setPlayerVanityState", enums.PlayerVanityState.UNLOCKED)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end
			if playerVanityCheckbox.unchecked() then
				playerVanityChangeCountState:set(playerVanityChangeCountState:get() + 1)
				if playerVanityChangeCountState:get() > 1 then
					RemoteEvents.TryDevTool:FireServer("setPlayerVanityState", enums.PlayerVanityState.LOCKED)
				else
					-- this event gets triggered on startup, so we need to ignore the first one
				end
			end

			local vanityInnerPlotDataFolder: any = vanityDataFolder:FindFirstChild(Constants.VANITY_INNER_PLOT_NAME)

			local setMainPlotInnerLandState = Iris.State("")
			Iris.Combo({ "" }, { index = setMainPlotInnerLandState })
			do
				for _, inst in vanityInnerPlotDataFolder:GetChildren() do
					local vanityComponentName = inst.Name
					Iris.Selectable({ vanityComponentName, vanityComponentName }, { index = setMainPlotInnerLandState })
				end
			end
			Iris.End()
			if Iris.Button({ "Set Main Plot Inner Land" }).clicked() then
				local vanityComponentName = setMainPlotInnerLandState:get()
				if vanityComponentName ~= "" then
					RemoteEvents.TryDevTool:FireServer(
						"setVanityComponentNameAtPlacement",
						enums.VanityPlacements.MAIN_PLOT_INNER,
						vanityComponentName
					)
				end
			end

			local vanityOuterPlotDataFolder: any = vanityDataFolder:FindFirstChild(Constants.VANITY_OUTER_PLOT_NAME)

			local setMainPlotOuterLandState = Iris.State("")
			Iris.Combo({ "" }, { index = setMainPlotOuterLandState })
			do
				for _, inst in vanityOuterPlotDataFolder:GetChildren() do
					local vanityComponentName = inst.Name
					Iris.Selectable({ vanityComponentName, vanityComponentName }, { index = setMainPlotOuterLandState })
				end
			end
			Iris.End()
			if Iris.Button({ "Set Main Plot Outer Land" }).clicked() then
				local vanityComponentName = setMainPlotOuterLandState:get()
				if vanityComponentName ~= "" then
					RemoteEvents.TryDevTool:FireServer(
						"setVanityComponentNameAtPlacement",
						enums.VanityPlacements.MAIN_PLOT_OUTER,
						vanityComponentName
					)
				end
			end

			local vanityFenceDataFolder: any = vanityDataFolder:WaitForChild(Constants.VANITY_FENCE_NAME)

			Iris.Text({ "Set Fence" })
			local setFenceState = Iris.State("")
			Iris.Combo({ "" }, { index = setFenceState })
			do
				for _, inst in vanityFenceDataFolder:GetChildren() do
					local vanityComponentName = inst.Name
					Iris.Selectable({ vanityComponentName, vanityComponentName }, { index = setFenceState })
				end
			end
			Iris.End()

			Iris.SameLine()
			for i = 1, 9 do
				if Iris.Button({ tostring(i) }).clicked() then
					local vanityComponentName = setFenceState:get()
					if vanityComponentName ~= "" then
						RemoteEvents.TryDevTool:FireServer(
							"setVanityComponentNameAtPlacement",
							fenceEnums[i],
							vanityComponentName
						)
					end
				end
			end
			Iris.End()

			local vanityExpansionInnerDataFolder =
				vanityDataFolder:FindFirstChild(Constants.VANITY_EXPANSION_INNER_NAME)

			Iris.Text({ "Set Expansion Inner" })
			local setExpansionInnerState = Iris.State("")
			Iris.Combo({ "" }, { index = setExpansionInnerState })
			do
				for _, inst in vanityExpansionInnerDataFolder:GetChildren() do
					local vanityComponentName = inst.Name
					Iris.Selectable({ vanityComponentName, vanityComponentName }, { index = setExpansionInnerState })
				end
			end
			Iris.End()
			Iris.SameLine()
			for i = 1, 4 do
				if Iris.Button({ tostring(i) }).clicked() then
					local vanityComponentName = setExpansionInnerState:get()
					if vanityComponentName ~= "" then
						RemoteEvents.TryDevTool:FireServer(
							"setVanityComponentNameAtPlacement",
							expansionInnerEnums[i],
							vanityComponentName
						)
					end
				end
			end
			Iris.End()

			local vanityExpansionOuterDataFolder =
				vanityDataFolder:FindFirstChild(Constants.VANITY_EXPANSION_OUTER_NAME)

			Iris.Text({ "Set Expansion Outer" })
			local setExpansionOuterState = Iris.State("")
			Iris.Combo({ "" }, { index = setExpansionOuterState })
			do
				for _, inst in vanityExpansionOuterDataFolder:GetChildren() do
					local vanityComponentName = inst.Name
					Iris.Selectable({ vanityComponentName, vanityComponentName }, { index = setExpansionOuterState })
				end
			end
			Iris.End()
			Iris.SameLine()
			for i = 1, 4 do
				if Iris.Button({ tostring(i) }).clicked() then
					local vanityComponentName = setExpansionOuterState:get()
					if vanityComponentName ~= "" then
						RemoteEvents.TryDevTool:FireServer(
							"setVanityComponentNameAtPlacement",
							expansionOuterEnums[i],
							vanityComponentName
						)
					end
				end
			end
			Iris.End()

			if Iris.Button({ "Reset All Vanity" }).clicked() then
				RemoteEvents.TryDevTool:FireServer("resetAllVanity")
			end

			if Iris.Button({ "Test New Blueprint Fanfare" }).clicked() then
				clientNewBlueprintManager:notifyNewBlueprint("nothing, this is a test", enums.Rarity.RARE)
			end

			Iris.SeparatorText({ "Item Screenshot" })

			local screenshotViewportCheckbox = Iris.Checkbox(
				{ "Enable Viewport" },
				{ isChecked = screenshotViewportEnabledState }
			)
			if screenshotViewportCheckbox.unchecked() then
				clearScreenshotPreview()
			end
			screenshotViewport.Visible = screenshotViewportEnabledState:get()

			Iris.Text({ "Category" })
			Iris.Combo({ "" }, { index = screenshotCategoryState })
			do
				for _, category in SCREENSHOT_CATEGORIES do
					Iris.Selectable({ category, category }, { index = screenshotCategoryState })
				end
			end
			Iris.End()

			local screenshotCategory = screenshotCategoryState:get()
			if screenshotCategory ~= lastScreenshotCategory then
				screenshotItemState:set("")
				lastScreenshotCategory = screenshotCategory
			end

			Iris.Text({ "Item" })
			Iris.Combo({ "" }, { index = screenshotItemState })
			do
				if screenshotCategory ~= "" then
					for _, inst in devToolsDataFolder:WaitForChild(screenshotCategory):GetChildren() do
						Iris.Selectable({ inst.Name, inst.Name }, { index = screenshotItemState })
					end
				end
			end
			Iris.End()

			updateScreenshotCameraFraming()

			Iris.SameLine()
			if Iris.Button({ "Spawn Item" }).clicked() then
				local itemName = screenshotItemState:get()
				if screenshotCategory ~= "" and itemName ~= "" then
					local itemInst = devToolsDataFolder:WaitForChild(screenshotCategory):FindFirstChild(itemName)
					local templatePath = itemInst
						and (
							itemInst:GetAttribute(Attributes.CASTER_PATH)
							or itemInst:GetAttribute(Attributes.TEMPLATE_PATH)
						)
					local cameraPosition = itemInst and itemInst:GetAttribute(Attributes.SCREENSHOT_CAMERA_POSITION)
					if templatePath then
						spawnScreenshotItem(templatePath, cameraPosition, screenshotCategory)
					end
				end
			end
			if Iris.Button({ "Remove Item" }).clicked() then
				clearScreenshotPreview()
			end
			Iris.End()

			Iris.SameLine()
			if Iris.Button({ "Rotate Clockwise" }).clicked() then
				rotateScreenshotItem(-1)
			end
			if Iris.Button({ "Rotate Counter-Clockwise" }).clicked() then
				rotateScreenshotItem(1)
			end
			Iris.End()

			if Iris.Button({ "Take Screenshot" }).clicked() then
				showDevWindow:set(false)
			end
		end

		Iris.End()

		Iris.Window({ "Customer Service" }, {
			size = Iris.State(Vector2.new(800, 450)),
			position = Iris.State(Vector2.new(200, 50)),
			isOpened = showCustomerWindow,
		})
		clientCustomerTools:renderIris()

		Iris.Window({ "Netops" }, {
			size = Iris.State(Vector2.new(800, 450)),
			position = Iris.State(Vector2.new(200, 50)),
			isOpened = showNetopsWindow,
		})
		clientNetopsTools:renderIris(showNetopsWindow)
	end)
end

function ClientDevTools.new(): ClientDevTools
	local self = setmetatable({} :: ClientDevToolsFields, ClientDevTools)

	self.state = {
		windowSize = Iris.State(Vector2.new(350, 400)),
		windowPosition = Iris.State(Vector2.new(0, 200)),

		debugUseBillboardsState = Iris.State(false),
		debugUseBillboardsChangeCountState = Iris.State(0),

		debugUseCastersOtherPlayersState = Iris.State(true),
		debugShowShadowsState = Iris.State(false),
	}
	return self
end

function ClientDevTools.initClass(deps: any)
	clientDragonManager = deps.clientDragonManager
end

local singleton = ClientDevTools.new()

return singleton
