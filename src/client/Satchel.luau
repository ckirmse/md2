--!strict

-- thin wrapper around the vendored Satchel library (out of scope per CLAUDE.md); the
-- library crosses this boundary untyped
local Satchel: any = (require :: any)(script.Parent.Libs.Satchel)

--[[
	This Source Code Form is subject to the terms of the Mozilla Public
	License, v. 2.0. If a copy of the MPL was not distributed with this
	file, You can obtain one at http://mozilla.org/MPL/2.0/.
]]

--[[
	By using Satchel, you agree to provide attribution in one of the following ways:
		1. Keep the Attribution script unmodified and enabled
		2. Provide credit in your experience description by name (Satchel) and creator (@WinnersTakesAll)
		3. Have a DevForum topic linked in your experience description, crediting with the above

	For questions or exceptions to the attribution terms, reach out through the social links:
		https://create.roblox.com/store/asset/13947506401

	Thank you for supporting Satchel.
]]

local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	print("💼 Running Satchel v1.4.1 by @WinnersTakesAll")
end

---
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- the RemoteEvents children only exist in Studio, so they are untyped here
local RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")

Satchel:GetSlotFilledEvent().Event:Connect(
	function(index: number, tool: Instance)
		--print("event fired slot filled", index, tool)
		local itemId = tool:GetAttribute(Attributes.ITEM_ID)
		RemoteEvents.TrySetBackpackIndex:FireServer(itemId, index)
	end
)

return Satchel
