--!strict

local CodeManager = {}
CodeManager.__index = CodeManager

local Types = require("./Types")
local gameController: Types.GameController -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager = require("./ItemManager")

local enums = require("@game/ReplicatedStorage/Shared/Enums")

local analyticsManager = require("./AnalyticsManager")

local codeData = require("@game/ServerScriptService/GameData/Control/Codes")

type CodeManagerFields = {}

export type CodeManager = typeof(setmetatable({} :: CodeManagerFields, CodeManager))

function CodeManager.getMaxCodeLength(self: CodeManager): number
	return 20
end

function CodeManager.tryApplyCode(self: CodeManager, player: Player, code: string)
	print("player", player, "trying to apply code", code)

	local playerData = gameController:getPlayerData(player)
	if not playerData then
		return
	end

	local codeEntry: any
	local codeEntries = codeData.codes
	for _, thisCodeEntry in codeEntries do
		if thisCodeEntry.codeName ~= code then
			continue
		end
		codeEntry = thisCodeEntry
		break
	end

	if not codeEntry then
		gameController:sendSystemMessageToPlayer(player, "Unknown code cannot be applied")
		analyticsManager:logEvent(player, analyticsManager.Events.CodeUnknown,
			{
				code = code,
			}
		)
		return
	end

	local now = workspace:GetServerTimeNow()
	if now < codeEntry.beginTime then
		gameController:sendSystemMessageToPlayer(player, "Unknown code cannot be applied")
		return
	end

	if codeEntry.endTime then
		if now > codeEntry.endTime then
			gameController:sendSystemMessageToPlayer(player, "Sorry, that code has already expired")
			analyticsManager:logEvent(player, analyticsManager.Events.CodeExpired,
				{
					code = code,
				}
			)
			return
		end
	end

	if playerData:hasCodeRedeemed(code) then
		gameController:sendSystemMessageToPlayer(player, "Sorry, you have already redeemed that code")
		analyticsManager:logEvent(player, analyticsManager.Events.CodeDuplicate,
			{
				code = code,
			}
		)
		return
	end

	if codeEntry.redeemMessage then
		gameController:sendSystemMessageToPlayer(player, codeEntry.redeemMessage)
	end

	for _, itemDescriptor in codeEntry.itemDescriptors do
		local item = itemManager:createItem(itemDescriptor.itemName, player.UserId)
		if not item then
			warn("failed to create code item", itemDescriptor.itemName)
			continue
		end
		if itemDescriptor.mutation and itemDescriptor.mutation ~= enums.Mutations.NORMAL then
			-- a mutation in the descriptor implies a mutation-capable (MItem) item
			local mutationItem = item :: Types.MItem
			mutationItem:setMutation(itemDescriptor.mutation)
		end

		playerData:notifyItemReceived(item)

		analyticsManager:logEvent(player, analyticsManager.Events.GainItem,
			{
				objectName = item:getItemName(),
				primaryElement = enums.getPublicName(enums.PrimaryElements, item:getItemData().primaryElement),
				rarity = enums.getPublicName(enums.Rarity, item:getItemData().rarity),
				itemType = item:getType(),
				acquisitionSource = "code",
			}
		)

		local visibleName = item:getVisibleName()
		item:putInBackpack()
		-- note: item may have been destroyed if it entered a stack

		gameController:sendSystemMessageToPlayer(player, string.format("You received a %s!", visibleName))
	end

	playerData:addCodeRedeemed(code)

	analyticsManager:logEvent(player, analyticsManager.Events.CodeRedeemed,
		{
			code = code,
		}
	)
end

function CodeManager.init(self: CodeManager)

end

function CodeManager.new(): CodeManager
	local self: CodeManager = setmetatable({} :: CodeManagerFields, CodeManager)

	return self
end

function CodeManager.initClass(deps: any)
	gameController = deps.gameController
end

local singleton = CodeManager.new()

return singleton
