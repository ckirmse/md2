--!strict

local ServerListener = {}
ServerListener.__index = ServerListener

local messagingService = game:GetService("MessagingService")

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

local ServerTopics = require("./ServerTopics")

type ServerListenerFields = {}

export type ServerListener = typeof(setmetatable({} :: ServerListenerFields, ServerListener))


function ServerListener.listenDisconnectUser(self: ServerListener)
	local isSuccess, connection = pcall(
		function()
			return messagingService:SubscribeAsync(ServerTopics.DISCONNECT_USER,
				function(message: any)
					-- This function runs on ALL servers when one server publishes
					local data = message.Data
					local sentTime = message.Sent
					print("Received Global Message:", data, sentTime)
					local userId = data.userId
					local reason = data.reason

					local textMessage
					if reason == "cstool-save" then
						textMessage = string.format("Customer Service has adjusted your game state; please reconnect")
					else
						textMessage = "unknown"
					end

					local foundUser = gameController:tryDisconnectPlayerByUserId(userId, textMessage)

					if foundUser then
						print("disconnected user from this server due to", reason, userId)
					end
				end
			)
		end
	)
	if not isSuccess then
		warn("server failed to connect to listen for disconnect users", connection)
	end
end

function ServerListener.init(self: ServerListener)
	self:listenDisconnectUser()

end

function ServerListener.new(): ServerListener
	local self: ServerListener = setmetatable({} :: ServerListenerFields, ServerListener)

	return self
end

function ServerListener.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = ServerListener.new()

return singleton
