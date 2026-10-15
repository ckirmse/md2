--!strict
-- Shared client UI style constants; one place for the visual language every
-- manager-built GUI reuses (disabled/maxed button gray, HUD slide timing).
local ClientUiStyle = {}

ClientUiStyle.DISABLED_BUTTON_COLOR = Color3.fromRGB(146, 146, 146)
ClientUiStyle.DISABLED_BUTTON_GRADIENT = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(145, 145, 145))

ClientUiStyle.HUD_TWEEN_SEC = 0.2

return ClientUiStyle
