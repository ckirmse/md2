--!strict

-- Shared tile plumbing for the playtime reward grid: the three Studio-authored tile templates (locked, ready,
-- claimed), clearing and cloning grid tiles, and filling a tile's title and picture from a reward the server sent.
local RewardTileUi = {}

local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local enums = require("@game/ReplicatedStorage/Shared/Enums")
local ItemIcons = require("@game/ReplicatedStorage/Shared/ItemIcons")
local utils = require("@game/ReplicatedStorage/Shared/utils")

RewardTileUi.TILE_STATE_LOCKED = 1
RewardTileUi.TILE_STATE_READY = 2
RewardTileUi.TILE_STATE_CLAIMED = 3

-- the tile templates are authored in Studio, so they are typed only as GuiObjects
export type TileTemplates = {
	locked: GuiObject,
	ready: GuiObject,
	claimed: GuiObject,
}

-- the part of a reward from the server that decides what a tile shows (see PlaytimeRewardManager)
export type RewardContent = {
	kind: number,
	itemName: string?,
	displayName: string?,
	skipSec: number?,
	coinAmount: number?,
	label: string?,
	rarity: number?,
}

function RewardTileUi.findTemplates(tileGrid: Instance): TileTemplates
	local templates = {
		locked = tileGrid:WaitForChild("TileTemplate") :: GuiObject,
		ready = tileGrid:WaitForChild("TileTemplateReady") :: GuiObject,
		claimed = tileGrid:WaitForChild("TileTemplateClaimed") :: GuiObject,
	}
	templates.locked.Visible = false
	templates.ready.Visible = false
	templates.claimed.Visible = false

	return templates
end

function RewardTileUi.getTemplateForState(templates: TileTemplates, tileState: number): GuiObject
	if tileState == RewardTileUi.TILE_STATE_READY then
		return templates.ready
	elseif tileState == RewardTileUi.TILE_STATE_CLAIMED then
		return templates.claimed
	end

	return templates.locked
end

function RewardTileUi.clearTiles(tileGrid: Instance, templates: TileTemplates)
	for _, child in tileGrid:GetChildren() do
		if child:IsA("GuiObject") and child ~= templates.locked and child ~= templates.ready and child ~= templates.claimed then
			child:Destroy()
		end
	end
end

-- whole hours as "2h", otherwise minutes (rounded), and seconds only below a minute
local function formatSkipTitle(skipSec: number): string
	if skipSec >= 3600 and skipSec % 3600 == 0 then
		return string.format("%dh Time Skip", skipSec // 3600)
	elseif skipSec >= 60 then
		return string.format("%dm Time Skip", math.floor(skipSec / 60 + 0.5))
	end

	return string.format("%ds Time Skip", skipSec)
end

function RewardTileUi.getTileTitle(reward: RewardContent, tileState: number?): string
	if reward.kind == enums.PlaytimeRewardKind.COINS then
		return if reward.coinAmount then `{utils.formatLargePositiveInteger(reward.coinAmount)} Coins` else "Coins"
	elseif reward.kind == enums.PlaytimeRewardKind.TIME_SKIP then
		return formatSkipTitle(reward.skipSec or 0)
	end

	-- a claimed tile keeps the template's gray text; a rarity colour tag would override it
	local name = reward.displayName or reward.itemName or reward.label or "???"
	if reward.rarity and tileState ~= RewardTileUi.TILE_STATE_CLAIMED then
		return utils.getColoredTextForRarity(name, reward.rarity)
	end

	return name
end

-- fills the tile's Title text and its pictures. A known item shows its icon on the template's Preview, or on its Icon
-- when the template has no Preview. Coin and time skip rewards, and a random or loot table reward that is still
-- hidden, use the picture authored as an attribute on the Icon (CoinImage, ClockImage, MysteryImage); anything else
-- keeps the Icon as authored
function RewardTileUi.fillTileContent(tile: GuiObject, reward: RewardContent, tileState: number?)
	local titleLabel = tile:FindFirstChild("Title") :: TextLabel?
	if titleLabel then
		titleLabel.RichText = true
		titleLabel.Text = RewardTileUi.getTileTitle(reward, tileState)
	end

	local preview = tile:FindFirstChild("Preview") :: ImageLabel?
	local icon = tile:FindFirstChild("Icon") :: ImageLabel?

	local itemIcon = if reward.itemName then ItemIcons.getItemIconAssetId(reward.itemName) else nil
	if preview then
		if itemIcon then
			preview.Image = itemIcon
		end
		preview.Visible = itemIcon ~= nil
	end

	if icon then
		local isIconShown = not (preview and preview.Visible)
		icon.Visible = isIconShown
		if not isIconShown then
			return
		end

		local coinIcon = icon:GetAttribute(Attributes.COIN_IMAGE)
		local clockIcon = icon:GetAttribute(Attributes.CLOCK_IMAGE)
		local mysteryIcon = icon:GetAttribute(Attributes.MYSTERY_IMAGE)
		if itemIcon then
			icon.Image = itemIcon
		elseif reward.kind == enums.PlaytimeRewardKind.TIME_SKIP and typeof(clockIcon) == "string" then
			icon.Image = clockIcon
		elseif reward.kind == enums.PlaytimeRewardKind.COINS and typeof(coinIcon) == "string" then
			icon.Image = coinIcon
		elseif reward.itemName == nil and reward.label ~= nil and typeof(mysteryIcon) == "string" then
			icon.Image = mysteryIcon
		end
	end
end

-- the ready template has a visual "CLAIM!" TextLabel that shares the button's name, so pick the button
function RewardTileUi.findClaimButton(tile: GuiObject): TextButton?
	for _, child in tile:GetChildren() do
		if child.Name == "Claim" and child:IsA("TextButton") then
			return child
		end
	end

	return nil
end

return RewardTileUi
