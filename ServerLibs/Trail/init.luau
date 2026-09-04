--!strict
--!native
--!optimize 2

-- CONFIGURATION --
local API_URL = "https://trail.offpath.gg/event"

local SLOT_SIZE           = math.clamp(tonumber(script:GetAttribute("SlotSize")) or 1500, 100, 100_000)
local SLOT_COUNT          = 20
local QUEUE_HIGH_LIMIT    = SLOT_SIZE * SLOT_COUNT
local QUEUE_MED_LIMIT     = SLOT_SIZE * 15
local QUEUE_LOW_LIMIT     = SLOT_SIZE * 10

local MIN_SEND_INTERVAL   = math.clamp(tonumber(script:GetAttribute("SendIntervalMin")) or 0.75, 0.5, 10.0)
local MAX_SEND_INTERVAL   = math.clamp(tonumber(script:GetAttribute("SendIntervalMax")) or 5.00, 0.5, 10.0)
local MAX_SEND_ATTEMPTS   = math.clamp(tonumber(script:GetAttribute("SendAttemptsMax")) or 3, 1, 10)
local EXPONENTIAL_BACKOFF = math.clamp(tonumber(script:GetAttribute("ExponentialBackoff")) or 1.5, 1.0, 5.0)

local EVENT_PRIORITIES = {
	["player.join"]            = 1,
	["player.meta"]            = 1,
	["player.plus"]            = 1,
	["player.leave"]           = 1,
	["player.teleport"]        = 1,
	["purchase.receipt"]       = 1,
	["server.start"]		   = 1,
	["server.stop"]            = 1,

	["player.spawn"]           = 2,
	["player.despawn"]         = 2,
	["purchase.asset"]         = 2,
	["purchase.gamepass"]      = 2,
	["purchase.devproduct"]    = 2,
	["purchase.subscription"]  = 2,
	["purchase.plus"]          = 2,
	["client.meta"]            = 2,

	["client.menu.opened"]     = 3,
	["client.menu.closed"]     = 3,
	["player.chat"]            = 3,
	["server.heartbeat"]       = 3,
	["client.heartbeat"]       = 3,
}

-- SERVICES --
local LocalizationService = game:GetService("LocalizationService")
local MarketplaceService = game:GetService("MarketplaceService")
local VoiceChatService = game:GetService("VoiceChatService")
local AnalyticsService = game:GetService("AnalyticsService")
local TextChatService = game:GetService("TextChatService")
local PolicyService = game:GetService("PolicyService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

-- TYPES --
type dictionary = {[string]: any}
type event = string | {string}
type vector3table = {x: number, y: number, z: number}
type HttpMethod = ("CONNECT" | "DELETE" | "GET" | "HEAD" | "OPTIONS" | "PATCH" | "POST" | "PUT" | "TRACE")

type playerData = {
	toPlaceId: number?,
	spawnAt: number?,
	joinAt: number,
	spawns: number,
	characterAdded: RBXScriptConnection,
	characterRemoving: RBXScriptConnection,
	onTeleport: RBXScriptConnection,
	onChat: RBXScriptConnection,
	onRobloxSubscription: RBXScriptConnection,
	lastClientRemote: number,
	clientRemoteCount: number
}

type payload = {
	seq: number,
	at: number,
	event: string,
	data: dictionary,
	user: number?,
	pos: vector3table?,
	ping: number?
}

type receiptFunction = (dictionary) -> Enum.ProductPurchaseDecision

export type Trail = {
	-- Instance methods
	Event: (self: Trail, event: event, data: dictionary?, player: (Player | number)?, at:number?) -> boolean,
	PlayerEvent: (self: Trail, player: Player, event: event, data: dictionary?, at:number?) -> boolean,
	ReceiptEvent: (self: Trail, receiptInfo: dictionary, result: Enum.ProductPurchaseDecision, extra: dictionary?) -> boolean,

	-- Class methods
	GetPlayerPosition: (player: Player) -> Vector3?,
	ProcessReceiptProxy: (fn: receiptFunction) -> receiptFunction,
	FormatVector3: (v: Vector3?) -> vector3table,
	Start: () -> boolean,
}

-- MODULE --
local Trail = {}

-- PRIVATE VARIABLES --

local trailClientScript = script:FindFirstChild("TrailClient") :: Script?
local trailClientRemote = trailClientScript and trailClientScript:FindFirstChild("Remote") :: RemoteEvent?

if not (trailClientScript and trailClientScript:IsA("Script") and trailClientScript.RunContext == Enum.RunContext.Client) then
	warn("Trail.TrailClient is missing or not a client script")
	trailClientScript = nil
end

if trailClientScript and not (trailClientRemote and trailClientRemote:IsA("RemoteEvent")) then
	warn("Trail.TrailClient.Remote is missing")
	trailClientRemote = nil
	trailClientScript = nil
end

local playerData: {[Player]: playerData} = {}
local eventBuffer: {{string}} = {}
local writeSlot = 1
local readSlot = 1
local timeSinceLastFlush = 0
local timeSinceLastServerHeartbeat = math.huge
local sendsInProgress = 0
local isStarted = false
local isStudio = RunService:IsStudio()
local sequenceId = 1
local warnedAboutPosition = false

local headers: {[string]: Secret | string} = {
	["content-type"] = "application/json",
	["x-trail-key"]  = "",
	["x-game-id"]    = tostring(game.GameId),
	["x-place-id"]   = tostring(game.PlaceId),
	["x-place-ver"]  = tostring(game.PlaceVersion),
	["x-job-id"]     = tostring(game.JobId),
}

-- UTILITY FUNCTIONS --
local function try<T>(default: T, fn: any, ...: any): T
	local ok, result = pcall(fn, ...)
	return if ok and result ~= nil then result else default
end

local function enumName(v: any): string?
	return if typeof(v) == "EnumItem" then v.Name else nil
end

local function getServerInfo(): (string, string?, number?)
	if game.PrivateServerId == "" then return "Standard", nil, nil end
	return if game.PrivateServerOwnerId ~= 0 then "VIP" else "Reserved", game.PrivateServerId, game.PrivateServerOwnerId
end

local function getSafeSecret(key : string): Secret?
	local success, secret = pcall(HttpService.GetSecret, HttpService, key)
	return if success and typeof(secret) == "Secret" then secret else nil
end

local function validateString(input: string?): boolean
	if typeof(input) == "string" then
		local utf8len = utf8.len(input)
		return utf8len ~= nil and utf8len <= 50
	else
		return false
	end
end

local function validateNumber(input: number?): boolean
	if typeof(input) == "number" then
		return math.abs(input) < math.huge
	else
		return false
	end
end

local function utf8sub(str: string, i: number, j: number): string
	local startByte = utf8.offset(str, i)
	local endByte = utf8.offset(str, j + 1)

	if not startByte then return "" end
	if endByte then
		return string.sub(str, startByte, endByte - 1)
	end

	return string.sub(str, startByte)
end

-- Round a number to 1 decimal place
local function roundNumber(num: number): number
	return math.floor(num * 10 + 0.5) / 10
end

-- Given a Vector3, return a table with the x, y, and z values rounded to 1 decimal place
local function _vectorToTable(vector: Vector3): vector3table
	return {
		x = roundNumber(vector.X),
		y = roundNumber(vector.Y),
		z = roundNumber(vector.Z),
	}
end

local function pcallExternalPosition(fn: (...any) -> ...any, ...: any): (boolean, any)
	local ok: boolean = false
	local result: any = nil

	local thread = task.spawn(function(...)
		ok, result = pcall(fn, ...)
	end, ...)

	if coroutine.status(thread) ~= "dead" then
		task.cancel(thread)
		return false, "function yielded"
	end

	return ok, result
end

local function getPlayerPositionFromCharacter(player: Player): Vector3?
	return player.Character and player.Character:GetPivot().Position
end

local function getPlayerPosition(player: Player): vector3table?
	if type(Trail.GetPlayerPosition) ~= "function" then
		warn("Trail.GetPlayerPosition is not a function, cannot get player position")
		return nil
	end

	local ok: boolean
	local result: any

	-- ensure user-provided position function is wrapped and does not yield
	if Trail.GetPlayerPosition ~= getPlayerPositionFromCharacter then
		ok, result = pcallExternalPosition(Trail.GetPlayerPosition, player)
	else
		ok, result = pcall(Trail.GetPlayerPosition, player)
	end

	if ok and typeof(result) == "Vector3" then
		return _vectorToTable(result)
	end

	if not ok and not warnedAboutPosition and result == "function yielded" then
		warn("Trail.GetPlayerPosition yielded")
		warnedAboutPosition = true
	end

	return nil
end

-- Given a table, determine if it's likely a list
local function isList(t: {[any]: any}): boolean
	return #t > 0
end

local function getBufferSize(): number
	return SLOT_SIZE * ((writeSlot - readSlot + SLOT_COUNT) % SLOT_COUNT) + #eventBuffer[writeSlot]
end

local function incrementSlot(slotId: number): number
	return (slotId % SLOT_COUNT) + 1
end

-- Send a batch of events
local function sendQueue(body: string)
	for attempt = 1, MAX_SEND_ATTEMPTS do
		local ok, result = pcall(HttpService.RequestAsync, HttpService, {
			Url      = API_URL,
			Method   = "POST",
			Headers  = headers,
			Body     = body,
			Compress = Enum.HttpCompression.Gzip,
		} :: any)

		if ok and result.Success then break end

		if ok and result.StatusCode == 401 then
			warn("Trail.sendQueue: Unauthorized, check your TrailKey")
			break
		elseif attempt == MAX_SEND_ATTEMPTS then
			warn(`Trail.sendQueue: Failed to send events: {if ok then `[{result.StatusCode}] {result.StatusMessage}` else result}`)
		else
			task.wait(EXPONENTIAL_BACKOFF ^ attempt + math.random())
		end
	end

	sendsInProgress -= 1
end

local function flushSlot()
	local slot = eventBuffer[readSlot]

	if #slot == 0 then
		if readSlot ~= writeSlot then
			readSlot = incrementSlot(readSlot)
		end
		return
	end

	timeSinceLastFlush = 0

	local body = "[" .. table.concat(slot, ",") .. "]"
	table.clear(slot)
	sendsInProgress += 1
	task.defer(sendQueue, body)

	if readSlot == writeSlot then
		writeSlot = incrementSlot(writeSlot)
	end

	readSlot = incrementSlot(readSlot)
end

local function characterAdded(player: Player, character: Model)
	local pData = playerData[player]

	if pData then
		pData.spawns += 1
		pData.spawnAt = DateTime.now().UnixTimestampMillis

		Trail:PlayerEvent(player, "player.spawn")
	end
end

local function characterRemoving(player: Player, character: Model)
	local pData = playerData[player]

	if pData then
		Trail:PlayerEvent(player, "player.despawn")
	end
end

local function onChat(player: Player, message: string, recipient: Player?)
	if typeof(message) == "string" and utf8.len(message) ~= nil then
		Trail:PlayerEvent(player, "player.chat", {message = utf8sub(message, 1, 200)})
	end
end

local function onTeleport(player: Player, teleportState: Enum.TeleportState, placeId: number, spawnName: string)
	local pData = playerData[player]

	if pData and teleportState == Enum.TeleportState.RequestedFromServer then
		pData.toPlaceId = placeId

		Trail:PlayerEvent(player, "player.teleport", {toPlaceId = placeId})
	end
end

local function onClientRemote(player: Player, eventName: string, data: dictionary?)
	local pData = playerData[player]

	if pData then
		local now = DateTime.now().UnixTimestamp

		if now == pData.lastClientRemote and pData.clientRemoteCount > 5 then
			return
		elseif now > pData.lastClientRemote then
			pData.lastClientRemote = now
			pData.clientRemoteCount = 1
		else
			pData.clientRemoteCount += 1
		end

		if eventName == "client.meta" and typeof(data) == "table" and
			validateString(data.sa) and
			validateString(data.sb) and
			validateString(data.sc) and
			validateString(data.sd) and
			validateString(data.se) and
			validateString(data.sf) and
			validateString(data.sg) and
			validateString(data.sh) and
			validateString(data.si) and
			validateString(data.sj) and
			validateString(data.sk) and
			validateNumber(data.na) and
			validateNumber(data.nb) and
			validateNumber(data.nc) and
			validateNumber(data.ne) and
			validateNumber(data.nf) and
			validateNumber(data.ng) and
			typeof(data.ba) == "boolean" and
			typeof(data.bb) == "boolean" and
			typeof(data.bc) == "boolean"
		then
			Trail:PlayerEvent(player, eventName, {
				timezone         = data.sa,
				platform         = data.sb,
				device           = data.sc,
				pcCamMovement    = data.sd,
				pcMovement       = data.se,
				rotationType     = data.sf,
				qualityLevel     = data.sg,
				touchCamMovement = data.sh,
				touchMovement    = data.si,
				viewport         = data.sj,
				preferredInput   = data.sk,
				arch             = data.na,
				screenX          = data.nb,
				screenY          = data.nc,
				gamepadSens      = data.ne,
				mouseSens        = data.nf,
				invertY          = data.ng,
				isDst            = data.ba,
				isTouch          = data.bb,
				isFullscreen     = data.bc
			})

		elseif eventName == "client.heartbeat" and typeof(data) == "table" and
			validateNumber(data.na) and
			validateNumber(data.nb) and
			validateNumber(data.nc)
		then
			Trail:PlayerEvent(player, eventName, {
				fps = data.na,
				dataIn = data.nb,
				dataOut = data.nc
			})

		elseif eventName == "client.menu.opened" then
			Trail:PlayerEvent(player, eventName)

		elseif eventName == "client.menu.closed" then
			Trail:PlayerEvent(player, eventName)

		end
	end
end

-- Purchase tracking functions
local function onProductPurchaseFinished(userId: number, productId: number, isPurchased: boolean)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Trail:PlayerEvent(player, "purchase.devproduct", {productId = productId, isPurchased = isPurchased})
	end
end

local function onGamePassPurchaseFinished(player: Instance, gamePassId: number, isPurchased: boolean)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Trail:PlayerEvent(player, "purchase.gamepass", {productId = gamePassId, isPurchased = isPurchased})
	end
end

local function onPurchaseFinished(player: Instance, assetId: number, isPurchased: boolean)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Trail:PlayerEvent(player, "purchase.asset", {productId = assetId, isPurchased = isPurchased})
	end
end

local function onSubscriptionPurchaseFinished(player: Instance, subscriptionId: string, isPurchased: boolean)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Trail:PlayerEvent(player, "purchase.subscription", {productId = subscriptionId, isPurchased = isPurchased})
	end
end

local function onRobloxSubscriptionPurchaseFinished(player: Instance, isPurchased: boolean)
	if typeof(player) == "Instance" and player:IsA("Player") then
		Trail:PlayerEvent(player, "purchase.plus", {isPurchased = isPurchased})
	end
end

local function onRobloxSubscriptionChanged(player: Player)
	Trail:PlayerEvent(player, "player.plus", {hasPlus = player.HasRobloxSubscription})
end

-- Additional metadata that yields
local function onPlayerMeta(player: Player)
	local countryCode    = try("XX", LocalizationService.GetCountryRegionForPlayerAsync, LocalizationService, player)
	local policy         = try({}, PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player) :: dictionary
	local segments       = try({}, AnalyticsService.GetPlayerSegmentsAsync, AnalyticsService, player) :: dictionary
	local isChatAllowed  = try(false, TextChatService.CanUserChatAsync, TextChatService, player.UserId)
	local isVoiceEnabled = try(false, VoiceChatService.IsVoiceEnabledForUserIdAsync, VoiceChatService, player.UserId)
	local isInGroup      = if game.CreatorType == Enum.CreatorType.Group then try(false, player.IsInGroupAsync, player, game.CreatorId) else false

	Trail:PlayerEvent(player, "player.meta", {
		country                = countryCode,
		isVoiceEnabled         = isVoiceEnabled,
		isInGroup              = isInGroup,
		isChatAllowed          = isChatAllowed,
		policyAds              = policy.AreAdsAllowed,
		policyPaidRng          = policy.ArePaidRandomItemsRestricted,
		policySharing          = policy.IsContentSharingAllowed,
		policyCommerce         = policy.IsEligibleToPurchaseCommerceProduct,
		policySubscription     = policy.IsEligibleToPurchaseSubscription,
		policyTrading          = policy.IsPaidItemTradingAllowed,
		policyPhotoAvatar      = policy.IsPhotoToAvatarAllowed,
		policyChina            = policy.IsSubjectToChinaPolicies,
		policyEndlessContent   = policy.IsEndlessContentLoadAllowed,
		policyEndlessAutoplay  = policy.IsEndlessContentAutoplayAllowed,
		segmentActivePayer     = enumName(segments.ActivePayerStatus),
		segmentWhenFirstPlayed = enumName(segments.WhenUserFirstPlayed),
		segmentPlatformSpender = enumName(segments.PlatformSpenderStatus)
	})
end

local function onPlayerAdded(player: Player)
	if playerData[player] then return end

	local at = DateTime.now().UnixTimestampMillis

	playerData[player] = {
		spawns               = 0,
		joinAt               = at,
		characterAdded       = player.CharacterAdded:Connect(function(...) characterAdded(player, ...) end),
		characterRemoving    = player.CharacterRemoving:Connect(function(...) characterRemoving(player, ...) end),
		onTeleport           = player.OnTeleport:Connect(function(...) onTeleport(player, ...) end),
		onChat               = player.Chatted:Connect(function(...) onChat(player, ...) end),
		onRobloxSubscription = player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(function() onRobloxSubscriptionChanged(player) end),
		lastClientRemote     = 0,
		clientRemoteCount    = 0
	}

	local joinData = player:GetJoinData() :: any

	Trail:PlayerEvent(player, "player.join", {
		fromGameId   = joinData.SourceGameId,
		fromPlaceId  = joinData.SourcePlaceId,
		fromPlayerId = joinData.ReferredByPlayerId,
		followedId   = player.FollowUserId,
		members      = joinData.Members,
		locale       = player.LocaleId,
		accountAge   = player.AccountAge,
		isPlus       = player.HasRobloxSubscription,
		hasBadge     = player.HasVerifiedBadge,
		isVerified   = player:IsVerified(),
		partyId      = player.PartyId,
		launchData   = joinData.LaunchData,
		name         = player.Name,
		displayName  = player.DisplayName,
	}, at)

	task.defer(onPlayerMeta, player)
end

local function onPlayerRemoving(player: Player, exitReason: Enum.PlayerExitReason)
	local pData = playerData[player]

	if pData then
		playerData[player] = nil

		local at = DateTime.now().UnixTimestampMillis

		-- Clean up connections
		if pData.characterAdded       then pData.characterAdded:Disconnect() end
		if pData.characterRemoving    then pData.characterRemoving:Disconnect() end
		if pData.onTeleport           then pData.onTeleport:Disconnect() end
		if pData.onChat               then pData.onChat:Disconnect() end
		if pData.onRobloxSubscription then pData.onRobloxSubscription:Disconnect() end

		Trail:PlayerEvent(player, "player.leave", {
			joinAt    = pData.joinAt,
			spawns    = pData.spawns,
			spawnAt   = pData.spawnAt,
			toPlaceId = pData.toPlaceId,
			exit = if pData.toPlaceId then 'Teleport' else enumName(exitReason)
		}, at)
	end
end

local function onServerStop(reason: Enum.CloseReason)
	for player in playerData do
		onPlayerRemoving(player, Enum.PlayerExitReason.Unknown)
	end

	-- Send a server stop event
	Trail:Event("server.stop", {reason = enumName(reason)})

	-- Force flush all pending events
	for _ = 1, SLOT_COUNT do
		if getBufferSize() == 0 then break end
		flushSlot()
	end

	-- Wait on any outstanding sends for up to 20 seconds
	local waiting = 0
	while sendsInProgress > 0 and waiting <= 20 do
		waiting += task.wait()
	end
end

local function onHeartbeat(dt: number)
	timeSinceLastFlush += dt
	timeSinceLastServerHeartbeat += dt

	-- track server heartbeat
	if timeSinceLastServerHeartbeat >= 6.0 then
		timeSinceLastServerHeartbeat = 0

		Trail:Event("server.heartbeat", {
			instances     = Stats.InstanceCount,
			primitives    = Stats.PrimitivesCount,
			fps           = math.round(workspace:GetRealPhysicsFPS()),
			dataIn        = math.round(Stats.DataReceiveKbps),
			dataOut       = math.round(Stats.DataSendKbps),
			physicsIn     = math.round(Stats.PhysicsReceiveKbps),
			physicsOut    = math.round(Stats.PhysicsSendKbps),
			physicsTime   = math.round(1e3 * Stats.PhysicsStepTime),
			heartbeatTime = math.round(1e3 * Stats.HeartbeatTime),
		})
	end

	-- Send once we've reached the max interval, or lower interval with a full slot
	if (timeSinceLastFlush >= MAX_SEND_INTERVAL) or (timeSinceLastFlush >= MIN_SEND_INTERVAL and readSlot ~= writeSlot) then
		flushSlot()
	end
end

-- PUBLIC FUNCTIONS --
function Trail.FormatVector3(v: Vector3?): vector3table
	return _vectorToTable(v or Vector3.zero)
end

-- Convenience function to add an event for a player
function Trail.ReceiptEvent(self: Trail, receiptInfo: dictionary, result: Enum.ProductPurchaseDecision, extra: dictionary?): boolean
	if self ~= Trail then
		warn("Call Trail:ReceiptEvent() not Trail.ReceiptEvent()")
		return false
	end

	if typeof(receiptInfo) ~= "table" or typeof(receiptInfo.PlayerId) ~= "number" then
		warn("Invalid receiptInfo provided to Trail:ReceiptEvent")
		return false
	end

	local receipt = {
		purchaseId = receiptInfo.PurchaseId,
		productId  = receiptInfo.ProductId,
		placeId    = receiptInfo.PlaceId,
		robux      = receiptInfo.CurrencySpent,
		channel    = enumName(receiptInfo.ProductPurchaseChannel),
		granted    = result == Enum.ProductPurchaseDecision.PurchaseGranted
	}

	if extra and typeof(extra) == "table" then
		for k,v in extra do
			if receipt[k] == nil then
				receipt[k] = v
			end
		end
	end

	return self:Event("purchase.receipt", receipt, receiptInfo.PlayerId)
end

-- Convenience function to add an event for a player
function Trail.PlayerEvent(self: Trail, player: Player, event: event, _data: dictionary?, at: number?): boolean
	if self ~= Trail then
		warn("Call Trail:PlayerEvent() not Trail.PlayerEvent()")
		return false
	end

	return self:Event(event, _data, player, at)
end

-- Add an event to the queue
function Trail.Event(self: Trail, event: event, _data: dictionary?, _player: (Player | number)?, at: number?): boolean
	if not isStarted then return false end

	if self ~= Trail then
		warn("Call Trail:Event() not Trail.Event()")
		return false
	end

	local eventName: string

	-- Event must either be a string, or an array of strings
	if typeof(event) == "string" then
		eventName = event
	elseif typeof(event) == "table" and #event > 0 then
		local ok, joined = pcall(table.concat, event, ".")
		if not ok then
			warn("Trail:Event: event table must contain only strings")
			return false
		end
		eventName = joined
	else
		warn("Trail:Event: event must be a string or non-empty table")
		return false
	end

	-- Get the current buffer size
	local bufferSize = getBufferSize()
	local eventPriority = EVENT_PRIORITIES[eventName] or 2
	local userId: number?
	local player: Player?
	local data: dictionary = {}

	-- Reject all events at high limit
	if bufferSize >= QUEUE_HIGH_LIMIT then
		warn("Trail:Event: queue is full")
		return false
	end

	if bufferSize >= QUEUE_MED_LIMIT and eventPriority > 1 then
		warn("Trail:Event: queue is filling up, skipping event: " .. eventName)
		return false
	end

	if bufferSize >= QUEUE_LOW_LIMIT and eventPriority > 2 then
		warn("Trail:Event: queue is filling up, skipping event: " .. eventName)
		return false
	end

	-- If slot is full, advance to next slot
	if #eventBuffer[writeSlot] >= SLOT_SIZE then

		local nextWriteSlot = incrementSlot(writeSlot)

		-- Shouldn't happen unless QUEUE_HIGH_LIMIT was changed
		if nextWriteSlot == readSlot then
			warn("Trail:Event: queue is full, failsafe triggered")
			return false
		else
			writeSlot = nextWriteSlot
		end
	end

	-- _data must be nil or a dictionary
	if _data ~= nil then
		-- reject
		if typeof(_data) ~= "table" then
			warn("Trail:Event: data must be a table or nil")
			return false
		-- Convert list to dictionary
		elseif isList(_data) then
			warn("Trail:Event: data appears to be an array, converting to dictionary, but change your usage")

			for k, v in _data do
				data[tostring(k)] = v
			end
		-- Regular table just shallow clone
		else
			data = table.clone(_data)
		end
	end

	-- _player needs to be a Player or userId
	if typeof(_player) == "Instance" and _player:IsA("Player") then
		userId = _player.UserId
		player = _player
	elseif typeof(_player) == "number" then
		userId = _player
		player = Players:GetPlayerByUserId(userId)
	end

	if player then
		local pData = playerData[player]

		if pData then
			data.joinAt = pData.joinAt
			data.spawns = pData.spawns
			data.spawnAt = pData.spawnAt
		end
	end

	local payload: payload = {
		seq   = sequenceId,
		at    = at or DateTime.now().UnixTimestampMillis,
		event = eventName,
		data  = data,
		user  = userId,
		pos   = if player then getPlayerPosition(player) else nil,
		ping  = if player then math.round(1e3 * player:GetNetworkPing()) else nil,
	}

	-- Build the event
	local success, result = pcall(HttpService.JSONEncode, HttpService, payload)

	if not success or type(result) ~= "string" then
		warn("Trail.Event: Failed to encode event: " .. tostring(result))
		return false
	end

	sequenceId += 1

	table.insert(eventBuffer[writeSlot], result)

	return true
end

function Trail.ProcessReceiptProxy(fn: receiptFunction): receiptFunction
	return function(receiptInfo: dictionary): Enum.ProductPurchaseDecision
		local success, result = pcall(fn, receiptInfo)

		if not success or typeof(result) ~= "EnumItem" then
			warn("Trail.ProcessReceiptProxy: wrapped handler errored: " .. tostring(result))
			result = Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if result == Enum.ProductPurchaseDecision.PurchaseGranted then
			task.defer(Trail.ReceiptEvent, Trail, receiptInfo, result, nil)
		end

		return result
	end
end

Trail.GetPlayerPosition = getPlayerPositionFromCharacter

-- Start the Trail module
function Trail.Start(): boolean
	if isStarted then return false end

	-- initialize eventBuffer if not already
	if eventBuffer[1] == nil then
		for i = 1, SLOT_COUNT do
			eventBuffer[i] = table.create(SLOT_SIZE) :: {string}
		end
	end

	if HttpService.HttpEnabled == false then
		warn("Trail: HTTP requests are disabled")
		return false
	end

	local trailKey = getSafeSecret("TRAIL_KEY")
		or script:GetAttribute("TrailKey_" .. tostring(game.GameId))
		or script:GetAttribute("TrailKey")

	if typeof(trailKey) ~= "string" or trailKey == "" then
		warn("Trail: Key must be provided via TRAIL_KEY secret or TrailKey attribute")
		return false
	end

	isStarted = true

	-- Set the key
	headers["x-trail-key"] = trailKey

	-- Connect to game events
	RunService.Heartbeat:Connect(onHeartbeat)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onServerStop)

	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.defer(onPlayerAdded, player)
	end

	-- Connect to purchase events
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassPurchaseFinished)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onProductPurchaseFinished)
	MarketplaceService.PromptPurchaseFinished:Connect(onPurchaseFinished)
	MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(onSubscriptionPurchaseFinished)
	MarketplaceService.PromptRobloxSubscriptionPurchaseFinished:Connect(onRobloxSubscriptionPurchaseFinished)

	-- Bind for client module
	if trailClientRemote and trailClientScript then
		trailClientRemote.OnServerEvent:Connect(onClientRemote)
		trailClientScript.Parent = game:GetService("ReplicatedStorage")
	end

	-- Send a server start event
	local serverType, serverId, ownerId = getServerInfo()

	Trail:Event("server.start", {
		serverType = serverType,
		serverId = serverId,
		ownerId = ownerId,
		isStudio = isStudio,
		matchmakingType = game.MatchmakingType.Name,
	})

	return true
end

return Trail