--!strict

-- Client data path of the reworked Index: the server sends the whole index at join (NotifyIndexV2Data), then one
-- NotifyIndexV2Discovery per new entry and one NotifyIndexV2TierResult per claim. This module only holds that state and
-- answers questions about it; the UI reads from it. Milestones are built with the same IndexRewardMath inputs the
-- server uses, so a milestone shown as claimable here is the one the server accepts. The server decides everything.
local ClientIndexV2Data = {}
ClientIndexV2Data.__index = ClientIndexV2Data

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local enums = require("@game/ReplicatedStorage/Shared/Enums")
local IndexRewardMath = require("@game/ReplicatedStorage/Shared/IndexRewardMath")

-- the server answers every claim; this only unlocks a claim whose request was dropped
local PENDING_TIMEOUT_SEC = 5

export type EntryKey = string | number

export type Entry = {
	key: EntryKey,
	displayName: string,
	group: number,
}

export type RowReward = {
	rarity: number,
	displayText: string,
	icon: string?,
}

export type TierReward = {
	requiredPercent: number,
	displayText: string,
	icon: string?,
}

export type CategoryData = {
	category: number,
	name: string,
	entries: { Entry },
	rowRewards: { RowReward },
	tiers: { TierReward },
	discovered: { [EntryKey]: boolean },
}

type DiscoveryListener = (category: number, key: EntryKey) -> ()
type ClaimListener = (tierId: string, isSuccess: boolean) -> ()

type ClientIndexV2DataFields = {
	categoriesById: { [number]: CategoryData },
	claimed: { [string]: boolean },
	incomeBonusPercent: number,
	singleTierBar: boolean,
	isLoaded: boolean,
	pendingTierId: string?,
	changedListeners: { () -> () },
	discoveryListeners: { DiscoveryListener },
	claimListeners: { ClaimListener },
}

export type ClientIndexV2Data = typeof(setmetatable({} :: ClientIndexV2DataFields, ClientIndexV2Data))

function ClientIndexV2Data.fireChanged(self: ClientIndexV2Data)
	for _, listener in self.changedListeners do
		listener()
	end
end

-- a listener runs after the data, a discovery or a claim result changes any state
function ClientIndexV2Data.addChangedListener(self: ClientIndexV2Data, listener: () -> ())
	table.insert(self.changedListeners, listener)
end

function ClientIndexV2Data.addDiscoveryListener(self: ClientIndexV2Data, listener: DiscoveryListener)
	table.insert(self.discoveryListeners, listener)
end

function ClientIndexV2Data.addClaimListener(self: ClientIndexV2Data, listener: ClaimListener)
	table.insert(self.claimListeners, listener)
end

function ClientIndexV2Data.hasData(self: ClientIndexV2Data): boolean
	return self.isLoaded
end

function ClientIndexV2Data.setData(self: ClientIndexV2Data, indexData: any)
	if typeof(indexData) ~= "table" then
		warn("ClientIndexV2Data: ignoring malformed data")
		return
	end

	local categoriesById: { [number]: CategoryData } = {}
	for _, categoryRecord in indexData.categories do
		local discovered: { [EntryKey]: boolean } = {}
		categoriesById[categoryRecord.category] = {
			category = categoryRecord.category,
			name = categoryRecord.name,
			entries = categoryRecord.entries,
			rowRewards = categoryRecord.rowRewards,
			tiers = categoryRecord.tiers,
			discovered = discovered,
		}
	end

	for _, discoveredRecord in indexData.discovered do
		local categoryData = categoriesById[discoveredRecord.category]
		if categoryData then
			for _, key in discoveredRecord.keys do
				categoryData.discovered[key] = true
			end
		end
	end

	local claimed: { [string]: boolean } = {}
	for _, tierId in indexData.claimed do
		claimed[tierId] = true
	end

	self.categoriesById = categoriesById
	self.claimed = claimed
	self.incomeBonusPercent = indexData.incomeBonusPercent
	self.singleTierBar = indexData.isSingleTierBar == true
	self.isLoaded = true
	self.pendingTierId = nil

	self:fireChanged()
end

function ClientIndexV2Data.notifyDiscovery(self: ClientIndexV2Data, category: any, key: any)
	local categoryData = self.categoriesById[category]
	if not categoryData or (typeof(key) ~= "string" and typeof(key) ~= "number") then
		return
	end

	if categoryData.discovered[key] then
		return
	end

	categoryData.discovered[key] = true

	for _, listener in self.discoveryListeners do
		listener(category, key)
	end
	self:fireChanged()
end

function ClientIndexV2Data.notifyTierResult(self: ClientIndexV2Data, tierId: any, isSuccess: any, incomeBonusPercent: any)
	if typeof(tierId) ~= "string" then
		return
	end

	if self.pendingTierId == tierId then
		self.pendingTierId = nil
	end

	if isSuccess == true then
		self.claimed[tierId] = true
	end
	if typeof(incomeBonusPercent) == "number" then
		self.incomeBonusPercent = incomeBonusPercent
	end

	for _, listener in self.claimListeners do
		listener(tierId, isSuccess == true)
	end
	self:fireChanged()
end

-- categories in enum order
function ClientIndexV2Data.getCategories(self: ClientIndexV2Data): { CategoryData }
	local categories: { CategoryData } = {}
	for _, category in enums.getAllValues(enums.IndexCategory) do
		local categoryData = self.categoriesById[category]
		if categoryData then
			table.insert(categories, categoryData)
		end
	end

	return categories
end

function ClientIndexV2Data.getCategory(self: ClientIndexV2Data, category: number): CategoryData?
	return self.categoriesById[category]
end

function ClientIndexV2Data.isDiscovered(self: ClientIndexV2Data, category: number, key: EntryKey): boolean
	local categoryData = self.categoriesById[category]
	return categoryData ~= nil and categoryData.discovered[key] == true
end

function ClientIndexV2Data.getProgress(self: ClientIndexV2Data, category: number): (number, number)
	local categoryData = self.categoriesById[category]
	if not categoryData then
		return 0, 0
	end

	local collected = 0
	for _, entry in categoryData.entries do
		if categoryData.discovered[entry.key] then
			collected += 1
		end
	end

	return collected, #categoryData.entries
end

function ClientIndexV2Data.isSingleTierBar(self: ClientIndexV2Data): boolean
	return self.singleTierBar
end

function ClientIndexV2Data.getIncomeBonusPercent(self: ClientIndexV2Data): number
	return self.incomeBonusPercent
end

function ClientIndexV2Data.getMilestones(self: ClientIndexV2Data, category: number): { IndexRewardMath.Milestone }
	local categoryData = self.categoriesById[category]
	if not categoryData then
		return {}
	end

	local collectedByGroup: { [number]: number } = {}
	local totalByGroup: { [number]: number } = {}
	for _, entry in categoryData.entries do
		totalByGroup[entry.group] = (totalByGroup[entry.group] or 0) + 1
		if categoryData.discovered[entry.key] then
			collectedByGroup[entry.group] = (collectedByGroup[entry.group] or 0) + 1
		end
	end

	local rowRarities: { number } = {}
	for _, rowReward in categoryData.rowRewards do
		table.insert(rowRarities, rowReward.rarity)
	end

	local tierPercents: { number } = {}
	for _, tier in categoryData.tiers do
		table.insert(tierPercents, tier.requiredPercent)
	end

	return IndexRewardMath.buildMilestones(category, rowRarities, tierPercents, collectedByGroup, totalByGroup, self.claimed)
end

function ClientIndexV2Data.getRewardText(self: ClientIndexV2Data, category: number, milestone: IndexRewardMath.Milestone): string
	local categoryData = self.categoriesById[category]
	if not categoryData then
		return ""
	end

	if milestone.kind == IndexRewardMath.Kind.ROW then
		for _, rowReward in categoryData.rowRewards do
			if rowReward.rarity == milestone.rarity then
				return rowReward.displayText
			end
		end
		return ""
	end

	local tier = categoryData.tiers[milestone.tierIndex :: number]
	return if tier then tier.displayText else ""
end

function ClientIndexV2Data.getRewardIcon(self: ClientIndexV2Data, category: number, milestone: IndexRewardMath.Milestone): string?
	local categoryData = self.categoriesById[category]
	if not categoryData then
		return nil
	end

	if milestone.kind == IndexRewardMath.Kind.ROW then
		for _, rowReward in categoryData.rowRewards do
			if rowReward.rarity == milestone.rarity then
				return rowReward.icon
			end
		end
		return nil
	end

	local tier = categoryData.tiers[milestone.tierIndex :: number]
	return if tier then tier.icon else nil
end

function ClientIndexV2Data.hasClaimable(self: ClientIndexV2Data, category: number?): boolean
	if category then
		return IndexRewardMath.hasClaimable(self:getMilestones(category))
	end

	for categoryId in self.categoriesById do
		if IndexRewardMath.hasClaimable(self:getMilestones(categoryId)) then
			return true
		end
	end

	return false
end

function ClientIndexV2Data.isClaimPending(self: ClientIndexV2Data): boolean
	return self.pendingTierId ~= nil
end

function ClientIndexV2Data.getPendingTierId(self: ClientIndexV2Data): string?
	return self.pendingTierId
end

-- asks the server to claim; returns false when nothing was sent (not claimable, or another claim is in flight)
function ClientIndexV2Data.tryClaim(self: ClientIndexV2Data, tierId: string): boolean
	if self.pendingTierId then
		return false
	end

	for categoryId in self.categoriesById do
		local milestone = IndexRewardMath.findMilestone(self:getMilestones(categoryId), tierId)
		if milestone then
			if not milestone.isClaimable then
				return false
			end

			self.pendingTierId = tierId
			RemoteEvents.TryClaimIndexV2Tier:FireServer(tierId)

			task.delay(PENDING_TIMEOUT_SEC, function()
				if self.pendingTierId == tierId then
					self.pendingTierId = nil
					self:fireChanged()
				end
			end)
			return true
		end
	end

	return false
end

function ClientIndexV2Data.init(self: ClientIndexV2Data)
	local dataRemote: any = RemoteEvents:FindFirstChild("NotifyIndexV2Data")
	local discoveryRemote: any = RemoteEvents:FindFirstChild("NotifyIndexV2Discovery")
	local tierResultRemote: any = RemoteEvents:FindFirstChild("NotifyIndexV2TierResult")
	if not dataRemote or not discoveryRemote or not tierResultRemote then
		warn("ClientIndexV2Data: the Index V2 RemoteEvents are missing, Index V2 is disabled")
		return
	end

	dataRemote.OnClientEvent:Connect(function(indexData: any)
		self:setData(indexData)
	end)

	discoveryRemote.OnClientEvent:Connect(function(category: any, key: any)
		self:notifyDiscovery(category, key)
	end)

	tierResultRemote.OnClientEvent:Connect(function(tierId: any, isSuccess: any, incomeBonusPercent: any)
		self:notifyTierResult(tierId, isSuccess, incomeBonusPercent)
	end)
end

function ClientIndexV2Data.new(): ClientIndexV2Data
	local self: ClientIndexV2Data = setmetatable({
		categoriesById = {},
		claimed = {},
		incomeBonusPercent = 0,
		singleTierBar = false,
		isLoaded = false,
		pendingTierId = nil,
		changedListeners = {},
		discoveryListeners = {},
		claimListeners = {},
	} :: ClientIndexV2DataFields, ClientIndexV2Data)

	return self
end

local singleton = ClientIndexV2Data.new()

return singleton
