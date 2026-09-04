--!strict

local ClientCustomerTools = {}
ClientCustomerTools.__index = ClientCustomerTools

local Iris = require("./Iris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

type ClientCustomerToolsFields = {
	usernameState: any, -- Iris state objects (vendored, untyped)
	userIdState: any,
	canSaveGameState: any,
	waitingForResponse: boolean?, -- never assigned today; kept for the render check
	messageText: any?,
	userId: any?,
	username: any?,
	customerData: any?,
}

export type ClientCustomerTools = typeof(setmetatable({} :: ClientCustomerToolsFields, ClientCustomerTools))

function ClientCustomerTools.renderIris(self: ClientCustomerTools)
	Iris.SeparatorText({"Customer"})

	Iris.InputText({"Username"}, { text = self.usernameState })
	Iris.Text({"or"})
	Iris.InputNum({[Iris.Args.InputNum.Text] = "UserId", [Iris.Args.InputNum.Format] = "%i", [Iris.Args.InputNum.NoButtons] = true} :: { [any]: any }, { number = self.userIdState })
	if Iris.Button({"Lookup"}).clicked() then
		local username = self.usernameState:get()
		local userId = self.userIdState:get()

		if username == self.username or userId == self.userId then
			-- just updating online status, so don't change anything
		else
			-- looking up a new person, so can't save any state
			self.canSaveGameState:set(false)
		end

		--print("looking up", username, userId)
		-- ask server for info on this person
		RemoteEvents.TryCustomerTool:FireServer("lookupUser", username, userId)
	end
	Iris.SeparatorText({"Info"})

	if self.waitingForResponse then
		Iris.SeparatorText({"Waiting for response from server"})
	end

	if self.messageText then
		Iris.Text({self.messageText})
	end

	if self.username and self.userId then
		Iris.SeparatorText({"Player Data"})

		Iris.SameLine()
		Iris.Text({string.format("Username: %s", self.username)})
		Iris.Text({string.format("UserId: %i", self.userId)})
		Iris.End()

		local customerData = self.customerData
		if customerData then
			if customerData.isInGame == nil then
				Iris.Text({"Unknown if playing"})
			else
				if customerData.isInGame then
					Iris.Text({"Currently playing"})
				else
					Iris.Text({"Not playing right now"})
				end
			end
		end

		-- maybe get/show robux purchase data?
		-- show save game

		-- button to load their game
		if Iris.Button({"Load Save Game"}).clicked() then
			RemoteEvents.TryCustomerTool:FireServer("loadUserSaveData", self.userId)

			self.canSaveGameState:set(true)
		end

		if self.canSaveGameState:get() then
			if Iris.Button({"Save Game To User"}).clicked() then
				RemoteEvents.TryCustomerTool:FireServer("saveDataToUser", self.userId)

				self.canSaveGameState:set(false)
			end
		else
			Iris.Text({"no state loaded, cannot save"})
		end

	end

	-- actions we want to be able to do on this person
	-- see full state

	-- save state -- broadcast message to set player to not-save and disconnect them, then save it
	Iris.End()

end

function ClientCustomerTools.notifyData(self: ClientCustomerTools, messageText: any, userId: any, username: any, customerData: any)
	print("customer tools got data", messageText, userId, username, customerData)

	self.messageText = messageText
	self.userId = userId
	self.username = username
	self.customerData = customerData

	self.usernameState:set(username)
	self.userIdState:set(userId)

end


function ClientCustomerTools.new(): ClientCustomerTools
	local self = setmetatable({} :: ClientCustomerToolsFields, ClientCustomerTools)

	self.usernameState = Iris.State("")
	self.userIdState = Iris.State(0)

	self.canSaveGameState = Iris.State(false)


	return self
end

local singleton = ClientCustomerTools.new()

return singleton
