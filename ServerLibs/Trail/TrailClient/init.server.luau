--!strict

-- Dependencies
local trailRemote = script:WaitForChild("Remote", 5.0) :: RemoteEvent?
assert(trailRemote, "TrailClient.Remote not found")

-- Services
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")
local Players           = game:GetService("Players")
local VRService         = game:GetService("VRService")
local TextService       = game:GetService("TextService")
local Stats             = game:GetService("Stats")

local GameSettings = UserSettings().GameSettings

-- Types
type meta = {
	sa: string,
	sb: string,
	sc: string,
	sd: string,
	se: string,
	sf: string,
	sg: string,
	sh: string,
	si: string,
	sj: string,
	sk: string,
	na: number,
	nb: number,
	nc: number,
	ne: number,
	nf: number,
	ng: number,
	ba: boolean,
	bb: boolean,
	bc: boolean,
}

type heartbeat = {
	na: number,
	nb: number,
	nc: number,
}

-- Utility methods
local function getPlatform(): (Enum.DeviceForm?, Enum.Platform?)
	local function getCharSize(codepoint: number): Vector2
		return TextService:GetTextSize(utf8.char(codepoint), 16, Enum.Font.SourceSans, Vector2.new(1000, 1000))
	end

	local _invalidSize = getCharSize(0xFFFF)

	local isWindowsSuccess, isWindowsResult = pcall(function() return (GuiService::any).IsWindows end)

	local ver = version()

	local isWindows = isWindowsSuccess and isWindowsResult
	local isApple   = getCharSize(0xF8FF) ~= _invalidSize
	local isDesktop = ver:find("^0%.") ~= nil
	local isConsole = GuiService:IsTenFootInterface() or ver:find("^1%.") ~= nil
	local isMobile  = ver:find("^2%.") ~= nil or UserInputService.GyroscopeEnabled or UserInputService.AccelerometerEnabled
	local isVR      = UserInputService.VREnabled and VRService.VREnabled
	local isTouch   = UserInputService.TouchEnabled

	local imageSelect = string.lower(UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonSelect))
	local imageL2     = string.lower(UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonL2))

	if     isVR                                   then return Enum.DeviceForm.VR,      Enum.Platform.MetaOS
	elseif isConsole and imageSelect:find("xbox") then return Enum.DeviceForm.Console, Enum.Platform.XBoxOne
	elseif isConsole and imageSelect:find("ps5")  then return Enum.DeviceForm.Console, Enum.Platform.PS5
	elseif isConsole and imageSelect:find("ps4")  then return Enum.DeviceForm.Console, Enum.Platform.PS4
	elseif isConsole and isWindows                then return Enum.DeviceForm.Console, Enum.Platform.XBoxOne
	elseif isConsole and imageL2:find("xbox")     then return Enum.DeviceForm.Console, Enum.Platform.XBoxOne
	elseif isConsole and imageL2:find("ps")       then return Enum.DeviceForm.Console, Enum.Platform.PS4
	elseif isMobile and isWindows                 then return Enum.DeviceForm.Phone,   Enum.Platform.UWP
	elseif isMobile and isApple                   then return Enum.DeviceForm.Phone,   Enum.Platform.IOS
	elseif isMobile and not isTouch               then return Enum.DeviceForm.Phone,   Enum.Platform.Linux
	elseif isMobile                               then return Enum.DeviceForm.Phone,   Enum.Platform.Android
	elseif isWindows                              then return Enum.DeviceForm.Desktop, Enum.Platform.Windows
	elseif isDesktop                              then return Enum.DeviceForm.Desktop, Enum.Platform.OSX
	elseif isApple                                then return Enum.DeviceForm.Phone,   Enum.Platform.IOS
	elseif not isTouch                            then return Enum.DeviceForm.Desktop, Enum.Platform.Linux
	end

	return nil,nil
end

local function getArchitecture(): number
	local addr = tonumber(string.sub(tostring({}), 8))
	return if #tostring(addr) <= 10 then 32 else 64
end

local function getDeviceX(): number
	local success, result = pcall(function() return workspace.CurrentCamera.ViewportSize.X end)
	return if success then math.round(result) else 0
end

local function getDeviceY(): number
	local success, result = pcall(function() return workspace.CurrentCamera.ViewportSize.Y end)
	return if success then math.round(result) else 0
end

local function sendMeta()
	local device, platform = getPlatform()
	local device_x = getDeviceX()
	local device_y = getDeviceY()

	if device == Enum.DeviceForm.Phone and math.max(device_x, device_y) / math.min(device_x, device_y) < 1.6 then
		device = Enum.DeviceForm.Tablet
	end

	local meta: meta = {
		sa = os.date("%z") :: string,
		sb = if platform then string.lower(platform.Name) else "unknown",
		sc = if device then string.lower(device.Name) else "unknown",
		sd = string.lower(GameSettings.ComputerCameraMovementMode.Name),
		se = string.lower(GameSettings.ComputerMovementMode.Name),
		sf = string.lower(GameSettings.RotationType.Name),
		sg = string.lower(GameSettings.SavedQualityLevel.Name),
		sh = string.lower(GameSettings.TouchCameraMovementMode.Name),
		si = string.lower(GameSettings.TouchMovementMode.Name),
		sj = string.lower(GuiService.ViewportDisplaySize.Name),
		sk = string.lower(UserInputService.PreferredInput.Name),

		na = getArchitecture(),
		nb = device_x,
		nc = device_y,
		ne = math.round(100 * GameSettings.GamepadCameraSensitivity),
		nf = math.round(100 * GameSettings.MouseSensitivity),
		ng = GameSettings:GetCameraYInvertValue(),

		ba = (os.date("*t")::any).isdst :: boolean,
		bb = GuiService.TouchControlsEnabled,
		bc = GameSettings:InFullScreen()
	}

	trailRemote:FireServer("client.meta", meta)
end

local function sendHeartbeat()
	local heartbeats = 0

	while Players.LocalPlayer do
		local frameTime = Stats.FrameTime
		local fps = if frameTime > 0 then math.min(math.round(1 / frameTime), 1000) else 0

		local heartbeat: heartbeat = {
			na = fps,
			nb = math.round(Stats.DataReceiveKbps),
			nc = math.round(Stats.DataSendKbps),
		}

		trailRemote:FireServer("client.heartbeat", heartbeat)

		heartbeats += 1

		if heartbeats <= 5 then
			task.wait(2.0)
		elseif heartbeats <= 10 then
			task.wait(4.0)
		else
			task.wait(6.0)
		end
	end
end

GuiService.MenuOpened:Connect(function() trailRemote:FireServer("client.menu.opened") end)
GuiService.MenuClosed:Connect(function() trailRemote:FireServer("client.menu.closed") end)

task.defer(sendMeta)
task.defer(sendHeartbeat)