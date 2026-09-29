class_name ChangelogEntries
## Player-facing list of shipped features, shown in the in-game changelog panel
## (features/changelog/changelog.gd).
##
## Whenever a new feature ships under `game/features/<name>/`, add one entry here in
## the same change (see AGENTS.md). Newest entries go at the top of the array.

## `title`: the feature's display name, unique across the list: released builds use it to
## find the release that added the entry (scripts/release_notes.sh), so don't rename one
## once it ships. `summary`: a one-line, player-facing description of what it does.
## Don't add a version; the build works it out from the release tags.
const ENTRIES: Array[Dictionary] = [
	{
		"title": "Baked hotel lighting and branching wings",
		"summary":
		"Explore six generated rooms with branching halls, soft lamp shadows and baked bounced light."
	},
	{
		"title": "Procedural floor plans on radar",
		"summary": "Generated rooms and hallways now appear on the radar as you explore."
	},
	{
		"title": "The hotel wing",
		"summary": "Visit the hotel wing from the south lobby; use its casino door to return."
	},
	{
		"title": "Sky through procedural windows",
		"summary": "Clear glazing and a clouded sky give generated rooms a view outside."
	},
	{
		"title": "Procedural room authoring",
		"summary":
		(
			"Build textured rooms with mouldings, eight-sided pillars, "
			+ "framed doors and windows from blueprints."
		)
	},
	{
		"title": "Doggy-door gnomes",
		"summary": "Gnomes pop out of wall doggy doors, roam, dodge you and can be shot.",
	},
	{
		"title": "Arcade attract mode",
		"summary": "Arcade cabinets idle on a title screen and load their game when you use them.",
	},
	{
		"title": "Prayer at the Kaaba",
		"summary": "Pray at the Kaaba with Use to stack blessings that improve your slot odds.",
	},
	{
		"title": "Casino patrons",
		"summary": "Gamblers stroll the casino floor; punch them silly and they ragdoll.",
	},
	{
		"title": "Steady casino textures",
		"summary": "Props no longer slide as you turn, and guns and gnomes show their colours.",
	},
	{
		"title": "Turkey Puncher computers",
		"summary": "Click arcade computer screens to play Super Turbo Turkey Puncher 3.",
	},
	{
		"title": "Developer console",
		"summary": "Press ~ for settings commands, autocomplete and sv_cheats to unlock noclip.",
	},
	{
		"title": "Boxing",
		"summary":
		"Empty-handed, click to jab or hold and release to power punch; knock dummies flat.",
	},
	{
		"title": "Ray Gun",
		"summary":
		"The Gun-O-Matic has a rare 1-in-30 chance to hand out the Ray Gun from Zombies.",
	},
	{
		"title": "Remembered leaderboard",
		"summary":
		"Offline players stay ranked; signed-in scores survive reconnects and server restarts.",
	},
	{
		"title": "Faster mobile",
		"summary": "Phones and tablets render fewer pixels and lights so the game runs smoother.",
	},
	{
		"title": "Modelled casino furniture and textured surfaces",
		"summary":
		(
			"Curved padded tables, contoured chairs and shaped patrons replace blocky salon props."
			+ " Clothing, leather, skin and trim now use small shared textures."
		),
	},
	{
		"title": "The old casino salon",
		"summary":
		(
			"Burgundy carpet, green card tables, formal patrons and an amber-lit bar."
			+ " Explore the upstairs gallery and the new slot-machine bank."
		),
	},
	{
		"title": "PS1 casino and lighter mobile rendering",
		"summary":
		(
			"Chunky props, crisp 128-pixel textures and warm matte finishes."
			+ " Mobile renders a lighter 3D scene with a sharp HUD."
		),
	},
	{
		"title": "Breaking news screen",
		"summary": "A screen over the casino floor scrolls the latest top headlines.",
	},
	{
		"title": "Gnome express tunnels",
		"summary":
		"Use any gnome hole to enter the tunnels, run at 4x speed and exit at any other hole."
	},
	{
		"title": "Flashlights",
		"summary":
		"Press F to toggle a flashlight that follows your aim and lights the way for everyone."
	},
	{
		"title": "Scavenging",
		"summary":
		"Search wrecked cars in the parking garage with Use for wallets, watches, cash and more."
	},
	{
		"title": "Casino material and model polish",
		"summary":
		(
			"Rich carpet, teal wallpaper and walnut with physical materials,"
			+ " detailed casino furniture, and realistic slot cabinets with rolling mechanical reels."
		)
	},
	{
		"title": "Open annex routes and desktop radar",
		"summary":
		(
			"Explore all ten annex rooms through cleared passages and solid floors."
			+ " Desktop players now have a top-right radar showing nearby rooms and players."
		)
	},
	{
		"title": "Adventure arcade room",
		"summary":
		(
			"A dedicated arcade room loads games only while you are inside,"
			+ " with smoother play and reliable positional sound."
		)
	},
	{
		"title": "Room doors",
		"summary":
		(
			"A lounge booth in the south lobby leads to a lounge and a wine cellar. Rooms"
			+ " behind doors only load while you're in them."
		)
	},
	{
		"title": "Adventure arcade",
		"summary":
		(
			"Five adventure demo cabinets: Monkey Island, Sam & Max, Fate of Atlantis,"
			+ " Passport to Adventure and a Day of the Tentacle display. Share play and"
			+ " autosaved progress, with sound fading to silence at 5 m. Play on the 3D"
			+ " screens and look around without leaving your turn. Enter to play; one button leaves."
		)
	},
	{
		"title": "Codex subscription usage",
		"summary":
		(
			"Discord's /usage command now shows both Claude and Codex subscription limits,"
			+ " with reset times and separate status for each provider."
		)
	},
	{
		"title": "Feature builder usage reports",
		"summary":
		(
			"PRs and Discord build updates now show the model, tokens used, and estimated"
			+ " API-equivalent cost, with readable PR-number links."
		)
	},
	{
		"title": "Choose your feature builder",
		"summary":
		(
			"Discord's /feature command now requires a harness choice: Claude or Codex."
			+ " Your choice also handles revisions and conflict fixes for that feature."
		)
	},
	{
		"title": "Wall sconces",
		"summary": "Brass 1960s wall sconces light the annex, glowing brightest at night."
	},
	{
		"title": "Mix-and-match creatures",
		"summary":
		(
			"Character Model (Esc menu) now picks a body, head and tail independently — a"
			+ " frog head or bird head, a lizard, fin or fluffy tail, on any body. Mix them"
			+ " into your own impossible creature."
		)
	},
	{
		"title": "Day/night cycle",
		"summary":
		(
			"Esc > Leaderboard ranks every connected player by money, jumps and kills, in"
			+ " three tabs."
		)
	},
	{
		"title": "Eight slot machines, eight stakes",
		"summary":
		(
			"Each of the eight slot machines now has its own buy-in, from $1 up to"
			+ " $1,000,000,000, shown on its cabinet and in the interaction prompt. Prizes"
			+ " scale with the buy-in, so every machine keeps the same 80% return."
		)
	},
	{
		"title": "One weapon at a time",
		"summary":
		(
			"Equipping a gun now holsters whatever else you had out. A strip at the bottom of"
			+ " the screen shows every weapon slot (1-8, 9 for the gun machine) and which one's"
			+ " active. Scroll now cycles weapon slots instead of also jumping."
		)
	},
	{
		"title": "Poverty flies",
		"summary":
		"Players ranked in the poorest 80% by wallet balance now have a swarm of flies buzzing overhead."
	},
	{
		"title": "Bouncier frogs",
		"summary":
		"Frogs jump twice as high, bounce off walls, ribbit when hit, and there are twice as many."
	},
	{
		"title": "Dev elevator",
		"summary":
		(
			"A hazard-striped debug warp pad (noclip to find it) instantly sends you to the"
			+ " parking garage for testing — internal, not part of the game proper."
		)
	},
	{
		"title": "Parking garage",
		"summary":
		(
			"A dark three-story parking structure outside the casino — take the staff door"
			+ " near the trampolines. Ramps and a stairwell connect all three levels."
		)
	},
	{
		"title": "Wandering gnomes",
		"summary":
		"Gnome burrows hug the outer walls, dash to far-off holes along real routed paths, and dodge you."
	},
	{
		"title": "Shooting gallery",
		"summary":
		"A Doom-style arena of killable, gory humanoid dummies. Every weapon can now hurt animals too."
	},
	{
		"title": "Steadier gun viewmodels",
		"summary":
		(
			"Generated guns no longer jitter in first person, shots fire from where you aim and"
			+ " stay visible, and each gunshot now plays from the gun that fired it."
		)
	},
	{
		"title": "New fonts",
		"summary": "Cleaner text everywhere, with bolder headings and a sharper HUD."
	},
	{
		"title": "Versioned release notes",
		"summary": "Release notes group what's new by version, starting from v0.6.0."
	},
	{
		"title": "Game settings",
		"summary":
		"Esc > Settings > Game: tune jump height and frog hop rate for everyone in the world."
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
