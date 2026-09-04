--!strict

local ObjectType = require("./ObjectType")
local super = ObjectType

local Types = require("./Types")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")

local ShadowDragonObjectType = {}
ShadowDragonObjectType.__index = setmetatable(ShadowDragonObjectType, super)


export type ShadowDragonObjectType = Types.ShadowDragonObjectType

function ShadowDragonObjectType.validateInstances(self: ShadowDragonObjectType): boolean
	--print("dragon validating obj")

	if not super.validateInstances(self) then
		return false
	end

	-- we validate caster too

	local casterPath = self:getRawData().casterPath
	-- a missing caster crashed here before typing too, so the cast keeps that behavior
	local caster = utils.getGameAssetPathReference(casterPath) :: Instance

	if self:getRawData().mixins.ride then
		local seatLocation: Instance? = nil
		for _, descendant in caster:GetDescendants() do
			--print("have", inst, inst:GetAttribute(Attributes.SEAT_LOCATION))
			if not descendant:GetAttribute(Attributes.SEAT_LOCATION) then
				continue
			end

			seatLocation = descendant
			break
		end

		if not seatLocation then
			warn("ridable dragon missing a SeatLocation", self:getRawData().name)
			return false
		end

		local trail = utils.findFirstDescendant(caster, "Trail")
		if not trail then
			warn("ridable dragon missing a Trail", self:getRawData().name)
			return false
		end
	end

	return true
end

function ShadowDragonObjectType.processInstances(self: ShadowDragonObjectType)
	-- all shadow objects use a single base template instance, but then we add a child so we need to make a unique copy here
	local template = (self:getTemplate() :: Instance):Clone()
	self:setTemplate(template)

	super.processInstances(self)

	template.Name = "Shadow"

	-- copy Hold from the caster to the main template

	local casterPath = self:getRawData().casterPath
	local caster = utils.getGameAssetPathReference(casterPath) :: Instance

	local hold = utils.findFirstDescendant(caster, "Hold")
	if hold then
		hold:Clone().Parent = template
	end

end

function ShadowDragonObjectType.addDataFromInstances(self: ShadowDragonObjectType)
	-- we add data about caster head size for better placement

	local casterPath = self:getRawData().casterPath
	-- casters are models with a primary part; a missing one crashed here before typing too
	local caster = utils.getGameAssetPathReference(casterPath) :: Model

	local head = caster.PrimaryPart :: BasePart

	self.data.distanceToTipOfNose = head.Size.Z / 2

	-- we get rough offset from primary part to seatLocation

	if self:getRawData().mixins.ride then
		local seatLocation: Instance? = nil
		for _, descendant in caster:GetDescendants() do
			--print("have", inst, inst:GetAttribute(Attributes.SEAT_LOCATION))
			if not descendant:GetAttribute(Attributes.SEAT_LOCATION) then
				continue
			end

			seatLocation = descendant
			break
		end

		local seatOffset = caster:GetPivot():PointToObjectSpace((seatLocation :: any).Position)
		--print("seatOffset is", seatOffset)
		self.data.seatOffset = seatOffset
	end

end

function ShadowDragonObjectType.new(): ShadowDragonObjectType
	local self = (setmetatable(ObjectType.new(), ShadowDragonObjectType) :: any) :: ShadowDragonObjectType

	self.type = "shadowDragon"

	self.dataTableShape = {
		type = "string",
		name = "string",
		displayName = "string",
		templatePath = "string",
		casterPath = "string",
		mutationSurfaceAppearanceName = "string",
		fireballPath = "string",
		rarity = {
			type = "enum",
			name = "Rarity",
		},
		primaryElement = {
			type = "enum",
			name = "PrimaryElements",
		},
		sortPriority = "integer",
		shouldCollideInWorkspace = {
			type = "enum",
			name = "CollideInWorkspace",
		},
		boardSpacing = "nonnegativeNumber",
		capacityCost = "nonnegativeNumber",
		level = "nonnegativeInteger",
		mixins = "table", -- should have more detailed type here
		eat = {
			xpMultiplier = "nonnegativeNumber",
			gemMultiplier = "nonnegativeNumber",
			audioPitchShift = "nonnegativeNumber",
		},
		movement = {
			minRadius = "nonnegativeNumber",
			baseFlapPeriod = "positiveNumber",
			baseFlapAmplitude = "nonnegativeNumber",
		},
		idle = {
			minHeight = "nonnegativeNumber",
			maxHeight = "nonnegativeNumber",
			pulsePeriodSec = "nonnegativeNumber",
			pulseAmplitudePlayerNear = {
				type = "nonnegativeNumber",
				optional = true,
			},
			pulseAmplitudePlayerFar = "nonnegativeNumber",
		},

		open = {
			type = {
				distance = "nonnegativeNumber",
			},
			optional = true,
		},
		buy = {
			type = {
				description = "string",
				minElementLevel = "nonnegativeInteger",
				unlockElement = {
					type = "enum",
					name = "PrimaryElements",
					optional = true,
				},
				category = {
					type = "enum",
					name = "ShopCategory",
					optional = true,
				},
				coins = "nonnegativeInteger",
				stock = {
					type = "array",
					elementType = {
						count = "nonnegativeInteger",
						percent = "nonnegativeNumber",
					},
				},
				cameraPosition = {
					type = "array",
					length = 3,
					elementType = "number",
				},
				robuxProductId = "nonnegativeInteger",
				robuxCount = "positiveInteger", -- how many of this item the player gets if they buy this with robux
			},
			optional = true,
		},

		indexCameraPosition = {
			type = "array",
			length = 3,
			elementType = "number",
			optional = true,
		},
	}


	return self
end

return ShadowDragonObjectType
