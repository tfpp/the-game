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
		"title": "Steadier gun viewmodels",
		"summary":
		"Generated guns no longer jitter in first person, and shots now fire from where you aim."
	},
	{
		"title": "Soccer ball physics",
		"summary":
		"The map's soccer ball rolls and bounces now — bump it with your body or shoot it."
	},
	{
		"title": "Wallet and health HUD",
		"summary": "Your money now shows in the bottom-right corner, above a proper health bar."
	},
	{
		"title": "Casino skylights",
		"summary":
		"Two skylights over the gaming floor let you see the daytime sky from the casino."
	},
	{
		"title": "UI refresh",
		"summary":
		"Key and button icons on the Controls page, menu icons, restyled sliders and click sounds."
	},
	{
		"title": "Elevator",
		"summary": "Call the lobby elevator to ding open onto a new back room, with friends in tow."
	},
	{
		"title": "The Gilded Lily casino",
		"summary":
		"Explore a faded 1964 casino with sunken gaming, eight slots, a petting zoo and an indoor ferry."
	},
	{
		"title": "AWP one-shots",
		"summary":
		"The AWP sniper rifle now deals damage like every other gun: a slow, lethal shot."
	},
	{
		"title": "Girl model option",
		"summary":
		"Pick a girl body model from the Esc menu's Character Model screen. Everyone sees your choice."
	},
	{
		"title": "Ferry helm",
		"summary":
		"Taking the ferry's wheel now plants you at its old-timey helm instead of wandering off."
	},
	{
		"title": "Settings menu",
		"summary":
		"Esc > Settings: rebind keys and controller buttons, tune look sensitivity and set volume."
	},
	{
		"title": "Gameplay sound effects",
		"summary":
		"Guns, hits and animal explosions now make sound. Pickups and inventory actions have audio cues."
	},
	{
		"title": "Exploding frogs",
		"summary":
		"Shoot frogs for a burst of flying pieces; they return after four seconds. Penguins face forward."
	},
	{
		"title": "Player skin tones",
		"summary": "Your player ID now determines a consistent skin tone for your avatar and hands."
	},
	{
		"title": "Backpacks and clothing",
		"summary":
		"Start in white underwear. Find clothing, manage your backpack and view your wallet with I."
	},
	{
		"title": "Blocky players",
		"summary":
		"Players now have blocky bodies with walking, running, jumping, and item-holding animations."
	},
	{
		"title": "Better items and grips",
		"summary":
		"Remodeled guns, banana and ball, with visible hands and proper first- and third-person grips."
	},
	{
		"title": "Frogs on the move",
		"summary":
		"Frogs have detailed bodies, varied sizes and hops, avoid obstacles, and flee nearby players."
	},
	{
		"title": "Frog makeover",
		"summary":
		"Frogs are now small blocky voxel frogs in proper frog-green tones, not blue blobs."
	},
	{
		"title": "Noclip for everyone",
		"summary":
		"Press V to toggle noclip. Switching control schemes no longer needs play time first."
	},
	{
		"title": "Kaaba",
		"summary": "A scaled-down Kaaba now stands in the northwest corner of the map."
	},
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
