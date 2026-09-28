class_name ChangelogEntries
## Player-facing list of shipped features, shown in the in-game changelog panel
## (features/changelog/changelog.gd).
##
## Whenever a new feature ships under `game/features/<name>/`, add one entry here in
## the same change (see AGENTS.md). Newest entries go at the top of the array.

## `title`: the feature's display name. `summary`: a one-line, player-facing
## description of what it does.
const ENTRIES: Array[Dictionary] = [
	{
		"title": "Trampolines",
		"summary": "Trampoline squares on the map launch you into the air when you stand on them."
	},
	{
		"title": "Killable penguin",
		"summary": "The penguin can now be shot with any weapon — she explodes and waddles back."
	},
	{
		"title": "Update screen",
		"summary":
		"Web client shows an Updating… screen during a deploy instead of flashing reloads."
	},
	{
		"title": "Combat",
		"summary": "Weapons can now kill — take damage and respawn once your health runs out."
	},
	{
		"title": "Item drops & new guns",
		"summary":
		"Drop any held item with G; thrown items bounce based on weight. Added an SMG and a shotgun."
	},
	{"title": "Esc menu", "summary": "Controls and Release notes moved into the Esc menu."},
	{"title": "Coins", "summary": "Coins scattered around the map now add $10 to your real money."},
	{"title": "AWP", "summary": "The AWP in the middle of the map is now a pickup."},
	{
		"title": "Pond",
		"summary": "A pond you can wade through; the water is just for looks, so it's safe."
	},
	{"title": "Suicide", "summary": "Type /suicide in chat to respawn."},
	{"title": "Penguin", "summary": "A penguin waddles around the map."},
	{"title": "Slot machine", "summary": "Play the slot machine for a payout."},
	{"title": "NYC ferry", "summary": "A ferry cruises across the water."},
	{"title": "Frogs", "summary": "Frogs hop around the world."},
	{"title": "Chat", "summary": "Press Enter to open a Source-style chat line."},
	{"title": "Character memory", "summary": "The world remembers where you logged off."},
]
