--!strict

local ClientCrystalManager = {}
ClientCrystalManager.__index = ClientCrystalManager

local collectionService = game:GetService("CollectionService")
local marketplaceService = game:GetService("MarketplaceService")
local runService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")
local UX = GameAssets:WaitForChild("UX")
-- the effect/billboard templates' shapes only exist in Studio, so they are untyped here
local CountdownBillboard: any = UX:WaitForChild("CountdownBillboard")
local Effects = GameAssets:WaitForChild("Effects")
local CrystalBreakParent: any = Effects:WaitForChild("CrystalBreakParent")
local ClaimableCrystalAudioParent: any = Effects:WaitForChild("ClaimableCrystalAudioParent")
local ClaimCrystalAudioParent: any = Effects:WaitForChild("ClaimCrystalAudioParent")
local CrystalCrackParent = Effects:WaitForChild("CrystalCrackParent")
local CrystalCrack: any = CrystalCrackParent:WaitForChild("Crack")
local OpenedCrystalAudioParent: any = Effects:WaitForChild("OpenedCrystalAudioParent")
local OpeningCrystalAudioParent: any = Effects:WaitForChild("OpeningCrystalAudioParent")
local SummonDragonToOpenAudioParent: any = Effects:WaitForChild("SummonDragonToOpenAudioParent")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local PivotToTween = require("@game/ReplicatedStorage/Shared/PivotToTween")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local CLAIMABLE_BASE_HEIGHT = 3
local CLAIMABLE_PULSE_AMPLITUDE = 0.5
local CLAIMABLE_PULSE_PERIOD = 12
local CLAIMABLE_ROTATION_PERIOD = 4

local player = game:GetService("Players").LocalPlayer :: Player

type OpeningState = {
	audioParent: any?,
}

type ClaimableState = {
	audioParent: any?,
	serverCFrame: CFrame?,
	floatingCFrame: CFrame?,
	riseTween: Tween?,
	runConnect: RBXScriptConnection?,
	shouldPulse: boolean?,
	pulseSec: number?,
}

type IndicatorData = {
	instance: any, -- world crystal Model/Part; its shape only exists at runtime
	isOwnedByPlayer: boolean,
	opening: OpeningState?,
	billboard: any?, -- CountdownBillboard clone
	runConnect: RBXScriptConnection?,
	robuxProductId: number?,
	animateCrystalClaimable: ClaimableState?,
	animationDragonComingToOpenChangedConnect: RBXScriptConnection?,
	openCompleteTimeChangedConnect: RBXScriptConnection?,
	animationCrystalOpenedChangedConnect: RBXScriptConnection?,
	crystalClaimableConnect: RBXScriptConnection?,
	animationClaimingChangedConnect: RBXScriptConnection?,
}

type InstantOpenCrystalData = {
	robuxProductId: number,
	durationSec: number,
	robuxPrice: number?,
}

type ClientCrystalManagerFields = {
	indicatorMap: { [number]: IndicatorData },
	instantOpenCrystalDatas: { InstantOpenCrystalData },
	isRobuxReady: boolean,
}

export type ClientCrystalManager = typeof(setmetatable({} :: ClientCrystalManagerFields, ClientCrystalManager))

function ClientCrystalManager.updateBillboardByItemId(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance
	local billboard = indicatorData.billboard
	if not billboard then
		return
	end

	-- the character rig's children only exist at runtime, so they are untyped here
	local distance = (((player.Character :: any).HumanoidRootPart.Position :: Vector3) - inst:GetPivot().Position).Magnitude
	if distance <= Constants.COUNTDOWN_DISTANCE then
		billboard.Enabled = true
	else
		billboard.Enabled = false
	end

	local completeTime = indicatorData.instance:GetAttribute(Attributes.OPEN_COMPLETE_TIME)
	if not completeTime then
		return
	end

	--print("have complete time for", itemId, completeTime)
	local remainingSec = math.ceil(math.max(0, completeTime - workspace:GetServerTimeNow()))

	local s = string.format("Open in %s", utils.convertDurationSecToString(remainingSec))

	local itemNameLabel = billboard:FindFirstChild("TextLabel")
	if s ~= itemNameLabel.Text then
		itemNameLabel.Text = s

		if self.isRobuxReady then
			-- these are in descending order of time
			local bestIndex: number?
			for i = 1, #self.instantOpenCrystalDatas do
				if self.instantOpenCrystalDatas[i].durationSec < remainingSec then
					break
				end
				bestIndex = i
			end
			if not bestIndex then
				return
			end

			local button = billboard:FindFirstChild("SpeedUpButton")
			if not button.Visible then
				button.Activated:Connect(
					function()
						-- tell server we want this one opened, so if robux purchase goes through,
						-- it'll try to open this one
						RemoteEvents.TryMarkInstantOpenCrystal:FireServer(itemId)
						--print("prompting to robux the crystal open")

						local isSuccess, errorMessage = pcall(
							function()
								marketplaceService:PromptProductPurchase(player, indicatorData.robuxProductId :: number)
							end
						)

						if isSuccess then
							--print("yes prompted")
						else
							warn("error prompting for robux purchase", errorMessage)
						end
					end
				)
				button.Visible = true
			end
			local cost = utils.findFirstDescendant(button, "Cost") :: any
			cost.Text = tostring(self.instantOpenCrystalDatas[bestIndex].robuxPrice)

			indicatorData.robuxProductId = self.instantOpenCrystalDatas[bestIndex].robuxProductId
		end
	end
end

function ClientCrystalManager.beginAnimateDragonComingToOpen(self: ClientCrystalManager, itemId: number, position: Vector3)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local summonDragonToOpenAudioParent = SummonDragonToOpenAudioParent:Clone()
	summonDragonToOpenAudioParent.Position = position
	summonDragonToOpenAudioParent.Parent = workspace

	local audioSummonToOpen = summonDragonToOpenAudioParent:FindFirstChild("AudioSummonToOpen")
	if not audioSummonToOpen.IsReady then
		local isReadyChanged = audioSummonToOpen:GetPropertyChangedSignal("IsReady")
		isReadyChanged:Wait()
	end
	game:GetService("Debris"):AddItem(summonDragonToOpenAudioParent, 5) -- destroy after 5s
	audioSummonToOpen:Play()
end

function ClientCrystalManager.cleanupAnimateDragonComingToOpen(self: ClientCrystalManager, itemId: number)
end

function ClientCrystalManager.beginAnimateOpen(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	indicatorData.opening = {}

	if indicatorData.isOwnedByPlayer then
		local billboard = CountdownBillboard:Clone()
		billboard.MaxDistance = 500
		billboard.Adornee = inst
		billboard.Enabled = true
		local _, size = inst:GetBoundingBox()
		billboard.StudsOffset = Vector3.new(0, 8 + size.Y / 2, 0)
		billboard:SetAttribute(Attributes.ITEM_ID, itemId) -- for debugging

		local button = billboard:FindFirstChild("SpeedUpButton")
		button.Visible = false

		indicatorData.billboard = billboard

		self:updateBillboardByItemId(itemId)

		billboard.Parent = player:WaitForChild("PlayerGui")

		indicatorData.runConnect = runService.PostSimulation:Connect(
			function(deltaTime)
				self:updateBillboardByItemId(itemId)
			end
		)
	end

	local openingCrystalAudioParent = OpeningCrystalAudioParent:Clone()
	openingCrystalAudioParent.Position = inst:GetPivot().Position
	openingCrystalAudioParent.Parent = workspace

	local audioOpeningCrystal = openingCrystalAudioParent:FindFirstChild("AudioOpeningCrystal")
	audioOpeningCrystal.Looping = true
	audioOpeningCrystal:Play();

	(indicatorData.opening :: OpeningState).audioParent = openingCrystalAudioParent

end

function ClientCrystalManager.cleanupAnimateOpen(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local runConnect = indicatorData.runConnect
	if runConnect then
		runConnect:Disconnect()
		indicatorData.runConnect = nil
	end

	local billboard = indicatorData.billboard
	if billboard then
		billboard:Destroy()
		indicatorData.billboard = nil
	end

	local opening = indicatorData.opening
	if opening then
		if opening.audioParent then
			opening.audioParent:Destroy()
			opening.audioParent = nil
		end
		indicatorData.opening = nil
	end
end

function ClientCrystalManager.beginAnimateCrystalOpened(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local openedCrystalAudioParent = OpenedCrystalAudioParent:Clone()
	openedCrystalAudioParent.Position = inst:GetPivot().Position
	openedCrystalAudioParent.Parent = workspace
	game:GetService("Debris"):AddItem(openedCrystalAudioParent, 5) -- destroy after 5s

	local audioOpenedCrystal = openedCrystalAudioParent:FindFirstChild("AudioOpenedCrystal")
	audioOpenedCrystal:Play()
end

function ClientCrystalManager.cleanupAnimateCrystalOpened(self: ClientCrystalManager, itemId: number)
end

function ClientCrystalManager.claimableRun(self: ClientCrystalManager, deltaTime: number, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local claimable = indicatorData.animateCrystalClaimable
	if not claimable then
		return
	end

	if claimable.shouldPulse then

		local pulseSec = (claimable.pulseSec or 0) + deltaTime
		claimable.pulseSec = pulseSec

		local floatingCFrame = claimable.floatingCFrame :: CFrame

		local rotationAngle = 2 * math.pi * pulseSec / CLAIMABLE_ROTATION_PERIOD

		local rotation = floatingCFrame.Rotation * CFrame.Angles(0, rotationAngle, 0)
		local position = floatingCFrame.Position + CLAIMABLE_PULSE_AMPLITUDE * Vector3.new(0, math.sin(2 * math.pi * pulseSec / CLAIMABLE_PULSE_PERIOD), 0)
		local cframe = rotation + position
		inst:PivotTo(cframe)
	end
end

function ClientCrystalManager.beginAnimateCrystalClaimable(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	if indicatorData.animateCrystalClaimable then
		return
	end

	local claimable: ClaimableState = {}
	indicatorData.animateCrystalClaimable = claimable

	local inst = indicatorData.instance

	local part = utils.getMainPart(inst)
	if not part then
		warn("claimable crystal has no parts", inst)
		return
	end

	local claimableCrystalAudioParent = ClaimableCrystalAudioParent:Clone()
	claimableCrystalAudioParent.Position = inst:GetPivot().Position
	claimableCrystalAudioParent.Parent = inst

	local audioClaimableCrystal = claimableCrystalAudioParent:FindFirstChild("AudioClaimableCrystal")
	audioClaimableCrystal.Looping = true
	audioClaimableCrystal:Play()

	claimable.audioParent = claimableCrystalAudioParent

	-- put a cracking particle on it

	local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

	local crystalCrackParticle = CrystalCrack:Clone()
	crystalCrackParticle.Color = ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement))
	crystalCrackParticle.Parent = part

	-- start some tweens to make the crystal pulse and look cool
	-- do a tween to raise its Y
	-- then we rotate & pulse crystal vertically in a run() function because they run in different rates

	local cframe = inst:GetPivot() :: CFrame
	claimable.serverCFrame = cframe
	local floatingCFrame = cframe.Rotation + (cframe.Position + Vector3.new(0, CLAIMABLE_BASE_HEIGHT, 0))
	claimable.floatingCFrame = floatingCFrame

	-- make the crystal rise off the ground; then it will pulse
	local riseTweenInfo = TweenInfo.new(
		1.5,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
	local riseTween = PivotToTween(inst, riseTweenInfo, floatingCFrame)
	riseTween.Completed:Connect(
		function()
			if not indicatorData.animateCrystalClaimable then
				return
			end

			claimable.riseTween = nil
			claimable.shouldPulse = true
			claimable.pulseSec = 0
		end
	)
	claimable.riseTween = riseTween
	riseTween:Play()

	claimable.runConnect = runService.PostSimulation:Connect(
		function(deltaTime)
			self:claimableRun(deltaTime, itemId)
		end
	)

end

function ClientCrystalManager.cleanupAnimateCrystalClaimable(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local claimable = indicatorData.animateCrystalClaimable
	if not claimable then
		return
	end

	if claimable.audioParent then
		claimable.audioParent:Destroy()
		claimable.audioParent = nil
	end

	local riseTween = claimable.riseTween
	if riseTween then
		riseTween:Cancel()
		claimable.riseTween = nil
	end

	local runConnect = claimable.runConnect
	if runConnect then
		runConnect:Disconnect()
		claimable.runConnect = nil
	end

	indicatorData.animateCrystalClaimable = nil
end

function ClientCrystalManager.beginAnimateClaiming(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local inst = indicatorData.instance

	local primaryElement = inst:GetAttribute(Attributes.PRIMARY_ELEMENT)

	local crystalBreakParent = CrystalBreakParent:Clone()
	crystalBreakParent:PivotTo(inst:GetPivot())
	utils.setPropertyTreeClassName(crystalBreakParent, "ParticleEmitter", "Color", ColorSequence.new(utils.getEffectColorForPrimaryElement(primaryElement)))

	crystalBreakParent.Parent = workspace

	local part = utils.getMainPart(inst)
	if not part then
		warn("claimable crystal has no parts", inst)
		return
	end

	part.Transparency = 1

	crystalBreakParent:FindFirstChild("BurstRing"):Emit(1)
	crystalBreakParent:FindFirstChild("CrystalBreak"):Emit(50)
	crystalBreakParent:FindFirstChild("Flash"):Emit(1)

	utils.safelyDisposeOfParticleParent(crystalBreakParent, 2)

	local openingCrystalAudioParent = ClaimCrystalAudioParent:Clone()
	openingCrystalAudioParent.Position = inst:GetPivot().Position
	openingCrystalAudioParent.Parent = workspace

	local audioClaimCrystal = openingCrystalAudioParent:FindFirstChild("AudioClaimCrystal")
	audioClaimCrystal:Play()

	game:GetService("Debris"):AddItem(audioClaimCrystal, 5) -- destroy after 5s

end

function ClientCrystalManager.cleanupAnimateClaiming(self: ClientCrystalManager, itemId: number)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

end

function ClientCrystalManager.setClaimablePulseEnabled(self: ClientCrystalManager, itemId: number, isEnabled: boolean)
	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	-- as of 2026-august-11 the claimable-state nil check happens before the pulseSec read; the
	-- original read pulseSec first, which could crash when the state was already cleaned up
	local claimable = indicatorData.animateCrystalClaimable
	if not claimable then
		return
	end

	if isEnabled and not claimable.pulseSec then
		-- safety check, saw this could happen in prod 2026-april-15
		return
	end

	claimable.shouldPulse = isEnabled

end

function ClientCrystalManager.getOpenableCrystalCount(self: ClientCrystalManager): number
	local count = 0

	for itemId, indicatorData in self.indicatorMap do
		if not indicatorData.isOwnedByPlayer then
			continue
		end
		if indicatorData.opening then
			count += 1
		end
	end

	return count
end

-- note this happens when an instance enters the data model, including when going from parent of nil to something else, which happens
-- when an item is activated from a hand
function ClientCrystalManager.notifyNewInstance(self: ClientCrystalManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local isOwnedByPlayer
	if inst:GetAttribute(Attributes.USER_ID) == player.UserId then
		isOwnedByPlayer = true
	else
		isOwnedByPlayer = false
	end

	self.indicatorMap[itemId] = {
		instance = inst,
		isOwnedByPlayer = isOwnedByPlayer,
		opening = nil,
	}

	local indicatorData = self.indicatorMap[itemId]


	if inst:GetAttribute(Attributes.OPEN_COMPLETE_TIME) then
		self:beginAnimateOpen(itemId)
	end

	indicatorData.animationDragonComingToOpenChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_DRAGON_COMING_TO_OPEN):Connect(
		function()
			local animationDragonComingToOpenStr = inst:GetAttribute(Attributes.ANIMATION_DRAGON_COMING_TO_OPEN)
			if animationDragonComingToOpenStr then
				local iterFunc = string.gmatch(animationDragonComingToOpenStr, "%S+")

				local x = tonumber(iterFunc())
				local y = tonumber(iterFunc())
				local z = tonumber(iterFunc())
				local position = Vector3.new(x, y, z)
				self:beginAnimateDragonComingToOpen(itemId, position)
			else
				self:cleanupAnimateDragonComingToOpen(itemId)
			end
		end
	)

	indicatorData.openCompleteTimeChangedConnect = inst:GetAttributeChangedSignal(Attributes.OPEN_COMPLETE_TIME):Connect(
		function()
			local completeTime = inst:GetAttribute(Attributes.OPEN_COMPLETE_TIME)
			if completeTime then
				self:beginAnimateOpen(itemId)
			else
				self:cleanupAnimateOpen(itemId)
			end
		end
	)

	indicatorData.animationCrystalOpenedChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_CRYSTAL_OPENED):Connect(
		function()
			local animationCrystalOpenedStr = inst:GetAttribute(Attributes.ANIMATION_CRYSTAL_OPENED)
			if animationCrystalOpenedStr then
				self:beginAnimateCrystalOpened(itemId)
			else
				self:cleanupAnimateCrystalOpened(itemId)
			end
		end
	)

	indicatorData.crystalClaimableConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_CRYSTAL_CLAIMABLE):Connect(
		function()
			local animationCrystalClaimableStr = inst:GetAttribute(Attributes.ANIMATION_CRYSTAL_CLAIMABLE)
			if animationCrystalClaimableStr then
				self:beginAnimateCrystalClaimable(itemId)
			else
				self:cleanupAnimateCrystalClaimable(itemId)
			end
		end
	)
	if inst:GetAttribute(Attributes.ANIMATION_CRYSTAL_CLAIMABLE) then
		self:beginAnimateCrystalClaimable(itemId)
	end

	indicatorData.animationClaimingChangedConnect = inst:GetAttributeChangedSignal(Attributes.ANIMATION_CLAIMING):Connect(
		function()
			local animationClaimingStr = inst:GetAttribute(Attributes.ANIMATION_CLAIMING)
			if animationClaimingStr then
				self:beginAnimateClaiming(itemId)
			else
				self:cleanupAnimateClaiming(itemId)
			end
		end
	)

end

function ClientCrystalManager.notifyRemoveInstance(self: ClientCrystalManager, inst: any)
	local itemId = inst:GetAttribute(Attributes.ITEM_ID)

	local indicatorData = self.indicatorMap[itemId]
	if not indicatorData then
		return
	end

	local animationDragonComingToOpenChangedConnect = indicatorData.animationDragonComingToOpenChangedConnect
	if animationDragonComingToOpenChangedConnect then
		animationDragonComingToOpenChangedConnect:Disconnect()
		indicatorData.animationDragonComingToOpenChangedConnect = nil
	end

	local openCompleteTimeChangedConnect = indicatorData.openCompleteTimeChangedConnect
	if openCompleteTimeChangedConnect then
		openCompleteTimeChangedConnect:Disconnect()
		indicatorData.openCompleteTimeChangedConnect = nil
	end

	local animationCrystalOpenedChangedConnect = indicatorData.animationCrystalOpenedChangedConnect
	if animationCrystalOpenedChangedConnect then
		animationCrystalOpenedChangedConnect:Disconnect()
		indicatorData.animationCrystalOpenedChangedConnect = nil
	end

	local animationClaimingChangedConnect = indicatorData.animationClaimingChangedConnect
	if animationClaimingChangedConnect then
		animationClaimingChangedConnect:Disconnect()
		indicatorData.animationClaimingChangedConnect = nil
	end

	self:cleanupAnimateDragonComingToOpen(itemId)
	self:cleanupAnimateOpen(itemId)
	self:cleanupAnimateCrystalOpened(itemId)
	self:cleanupAnimateClaiming(itemId)
	self:cleanupAnimateCrystalClaimable(itemId)

	self.indicatorMap[itemId] = nil
end

function ClientCrystalManager.getMapSize(self: ClientCrystalManager): number
	return utils.getTableSize(self.indicatorMap)
end

function ClientCrystalManager.init(self: ClientCrystalManager)

	collectionService:GetInstanceAddedSignal(Tags.CRYSTAL):Connect(
		function(inst)
			--print("new crystal exists", inst)
			self:notifyNewInstance(inst)
		end
	)

	collectionService:GetInstanceRemovedSignal(Tags.CRYSTAL):Connect(
		function(inst)
			--print("crystal no longer exists", inst)
			self:notifyRemoveInstance(inst)
		end
	)

	for _, inst in collectionService:GetTagged(Tags.CRYSTAL) do
		--print("existing crystal exists", inst)
		self:notifyNewInstance(inst)
	end

	local splendidDataFolder = player:WaitForChild("PlayerGui"):WaitForChild("SplendidData")
	local instantOpenCrystalDataFolder = splendidDataFolder:WaitForChild("InstantOpenCrystal")

	local instantOpenCrystalDatas: { InstantOpenCrystalData } = {}
	for _, inst in instantOpenCrystalDataFolder:GetChildren() do
		local instantOpenCrystalData: InstantOpenCrystalData = {
			robuxProductId = inst:GetAttribute(Attributes.PRODUCT_ID) :: number,
			durationSec = inst:GetAttribute(Attributes.DURATION) :: number,
		}
		table.insert(instantOpenCrystalDatas, instantOpenCrystalData)
	end

	self.instantOpenCrystalDatas = {}

	local countRemaining = #instantOpenCrystalDatas
	for _, instantOpenCrystalData in instantOpenCrystalDatas do
		task.defer(
			function()
				local isSuccess, productInfo = pcall(
					function()
						return marketplaceService:GetProductInfoAsync(instantOpenCrystalData.robuxProductId, Enum.InfoType.Product) :: any
					end
				)
				if isSuccess then
					--print("got marketplace info", productInfo)
					if productInfo.IsForSale then
						table.insert(self.instantOpenCrystalDatas,
							{
								robuxProductId = instantOpenCrystalData.robuxProductId,
								durationSec = instantOpenCrystalData.durationSec,
								robuxPrice = productInfo.PriceInRobux :: number,
							}
						)
					else
						print("instant crystal open product not for robux sale", instantOpenCrystalData.durationSec, productInfo)
					end
				end

				countRemaining -= 1
				--print("remaining crystal instant open robux lookups", countRemaining)

				if countRemaining == 0 then

					-- sort in decreasing time
					table.sort(self.instantOpenCrystalDatas,
						function(a: InstantOpenCrystalData, b: InstantOpenCrystalData)
							if a.durationSec > b.durationSec then
								return true
							end
							return false
						end
					)

					self.isRobuxReady = true
				end

			end
		)
	end
end

function ClientCrystalManager.new(): ClientCrystalManager
	local self = setmetatable({} :: ClientCrystalManagerFields, ClientCrystalManager)

	self.indicatorMap = {}
	self.instantOpenCrystalDatas = {}
	self.isRobuxReady = false

	return self
end

local singleton = ClientCrystalManager.new()

return singleton
