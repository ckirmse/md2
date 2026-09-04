-- src/main.server.lua

local changeHistoryService = game:GetService("ChangeHistoryService")

local Iris = require(script.Packages.iris)

local selectedNode = Iris.State(nil)
local fieldList = Iris.State({})
local selectedField = Iris.State(nil)
local valueList = Iris.State({})
local selectedValueEntry = Iris.State(nil)

local function renderNode(instance)
	if instance:IsA("Folder") then
		local tree = Iris.Tree({instance.Name})
		if tree.collapsed() or tree.uncollapsed() then
			selectedNode:set(instance)
			fieldList:set({})
			selectedField:set(nil)
			valueList:set({})
			selectedValueEntry:set(nil)
		end
		for _, child in instance:GetChildren() do
			renderNode(child)
		end
		Iris.End()
	else
		local selectable = Iris.Selectable({instance.Name, instance}, {index = selectedNode})
		if selectable.selected() then
			fieldList:set({})
			selectedField:set(nil)
			valueList:set({})
			selectedValueEntry:set(nil)
		end
	end
end

local function getFieldSets()
	local node = selectedNode:get()
	if not node then
		print("[Fields] No node selected.")
		return nil
	end
	local fieldSets = {}
	for _, descendant in node:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end

		local isSuccess, result = pcall(require, descendant)
		if isSuccess and type(result) == "table" then
			local keys = {}
			for key in result do
				keys[key] = true
			end
			table.insert(fieldSets, {name = descendant:GetFullName(), keys = keys})
		elseif not isSuccess then
			print("[Fields] ERROR: " .. descendant:GetFullName() .. " -- " .. tostring(result))
		end
	end
	return fieldSets
end

local function showSharedFields()
	local fieldSets = getFieldSets()
	if not fieldSets or #fieldSets == 0 then
		print("[SharedFields] No modules found.")
		return
	end
	local shared = {}
	for key in fieldSets[1].keys do
		shared[key] = true
	end
	for i = 2, #fieldSets do
		for key in shared do
			if not fieldSets[i].keys[key] then
				shared[key] = nil
			end
		end
	end
	local list = {}
	for key in shared do
		table.insert(list, tostring(key))
	end
	table.sort(list)
	fieldList:set(list)
	selectedField:set(nil)
	valueList:set({})
	selectedValueEntry:set(nil)
end

local function showAllFields()
	local fieldSets = getFieldSets()
	if not fieldSets or #fieldSets == 0 then
		print("[AllFields] No modules found.")
		return
	end
	local union = {}
	for _, fs in fieldSets do
		for key in fs.keys do
			union[key] = true
		end
	end
	local list = {}
	for key in union do
		table.insert(list, tostring(key))
	end
	table.sort(list)
	fieldList:set(list)
	selectedField:set(nil)
	valueList:set({})
	selectedValueEntry:set(nil)
end

local function showValue()
	local node = selectedNode:get()
	local field = selectedField:get()
	if not node or not field then
		return
	end
	local entries = {}
	for _, descendant in node:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end
		local isSuccess, result = pcall(require, descendant)
		if isSuccess and type(result) == "table" then
			local value = result[field]
			table.insert(entries, descendant:GetFullName() .. " | " .. field .. " = " .. tostring(value))
		end
	end
	valueList:set(entries)
	selectedValueEntry:set(nil)
end

local function validate()
	local countChecked = 0
	local countSucceeded = 0
	local node = selectedNode:get()
	if node then
		print("[Validate] Checking scripts under: " .. node:GetFullName())
		for _, descendant in node:GetDescendants() do
			if descendant:IsA("ModuleScript") then
				local isSuccess, err = pcall(require, descendant)
				if isSuccess then
					--print("[Validate] OK: " .. descendant:GetFullName())
					countSucceeded += 1
				else
					print("[Validate] ERROR: " .. descendant:GetFullName() .. " -- " .. tostring(err))
				end
				countChecked += 1
			end
		end
	end
	print(string.format("[Validate] %i/%i succeeded", countSucceeded, countChecked))
end

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, true, false, 300, 400, 200, 200)

local pluginGui = plugin:CreateDockWidgetPluginGui("mdPluginPanel", widgetInfo)
pluginGui.Title = "Marge Dargons Plugin"

Iris.UpdateGlobalConfig({UseScreenGUIs = false})
Iris.Init(pluginGui)

local windowSize = Iris.State(pluginGui.AbsoluteSize)
local windowPos = Iris.State(Vector2.new(0, 0))

pluginGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(
	function()
		windowSize:set(pluginGui.AbsoluteSize)
	end
)

Iris:Connect(
	function()
		-- NoTitleBar=true, NoClose=true, NoMove=true, NoResize=true
		Iris.Window({"Plugin Tools", true, false, false, true, true, false, true}, {
			size = windowSize,
			position = windowPos,
		})

		local gameData = game:GetService("ServerScriptService"):FindFirstChild("GameData")
		if gameData then
			renderNode(gameData)
		else
			Iris.Text({"GameData not found"})
		end

		if Iris.Button({"Validate"}).clicked() then
			validate()
		end

		if Iris.Button({"Show Shared Fields"}).clicked() then
			showSharedFields()
		end
		if Iris.Button({"Show All Fields"}).clicked() then
			showAllFields()
		end

		local currentFieldList = fieldList:get()
		if #currentFieldList > 0 then
			Iris.Separator()
			for _, fieldName in currentFieldList do
				local fieldSelectable = Iris.Selectable({fieldName, fieldName}, {index = selectedField})
				if fieldSelectable.selected() then
					valueList:set({})
					selectedValueEntry:set(nil)
				end
			end
			if Iris.Button({"Show Value"}).clicked() then
				showValue()
			end
		end

		local currentValueList = valueList:get()
		if #currentValueList > 0 then
			Iris.Separator()
			for _, entry in currentValueList do
				Iris.Selectable({entry, entry}, {index = selectedValueEntry})
			end
		end

		-- show single field in selected tree
		-- remove field from selected tree

		Iris.End()
	end
)

local toolbar = plugin:CreateToolbar("External Tools")
local button = toolbar:CreateButton("Marge Dargons", "Tooltip description", "rbxassetid://4458901886")

button.Click:Connect(
	function()
		pluginGui.Enabled = not pluginGui.Enabled
	end
)
