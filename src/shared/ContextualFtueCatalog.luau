--!strict

local ContextualFtueCatalog = {}

-- Each entry:
--   id             Contextual FTUE unique id
--   sortOrder      Sorting order in which the entry will be visible in catalogue or a separate UI.
--   title          Contextual FTUE title.
--   bodyText       Contextual FTUE description.
--   imageAssetId   Contextual FTUE image asset url uploaded on Roblox

export type Entry = {
	id: string,
	sortOrder: number,
	title: string,
	bodyText: string,
	imageAssetId: string,
}

local entries: { Entry } = {
	{
		id = "unlockElement",
		sortOrder = 1,
		title = "New Element Unlocked!",
		bodyText = "You can now buy, fuse, and earn XP with items of this Element.",
		imageAssetId = "rbxassetid://123172994636145",
	},
	{
		id = "unlockAbility",
		sortOrder = 2,
		title = "Skill Unlocked!",
		bodyText = "Visit the Dragon Master floating next to the Buy Store to learn more.",
		imageAssetId = "rbxassetid://95574032198655",
	},
	{
		id = "unlockFuseAll",
		sortOrder = 3,
		title = "Fuse All Unlocked!",
		bodyText = "Toggle it on in the upper left corner to automatically fuse all matching items.",
		imageAssetId = "rbxassetid://90004676252047",
	},
	{
		id = "flyingUnlocked",
		sortOrder = 4,
		title = "Flying Unlocked!",
		bodyText = "Jump on any Dragon level 4 or higher to ride it, then explore the Void to collect new items!",
		imageAssetId = "rbxassetid://70440981093991",
	},
	{
		id = "receiveCrystal",
		sortOrder = 5,
		title = "Crystal Found!",
		bodyText = "Fuse Crystals to higher levels and command your Dragons to activate them for rewards that scale with level.",
		imageAssetId = "rbxassetid://135228938752423",
	},
	{
		id = "vanityUnlocked",
		sortOrder = 6,
		title = "Vanity Unlocked!",
		bodyText = "Fuse Keys to open Chests in the Void and earn Blueprints, then bring them to the Gnome outside your plot to equip.",
		imageAssetId = "rbxassetid://77210834931271",
	},
}

local entriesById: { [string]: Entry } = {}
for _, entry in entries do
	entriesById[entry.id] = entry
end

function ContextualFtueCatalog.getEntryById(id: string): Entry?
	return entriesById[id]
end

function ContextualFtueCatalog.getAllEntries(): { Entry }
	return entries
end

return ContextualFtueCatalog
