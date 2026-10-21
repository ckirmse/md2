--!strict

-- Plain colour shell on dragons and eggs that carry a weather trait, until real trait art exists. The server replicates
-- the traits as a JSON attribute; a low-frequency sweep keeps one Highlight per target (casters get rebuilt, so no event wiring).
local ClientTraitGlowManager = {}
ClientTraitGlowManager.__index = ClientTraitGlowManager

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local Tags = require("@game/ReplicatedStorage/Shared/Tags")

local clientShadowManager = require("./ClientShadowManager")
local ClientTicker = require("./ClientTicker")

local SWEEP_SEC = 0.5
local HIGHLIGHT_NAME = "TraitGlow"

local TRAIT_COLORS: { [number]: Color3 } = {
	[Enums.Trait.SCORCHED] = Color3.fromRGB(255, 120, 40),
	[Enums.Trait.BLOSSOMED] = Color3.fromRGB(255, 150, 200),
	[Enums.Trait.SOAKED] = Color3.fromRGB(70, 150, 255),
	[Enums.Trait.WINDSWEPT] = Color3.fromRGB(170, 230, 200),
	[Enums.Trait.CHARGED] = Color3.fromRGB(255, 235, 60),
	[Enums.Trait.STARLIT] = Color3.fromRGB(190, 140, 255),
}

type ClientTraitGlowManagerFields = {
	-- target -> the traits string its highlight was built from
	appliedTraits: { [Instance]: string },
}

export type ClientTraitGlowManager = typeof(setmetatable({} :: ClientTraitGlowManagerFields, ClientTraitGlowManager))

-- the model the player sees: the ghost model for a dragon, the egg itself otherwise
local function getTarget(inst: any): Instance?
	if inst:HasTag(Tags.SHADOW_DRAGON) then
		return clientShadowManager:getCaster(inst:GetAttribute(Attributes.ITEM_ID))
	end
	return inst
end

function ClientTraitGlowManager.removeGlow(self: ClientTraitGlowManager, target: Instance)
	self.appliedTraits[target] = nil
	local highlight = target:FindFirstChild(HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end
end

function ClientTraitGlowManager.applyGlow(self: ClientTraitGlowManager, target: Instance, traitsText: string)
	local highlight = target:FindFirstChild(HIGHLIGHT_NAME)
	if highlight and self.appliedTraits[target] == traitsText then
		return
	end

	local ok, traits: any = pcall(function()
		return HttpService:JSONDecode(traitsText)
	end)
	local color = if ok and type(traits) == "table" then TRAIT_COLORS[traits[#traits]] else nil
	if not color then
		return
	end

	local glow: Highlight
	if highlight then
		glow = highlight :: Highlight
	else
		glow = Instance.new("Highlight")
		glow.Name = HIGHLIGHT_NAME
		glow.FillTransparency = 0.6
		glow.OutlineTransparency = 0.2
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Adornee = target
		glow.Parent = target
	end

	glow.FillColor = color
	glow.OutlineColor = color
	self.appliedTraits[target] = traitsText
end

function ClientTraitGlowManager.sweep(self: ClientTraitGlowManager)
	for _, tag in { Tags.SHADOW_DRAGON, Tags.DRAGON_EGG } do
		for _, inst in CollectionService:GetTagged(tag) do
			if not inst:IsDescendantOf(workspace) then
				continue
			end
			local target = getTarget(inst)
			if not target then
				continue
			end
			local traitsText = inst:GetAttribute(Attributes.TRAITS)
			if type(traitsText) == "string" then
				self:applyGlow(target, traitsText)
			else
				self:removeGlow(target)
			end
		end
	end

	for target in self.appliedTraits do
		if not target:IsDescendantOf(workspace) then
			self.appliedTraits[target] = nil
		end
	end
end

function ClientTraitGlowManager.init(self: ClientTraitGlowManager)
	ClientTicker.every(SWEEP_SEC, function()
		self:sweep()
	end)
end

function ClientTraitGlowManager.new(): ClientTraitGlowManager
	return setmetatable({ appliedTraits = {} } :: ClientTraitGlowManagerFields, ClientTraitGlowManager)
end

local singleton = ClientTraitGlowManager.new()

return singleton
