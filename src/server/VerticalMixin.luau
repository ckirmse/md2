--!strict

local VerticalMixin = {}
VerticalMixin.__index = VerticalMixin


local ALIGN_ORIENTATION_NAME = "VerticalMixinAlignOrientation"

type VerticalMixinFields = {}

export type VerticalMixin = typeof(setmetatable({} :: VerticalMixinFields, VerticalMixin))

function VerticalMixin.notifyItemCreated(self: VerticalMixin, item: any)
	local obj = item:getObj()

	--print("new vertical item created", obj, item:getUserId())

	local part = item:getPart()

	local attachment0 = Instance.new("Attachment")
	attachment0.Axis = Vector3.yAxis
	attachment0.Parent = part
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = ALIGN_ORIENTATION_NAME
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attachment0
	alignOrientation.AlignType = Enum.AlignType.PrimaryAxisParallel
	alignOrientation.PrimaryAxis = Vector3.yAxis
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxAngularVelocity = 100
	alignOrientation.MaxTorque = 10000000
	alignOrientation.Responsiveness = 20
	alignOrientation.Parent = part

	obj:GetPropertyChangedSignal("Parent"):Connect(
		function()
			if obj.Parent == workspace then
				alignOrientation.Enabled = true
			else
				alignOrientation.Enabled = false
			end
		end
	)

end

function VerticalMixin.notifyItemCloned(self: VerticalMixin, item: any)
	self:notifyItemCreated(item)
end

function VerticalMixin.new()
	local self = setmetatable({}, VerticalMixin)

	return self
end

local singleton = VerticalMixin.new()

return singleton
