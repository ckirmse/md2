--!strict

local ClientNetopsTools = {}
ClientNetopsTools.__index = ClientNetopsTools

local Iris = require("./Iris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

type RemoteEventData = {
	name: string,
	count: number,
	elapsedTime: number,
}

type ClientNetopsToolsFields = {
	prevRemoteEventDatas: { RemoteEventData }?,
	latestRemoteEventDatas: { RemoteEventData }?,
}

export type ClientNetopsTools = typeof(setmetatable({} :: ClientNetopsToolsFields, ClientNetopsTools))

function ClientNetopsTools.renderIris(self: ClientNetopsTools, isShown: boolean)
	if Iris.Button({"Get Remote Event Metrics"}).clicked() then
		RemoteEvents.TryDevTool:FireServer("getRemoteEventMetrics")
	end

	Iris.SeparatorText({"Since Server Launch"})

	local latestRemoteEventDatas = self.latestRemoteEventDatas
	if latestRemoteEventDatas then
		self:renderRemoteEventTable(latestRemoteEventDatas)
	else
		self:renderRemoteEventTable({})

	end

	Iris.SeparatorText({"Most Recent Period"})

	local remoteEventDatas = self:getDiffRemoteEventDatas()
	if remoteEventDatas then
		self:renderRemoteEventTable(remoteEventDatas)
	else
		self:renderRemoteEventTable({})
	end


	Iris.End()
end

function ClientNetopsTools.renderRemoteEventTable(self: ClientNetopsTools, remoteEventDatas: { RemoteEventData })
	local haveHeader = true
	local rowBackground = true
	Iris.Table({4, haveHeader, rowBackground, false, false, false, false, true} :: { any })

	-- Header Row
	Iris.PushConfig({TextXAlignment = Enum.TextXAlignment.Center})
	Iris.Text({"Remote Event Name"})
	Iris.NextColumn()
	Iris.Text({"Count"})
	Iris.NextColumn()
	Iris.Text({"Elapsed Time (s)"})
	Iris.NextColumn()
	Iris.Text({"Average Time (s)"})
	Iris.NextColumn()
	Iris.PopConfig()

	Iris.NextRow()

	-- Data Rows
	for _, data in remoteEventDatas do
		Iris.Text({data.name})
		Iris.NextColumn()

		Iris.PushConfig({TextXAlignment = Enum.TextXAlignment.Right})
		Iris.Text({tostring(data.count)})
		Iris.PopConfig()
		Iris.NextColumn()

		Iris.PushConfig({TextXAlignment = Enum.TextXAlignment.Right})
		Iris.Text({string.format("%.3f", data.elapsedTime)})
		Iris.PopConfig()
		Iris.NextColumn()

		local averageTime = 0
		if data.count > 0 then
			averageTime = data.elapsedTime / data.count
		end
		Iris.PushConfig({TextXAlignment = Enum.TextXAlignment.Right})
		Iris.Text({string.format("%.3f", averageTime)})
		Iris.PopConfig()
		Iris.NextColumn()

		Iris.NextRow()
	end

	Iris.End() -- Close the Table
end

function ClientNetopsTools.getDiffRemoteEventDatas(self: ClientNetopsTools): { RemoteEventData }?
	local prevRemoteEventDatas = self.prevRemoteEventDatas
	local latestRemoteEventDatas = self.latestRemoteEventDatas
	if not prevRemoteEventDatas or not latestRemoteEventDatas then
		return nil
	end

	if #prevRemoteEventDatas ~= #latestRemoteEventDatas then
		return nil
	end

	local remoteEventDatas: { RemoteEventData } = {}
	for i = 1, #prevRemoteEventDatas do
		table.insert(remoteEventDatas,
			{
				name = prevRemoteEventDatas[i].name,
				count = latestRemoteEventDatas[i].count - prevRemoteEventDatas[i].count,
				elapsedTime = latestRemoteEventDatas[i].elapsedTime - prevRemoteEventDatas[i].elapsedTime,
			}
		)
	end

	return remoteEventDatas
end

function ClientNetopsTools.notifyRemoteEventMetrics(self: ClientNetopsTools, remoteEventMetrics: { [string]: any })
	--print("remote event metrics", remoteEventMetrics)

	local latestRemoteEventDatas: { RemoteEventData } = {}
	for remoteEventName, remoteEventData in remoteEventMetrics do
		table.insert(latestRemoteEventDatas,
			{
				name = remoteEventName,
				count = remoteEventData.count :: number,
				elapsedTime = remoteEventData.elapsedTime :: number,
			}
		)
	end

	table.sort(latestRemoteEventDatas,
		function(a: RemoteEventData, b: RemoteEventData)
			return a.name < b.name
		end
	)

	self.prevRemoteEventDatas = self.latestRemoteEventDatas
	self.latestRemoteEventDatas = latestRemoteEventDatas
end

function ClientNetopsTools.new(): ClientNetopsTools
	local self = setmetatable({} :: ClientNetopsToolsFields, ClientNetopsTools)

	self.latestRemoteEventDatas = nil

	return self
end

local singleton = ClientNetopsTools.new()

return singleton
