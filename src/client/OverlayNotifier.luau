--!strict

-- default no-op implementation of the Types.OverlayNotifier protocol; kept as documentation
-- of the observer interface OverlayTracker calls (nothing requires this module today)
local OverlayNotifier = {}
OverlayNotifier.__index = OverlayNotifier

local Types = require("./Types")

export type OverlayNotifier = typeof(setmetatable({}, OverlayNotifier))

function OverlayNotifier.notifyBeginOverlay(self: OverlayNotifier, overlay: Types.Overlay, hudElements: { number })

end

function OverlayNotifier.notifyEndOverlay(self: OverlayNotifier, overlay: Types.Overlay, hudElements: { number })

end

function OverlayNotifier.new(): OverlayNotifier
	local self = setmetatable({}, OverlayNotifier)

	return self
end

local singleton = OverlayNotifier.new()

return singleton
