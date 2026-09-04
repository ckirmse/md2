--!strict

local Validate = {}

local enums = require("@game/ReplicatedStorage/Shared/Enums")

local Types = require("./Types")
local islandManager: Types.IslandManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle
local itemManager: Types.ItemManager -- injected via initClass(deps); typed through Types.luau to avoid the require cycle

function Validate.isItemId(itemId: any): boolean
	if typeof(itemId) ~= "number" then
		return false
	end

	local item = itemManager:getItemById(itemId)
	if not item then
		return false
	end

	return true
end

function Validate.isNodeObjectId(objectId: any): boolean
	local node = islandManager:isNodeObjectId(objectId)
	if not node then
		print("cannot find client-sent node objectId", objectId)
		return false
	end

	return true
end

function Validate.isChestObjectId(objectId: any): boolean
	local node = islandManager:isChestObjectId(objectId)
	if not node then
		print("cannot find client-sent chest objectId", objectId)
		return false
	end

	return true
end

function Validate.isCritterObjectId(objectId: any): boolean
	local node = islandManager:isCritterObjectId(objectId)
	if not node then
		print("cannot find client-sent critter objectId", objectId)
		return false
	end

	return true
end

function Validate.isItemIdForPlayer(player: Player, itemId: any): boolean
	if not Validate.isItemId(itemId) then
		return false
	end

	-- isItemId above guarantees the item exists, so the cast keeps that guarantee visible
	local item = itemManager:getItemById(itemId) :: Types.Item

	if item:getUserId() ~= player.UserId then
		warn("item not owned by player from client-sent itemId", itemId, item:getUserId(), player.UserId)
		return false
	end

	return true
end

function Validate.isItemIdForOtherPlayer(player: Player, itemId: any): boolean
	if not Validate.isItemId(itemId) then
		return false
	end

	-- isItemId above guarantees the item exists, so the cast keeps that guarantee visible
	local item = itemManager:getItemById(itemId) :: Types.Item

	if item:getUserId() == player.UserId then
		warn("item not supposed to be owned by player from client-sent itemId", itemId, item:getUserId(), player.UserId)
		return false
	end

	return true
end

--[[
	prerequisite: itemId must have already been validated
]]
function Validate.isPlayerHoldingItemId(player: Player, itemId: number): boolean
	-- the documented prerequisite: itemId was already validated, so the item exists
	local item = itemManager:getItemById(itemId) :: Types.Item
	local part = item:getPart()
	if part.Parent == nil or part.Parent.Parent ~= player.Character then
		print("item not being held by player", itemId, player)
		return false
	end

	return true
end

function Validate.areItemIdsForPlayer(player: Player, itemIds: { any }): boolean
	for _, itemId in itemIds do
		if not Validate.isItemIdForPlayer(player, itemId) then
			return false
		end
	end

	return true
end

function Validate.areUniqueItemIds(itemIds: { any }): boolean
    local seen: { [any]: boolean } = {}

    -- Iterate over each number in the input array.
    for _, itemId in itemIds do
        if seen[itemId] then
            return false
        end

        seen[itemId] = true
    end

    return true
end

function Validate.isPlayerNameOnServer(playerName: any): boolean
	if not Validate.isString(playerName) then
		return false
	end

	for _, player in game:GetService("Players"):GetPlayers() do
		if player.Name == playerName then
			return true
		end
	end
	return false
end

function Validate.isBoolean(value: any): boolean
	return typeof(value) == "boolean"
end

function Validate.isNumber(value: any): boolean
	return typeof(value) == "number"
end

function Validate.isInteger(value: any): boolean
	return Validate.isNumber(value) and (value % 1) == 0
end

function Validate.isString(value: any): boolean
	return typeof(value) == "string"
end

function Validate.isTable(value: any): boolean
	return typeof(value) == "table"
end

function Validate.isTableBelowSize(value: any, size: number): boolean
	if not Validate.isTable(value) then
		return false
	end

	local count = 0
	for _, _ in value do
		count = count + 1
		if count > size then
			return false
		end
	end

	return true
end

function Validate.isArray(value: any): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, string.format("%s not array", tostring(value))
	end
	local count = 0
	for _, _ in value do
		count = count + 1
	end
	if count ~= #value then
		return false, string.format("%s not array", tostring(value))
	end
	return true, nil
end

function Validate.isTableShape(value: any, shape: any): (boolean, string?)
	if typeof(shape) ~= "table" then
		warn("validation data invalid: shape is not a table:", shape)
		return false, string.format("validation data invalid: non-table shape %s", tostring(shape))
	end

	if not Validate.isTable(value) then
		return false, string.format("%s not a table", value)
	end

	for key, shapeValue in shape do
		local isValid, err = Validate.isValueType(value[key], shapeValue)
		if not isValid then
			return false, string.format("table key %s invalid; %s", key, tostring(err))
		end
	end

	-- should look for if value has entries that were not in 'shape', and then return false

	for key, subValue in value do
		if not shape[key] then
			return false, string.format("table extra key %s", key)
		end
	end

	return true, nil
end

function Validate.isValueType(value: any, testType: any): (boolean, string?)
	if typeof(testType) == "table" then
		if testType.type then
			if testType.optional then
				if value == nil then
					return true, nil
				end
			end
			if testType.type == "table" then
				local shape = testType.shape
				if not shape then
					return true, nil
				end
				local isValid, err = Validate.isTableShape(value, shape)
				if not isValid then
					return false, string.format("%s not table shape %s; %s", tostring(value), tostring(testType), tostring(err))
				end
				if testType.nonempty then
					if not next(value) then
						return false, string.format("%s not non-empty table", tostring(value))
					end
				end
			elseif testType.type == "array" then
				if not Validate.isArray(value) then
					return false, string.format("%s not array", tostring(value))
				end
				if testType.nonempty then
					if #value == 0 then
						return false, string.format("%s not non-empty array", tostring(value))
					end
				end
				if testType.length then
					local length: number = testType.length
					if #value ~= length then
						return false, string.format("%s not fixed length %i array", tostring(value), length)
					end
				end
				local elementType = testType.elementType
				local valueCount: number = #value
				for i = 1, valueCount do
					if not Validate.isValueType(value[i], elementType) then
						return false, string.format("%s wrong type entry %i not %s", tostring(value), i, tostring(elementType))
					end

				end
			elseif testType.type == "enum" then
				local enumName = testType.name
				local enumTable = (enums :: any)[enumName]
				if not enumTable then
					return false, string.format("validation data invalid: unknown enum name %s", tostring(enumName))
				end
				if not enums.isValidValue(enumTable, value) then
					return false, string.format("%s not valid value of enum type %s", tostring(value), tostring(enumName))
				end
			else
				return Validate.isValueType(value, testType.type)
			end
		else
			local isValid, err = Validate.isTableShape(value, testType)
			if not isValid then
				return false, string.format("%s not table shape %s; %s", tostring(value), tostring(testType), tostring(err))
			end
		end
	elseif testType == "boolean" then
		if not Validate.isBoolean(value) then
			return false, string.format("%s not a boolean", tostring(value))
		end
	elseif testType == "number" then
		if not Validate.isNumber(value) then
			return false, string.format("%s not a number", tostring(value))
		end
	elseif testType == "nonnegativeNumber" then
		if not Validate.isNumber(value) then
			return false, string.format("%s not a number, no less nonnegativeNumber", tostring(value))
		end
		if value < 0 then
			return false, string.format("%s not a nonnegativeNumber", tostring(value))
		end
	elseif testType == "positiveNumber" then
		if not Validate.isNumber(value) then
			return false, string.format("%s not a number, no less positiveNumber", tostring(value))
		end
		if value <= 0 then
			return false, string.format("%s not a positiveNumber", tostring(value))
		end
	elseif testType == "integer" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer", tostring(value))
		end
	elseif testType == "nonnegativeInteger" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer, no less nonnegativeInteger", tostring(value))
		end
		if value < 0 then
			return false, string.format("%s not a nonnegativeInteger", tostring(value))
		end
	elseif testType == "positiveInteger" then
		if not Validate.isInteger(value) then
			return false, string.format("%s not an integer, no less positiveNumber", tostring(value))
		end
		if value <= 0 then
			return false, string.format("%s not a positiveInteger", tostring(value))
		end
	elseif testType == "string" then
		if not Validate.isString(value) then
			return false, string.format("%s not a string", tostring(value))
		end
	elseif testType == "table" then
		-- temporary as of 2026-may-2 until ObjectTypes all have table types defined
		if not Validate.isTable(value) then
			return false, string.format("%s not a table", tostring(value))
		end
	else
		warn("isValueType given unknown test type", testType)
		return false, string.format("validation data invalid: unknown test type %s", tostring(testType))
	end

	return true, nil
end

function Validate.initClass(deps: any)
	islandManager = deps.islandManager
	itemManager = deps.itemManager
end

return Validate