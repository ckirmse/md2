--!strict

local DataType = require("./DataType")
local super = DataType

local Types = require("./Types")

local ObjectType = {}
ObjectType.__index = setmetatable(ObjectType, super)

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local utils = require("@game/ReplicatedStorage/Shared/utils")


export type ObjectTypeFields = Types.ObjectTypeFields
export type ObjectType = Types.ObjectType

function ObjectType.validateInstances(self: ObjectType): boolean
	local templatePath = self:getRawData().templatePath
	local template = utils.getGameAssetPathReference(templatePath)

	self:setTemplate(template)

	-- a missing template crashed here before typing too, so the cast keeps that behavior
	local templateInst = template :: Instance
	if templateInst:IsA("Model") then
		if not templateInst.PrimaryPart then
			warn("every model must have a primary part. Missing for", self.name, templateInst.Name)
			return false
		end
	end

	return true
end

function ObjectType.processInstances(self: ObjectType)
	super.processInstances(self)

	local template = self.template :: Instance

	local i = 1

	if template:IsA("BasePart") then
		template:SetAttribute(Attributes.PART_INDEX, i)
		i = i + 1
	end

	for _, inst in template:GetDescendants() do
		if not inst:IsA("BasePart") then
			continue
		end
		inst:SetAttribute(Attributes.PART_INDEX, i)
		i = i + 1
	end

end

function ObjectType.setTemplate(self: ObjectType, template: Instance?)
	self.template = template
end

function ObjectType.getTemplate(self: ObjectType): Instance?
	return self.template
end

function ObjectType.new(): ObjectType
	local self = (setmetatable(DataType.new(), ObjectType) :: any) :: ObjectType

	return self
end

return ObjectType
