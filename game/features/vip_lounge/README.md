# The Mirror Club

An enclosed lounge recessed behind the Golden Crown's east wall, at x 24–32,
y 5–8.75, z -12–12. Its deck has no overhang into the main casino floor. The
north/south ends, outer wall, floor and ceiling are saved, editable GridMaps using
the casino's existing MeshLibrary. A full-height outer shell encloses the recess;
the ceiling has its own roof collision. The main casino's matching upper east
wall panels are replaced by the shared, sealed one-way pane at x 24. The casino
owns this window so standalone previews retain a closed hull. Two bounded amber
lights bring the casino's authored light
count to 32; no new shadow lights or large textures are introduced. Furniture,
bar, stools, glasses and evening guests reuse existing native assets.

## Discovery and access

An unmarked mirror at **(23.7, 1.3, -15)** on the east promenade admits players
with an existing wallet balance of **$2,000** (200,000 cents). Entry is free.
The small nearby inscription hints at the entrance. A validated use teleports
only the requesting player's owner, with a private chime, fade and welcome.
The exit works at any balance. Falling below $2,000 does not end a current visit;
leaving the room, disconnecting or changing sessions does. A three-second arrival
hold accommodates movement replication after the teleport.

GPS reveals the destination after discovery and uses the existing `GarageDoor`
portal routing contract. Upstairs stations join the local interaction/GPS object
catalog only after discovery. The unique door leaf inherits GarageDoor's CSG;
room architecture uses GridMaps. The inherited legacy RPC delegates to the same
NetworkedInteraction validator, so it cannot bypass eligibility.

The west-facing pane is opaque chrome from the casino and invisible from the VIP
side, with a physical barrier. It uses no screen-buffer sampling, which could expose
guests drawn behind the window. The finish is reflective metal rather than a live
planar reflection. A rendered magenta-marker probe checks both viewing directions.
The entire area lies inside the existing Golden Crown combat-free volume.

## Hosts and services

Scarlett (28), Jade (30), and Valentina (29) are adult evening guests using
CompanionModel's dress/hair API and the shared avatar idle pose. Conversations
and menus are optional, private to the requesting player, playful and non-explicit.
Returning visits use alternate dialogue.

| Service | Behavior |
| --- | --- |
| Luck Cocktail | Free; +500% luck for 300 seconds, 1,800-second cooldown. Exactly 6× private-table win chance: 4% → 24%, with losses still possible. Also multiplies rare gift chance by six. |
| Golden Hour | Free; doubles **lounge** XP for 600 seconds, 1,800-second cooldown. Does not add a global RPG level system. |
| Velvet Reserve | Free; raises rare daily glass chance from 5% to 20% for 600 seconds, 1,800-second cooldown. Combined gift chance caps at 100%. |
| Private Triple Match | Two private tables; stakes $100/$250/$500. Three matching symbols pay the existing five-symbol slot prizes, 10×/15×/20×/25×/30×. |
| Daily mystery gift | $50 plus a collectible glass, once per UTC day. Four glasses include a rare Golden Crown goblet. |
| Secret invitation | Talk to all three hosts, settle a private-table round, and discover the crown by the window. One $100 reward, House Favorite title, lounge XP and a gold-shirt/midnight-trousers outfit. |

Same drinks cannot stack. Different drinks have independent cooldowns and their
specified effects combine. Jade's three Whisper Menu orders now collect ordinary
inventory items (`luck_cocktail`, `golden_hour`, `velvet_reserve`). A full/loading
inventory denies the order without spending its cooldown. Ordering starts the
30-minute service cooldown; finishing the three-second drink starts the boost.
Equip a stored drink through Inventory, then use the existing primary action
(left click / controller right shoulder / touch FIRE). Drinks can be stowed,
dropped, picked up, shared and saved by the normal inventory system. The benefit
belongs to the consumer, including outside the lounge, and still applies only to
the existing lounge activities. An active matching boost denies drinking without
spending the item. Death/session interruption grants no boost. There is one use
per glass. The HUD displays remaining boost time and a lounge-only
VIP title. The Luck Cocktail also gives a cosmetic gold ring; it never changes
gameplay locally. Clothing is collected once through the existing Hand inventory;
full/loading inventories retain the claim. Glasses are a personal collection in
the lounge menu, not holdable inventory items. An original eight-second chord/bass
loop plays quietly for guests through the existing GameSFX volume/mute controls.

### Held drink models

The editable view scenes live in `items/`. They reuse the existing authored,
UV-mapped casino cocktail glass and hotel drinking-glass meshes and their approved
small textures, with faceted liquid surfaces and garnish meshes. Luck is a short
green stemmed cocktail with lime, Golden Hour an amber tumbler with orange, and
Velvet Reserve a tall burgundy martini with an olive and cocktail pick. No new
texture artwork, imported dependencies or per-item lights are required. Glasses
are 17–23 cm high; grip-centered origins and lip `Mouth` markers support existing
first-person and remote drinking animation. Ground clearance matches each base.
Native mesh/primitive resources remain reusable by pickup and inventory icons.

The holdables `ItemDefinition.consumption_group` provides an optional feature-owned
effect handler. `ConsumableUse` validates the handler on the server before use and
at completion, and removes the item only after a successful effect. Existing beer,
cigarette and food behavior remains covered by its original tests.

Review actual catalog models with
`godot --path game res://tests/features/vip_lounge/drink_preview.tscn`;
front and underside PNGs go to `/tmp/vip-drinks*.png`. The existing
`tests/features/holdables/consumable_probe.tscn` also accepts these catalog IDs
via `--item=luck_cocktail` (optionally `--first-person`) for rig review.

## Authority, wallets and persistence

`vip_lounge.gd` owns records and eligibility, `vip_rules.gd` owns pure rules,
and `vip_station.gd` validates fixed station-specific requests. Every use/service
uses NetworkedInteraction: authenticated sender, strict payload shape, range,
admission, room bounds and action cooldown. No client selects rewards or duration.
Replicated profiles contain discoverability, remaining time, progress and collections;
they omit account keys and transaction intents. Late joins receive current state,
without replaying private menus, dialogue, sounds or rewards.

All money remains in PlayerMoney. Private rounds use its existing atomic,
idempotent `settle_roulette` operation; the signed API accepts the resulting payouts
under its existing 36× limit. Gifts and invitation tips use `adjust_account` with
captured accounts. No money API/schema changes or second wallet are needed.

Account records persist in **user://vip_lounge.json**, or `--vip-save-path=...`,
following the existing bar's server-local account-store pattern. Keep this path on
the server's persistent storage. Boost/cooldown deadlines are absolute Unix times,
so reconnects and downtime do not extend them. Temporary offline/dev records remain
session-only and never cross into account records.

Before payment, the server saves the exact transaction ID, reward roll, amounts
and original claim time. Unknown replies retain that intent and block a different
operation; use the same service to retry. Account API replay prevents a duplicate
payment across reconnects or a restart. Successful settlement then records the
claim/progress and clears the intent. A failed intent save prevents submission.
The existing inventory persistence separately owns the awarded clothing.

## Rebuild and checks

From the repository root:

```sh
godot --headless --path game -s res://features/vip_lounge/tools/build_interior.gd
godot --headless --path game -s res://features/vip_lounge/tools/bake_music.gd
godot --headless --path game --import
godot --headless --path game --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir= -gtest=res://tests/features/vip_lounge/test_vip_lounge.gd -gexit
game/tests/features/vip_lounge/network_test.sh
harness/verify.sh
```

The furniture builder preserves prefab instances rather than flattening their
children; loading the game never repaints the saved GridMaps. The room's original
local coordinates are offset eight metres east by its `Interior` instance.
To migrate only the casino's saved upper wall opening without rebuilding unrelated
layout, run `godot --headless --path game -s res://features/vip_lounge/tools/recess_casino.gd`.
The casino's full offline builder calls `gridmap/vip_window.gd` to retain the
recess during future rebuilds. The entrance remains on the east promenade; its
upstairs arrival, exit, stations and GPS bounds follow the moved room.

Rendered review (requires a display):

```sh
godot --path game --audio-driver Dummy --rendering-method gl_compatibility \
  --resolution 1280x800 res://tests/features/vip_lounge/vip_probe.tscn \
  -- --offline --vip-role=capture
```

This writes room, overlook, exterior, bartender, menu and privacy-check PNGs to
`/tmp/vip-*.png`. The same probe supports `--vip-role=driver|observer` against a
dev-auth server. These test scenes seed only temporary wallets; production scenes
never grant the entry bankroll. Graphical shutdown can report the base casino's
two SubViewport texture leaks; the captures and privacy assertions run before exit.
