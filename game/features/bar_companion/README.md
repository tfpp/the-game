# Bar companion (Vivienne)

The salon bar at the back of the gaming floor (bar at (-7.4, -1.25, -10.7)) now has a
working bartender and **Vivienne**, who sits on a brass stool at (-5.2, -1.25, -8.55)
facing the counter. Everything uses Use (E, Circle / B, or mobile **USE**).

- **Bartender** (Use at the counter): a drink costs $5 through `PlayerMoney.charge()`.
  Each drink adds one point of intoxication, which wears off one drink per 90 s.
- **Charisma** (0–10): +2 for every slot win (up to +6, fading 1 point a minute) plus
  one per drink for the first three drinks. Each drink past three costs 2 points, so
  getting drunk also eats into charisma from wins.
- **Vivienne** (Use near her): costs $50, minus 7% per charisma point (at least $15).
  Replies appear in on-screen subtitles as well as her overhead bubble, so room
  requirements and payment failures remain readable when standing close in either view.
  You need a Lily Apartments unit first (`features/apartments`). After paying she
  follows you (catching up through doors and elevators) and asks you to lead her to
  your room. Walk into your own unit with her there and you get a **lucky night**:
  for 10 minutes, every slot spin gets two extra reel rolls, stacking with the separate
  Kaaba blessing bonus. Wins don't use it up. She lingers a few
  seconds, then returns to her stool. If you disconnect or take longer than 5 minutes
  she goes back too. Only one player can have her at a time.
- A line above the wallet (bottom right) shows your charisma, mood, lucky-night timer
  and escort goal while any of them apply.

## How it works

- `bar_companion.gd` (`BarCompanion`, group `bar_companion`) owns per-peer charisma,
  intoxication and luck on the server, and replicates a rounded `stats` summary through
  its `NetworkedEntity` (late joiners get it on spawn). Server API: `add_drink`,
  `note_win`, `grant_luck`, `price_for`, `rerolls_for`, `forget`.
- `bartender.gd` and `companion.gd` (`Vivienne`) use `NetworkedInteraction`: the server
  checks the sender, range and state, then charges the wallet asynchronously. Vivienne
  replicates `net_escort` on change and `net_position` / `net_yaw` continuously.
- `companion_model.gd` dresses `casino_patrons`' `PatronModel` (the player avatar rig)
  in a one-color evening dress with long hair and seats her with `PatronModel.sit()`. `charm_math.gd` holds the pure rules.
- `features/slot_machine` adds `rerolls_for()` to its spin rerolls and calls
  `note_win()` when the reels stop on a win (not earlier, so charisma can't spoil the
  result). `features/apartments` gained `unit_bounds()` and `in_unit()`.

Limitation: extra rolls only change the odds on temporary (offline / dev) wallets;
Kaaba blessings also apply to authenticated accounts, through a separate bonus.
## Stats menu and persistence (#343)

Open **Player stats** from the Esc/pause menu (also available through the touch menu
and controller focus). It always shows charisma and intoxication, including zero,
explains tipsy/too-drunk effects and Vivienne's price, and shows the lucky-night timer
and existing Kaaba blessing count. It is read-only and refreshes from replicated state.
The compact HUD remains unchanged. No new key binding is required.

`BarCompanion` still owns all gameplay state. `CharmStore` saves the precise win-charisma,
intoxication and lucky-night components by immutable authenticated account ID, never
by display name or client-supplied identity. Reconnecting or renaming restores the same
stats; guest/offline/dev-auth stats remain session-only. Escort progress is not saved.
Respawns retain stats as before. Timers continue while signed out or the server is down,
using elapsed wall-clock time at restore; active sessions retain the existing decay rules.

Server snapshots are atomically replaced at `user://bar_stats.json` on each drink,
win or luck grant, every five seconds during decay, on disconnect and feature shutdown.
Pass `-- --bar-stats-save-path=/persistent-volume/bar_stats.json` to override this.
The parent directory must exist; operators must mount persistent storage to retain the
file across container replacements (the same deployment requirement as leaderboard).
Sign-ins and browser refreshes do not require any deployment changes. A crash can lose
up to five seconds of decay; invalid rows are skipped and valid values are bounded.
Clients never read/write saves, and account IDs are not added to replicated summaries.
Old sessions have no saved stats to backfill. Wallet/inventory persistence is unchanged.

Tests: `tests/features/bar_companion/`.

## Busboy shift (#450)

At the **left end of the main salon bar**, use the glass marked **BUSBOY SHIFT**
(-9.9, -0.27, -9.6) with E / B / Circle / touch USE. The existing bartender
shop is unchanged, several metres to the right. One worker at a time takes the
shared two-minute shift; other players can watch but cannot take its tasks.

- Collect glasses marked EMPTY from the **numbered tables 1–8**. The first empty
  appears immediately at table 1; the HUD lists tables with outstanding empties.
  Tables 1–3 are the salon card tables (glasses on their west edges); 4 is the east
  lounge table, 5 the existing southwest lounge table. New cocktail tables 6–8
  stand on the northwest, northeast and southeast promenade. Return each empty
  to the station with Use before collecting another. The counter only offers Use
  when it can actually start, accept cargo, dispense an order or pay the prize;
  it no longer advertises an action that silently does nothing. Cargo is a
  temporary shift task, not backpack loot.
- After 30 seconds, seated patrons at the east side of the card tables order drinks.
  Take a bottled drink from the station, then Use the matching numbered patron.
  Their labels show a 35-second deadline, including time spent carrying the drink.
  You cannot carry an empty and an order together. The task HUD shows your cargo,
  remaining shift time, dirty backlog and pending orders. Empty cargo uses the
  existing hotel glass; ordered cargo uses the existing beer bottle, visible in
  first person, third person and to observers on the offhand side.
- After the immediate first empty, spawns accelerate from 12 seconds to 4;
  orders from 24 seconds to 10.
  Slots are selected randomly from free table positions; living seated patrons
  are selected randomly for orders. Decorative table glasses are not objectives.
- A ninth dirty glass or any overdue order fails with **no prize**. To win at
  120 seconds, return at least one empty and finish all orders. Remaining dirty
  glasses are cleared when the shift ends. Return to the station to claim **$10**;
  if the wallet is busy or unavailable, Use again to retry the same reward ID.
  There is no entry charge. Use after failure or payment starts a new shift.

`busboy_shift.gd` owns the worker, timers, backlog, cargo, deadlines and reward ID
exclusively on the server. Its NetworkedEntity replicates one bounded `snapshot`
including current task state on late join. `busboy_point.gd` constructs matching
static NetworkedInteraction endpoints before connecting; these are fixed cosmetic
views, not dynamically spawned entities. Empty Use payloads resolve the sender
and validate range, ownership, phase and cargo again on the server. No new RPC,
input action, inventory slot, collectible item or persistence store is introduced.
`HeldItemPose.player_mount()` is reused only for the cosmetic cargo mount; normal
inventory remains untouched, cannot store/sell task cargo and has its own hand.
`PlayerMoney.credit_coin()` is the sole reward path, including its signed,
idempotent authenticated-account settlement and private gain notice. Pending claims
block duplicates; stale callbacks cannot change a replacement shift or session.

Death or a replaced player node fails the shift. Disconnect or session changes
clear all tasks and release the station. Rounds and unclaimed prizes reset on
server restart; claimed account money follows existing wallet persistence. Offline
play runs the same authority path with the normal temporary wallet.

`table_card.tscn` is a reusable two-sided cream number card; set `number` before
adding it to the tree. `table_card.gd` is the authoritative native geometry source:
0.30 × 0.325 × 0.16 m, tabletop-centred pivot, faces ±Z, 28 triangles and two
shared materials. Numbers reuse `SignBoard.letters_mesh()` and the existing
64×64 `SignLetterAtlas` with its padded glyph UVs; no new artwork, atlas or lights.
The paper card meets its broad foot without gaps; cards have no collision. Card
faces on salon tables rotate toward the west/east approaches. All eight cards
are always visible, even outside a shift. New tables reuse the existing painted
walnut pedestal model/collider at y=0; existing furnishings remain unchanged.
The three new table centres are (-20,0,-15), (20,0,-8), (20,0,14).

Tests: `test_busboy.gd`, `test_busboy_use.gd` and `test_busboy_layout.gd` cover
public Use selection at real standing heights, rules, security, cargo,
wallet claims, lifecycle, snapshot presentation and supported placement in the
actual live casino. Run `tests/features/bar_companion/busboy_network_test.sh` from
`game/` for real WebSocket sender, competition, late-join, cargo and disconnect
checks; `BUSBOY_TEST_PORT` overrides the port. The probe has the same isolated
server-side weapon-hotbar workaround as the existing Celeste probe.

Native review captures are in `docs/design/previews/busboy-shift/`. Reproduce with
`godot --audio-driver Dummy --rendering-method gl_compatibility --resolution 1100x750
res://tests/features/bar_companion/busboy_network_probe.tscn -- --offline
--busboy-role=capture --busboy-view=tables` (one command, from `game/` using a display).
Views `east` and `first` capture the lounge and carried glass; `390x844` automatically
uses the existing mobile UI scale and touch controls. Captures seed a frozen example
snapshot, not a completed shift or payout. Images are written to `/tmp/busboy-<view>.png`.


## Celeste: an uncertain ally

Celeste stands beside the bar at **(-6.6, -1.25, -7.8)**, in a moss green evening
dress with a swept fringe and a gold brooch. Use **E**, **B /
Circle**, or touch **USE** to invite her along for free; Use her again to part ways.
She accompanies one player at a time around the gaming floor for up to five minutes,
sharing quiet tips and suspicious asides every 22 seconds through `Subtitles`.
Her allegiance stays ambiguous: she never attacks, steals money or alters luck.
Vivienne's paid apartment visit, drinks and rewards are unchanged.

`celeste.gd` owns only Celeste's server-side leader, bounded breadcrumb trail and
dialogue timers. `NetworkedInteraction` authenticates empty Use requests, checks
range/availability and enforces a shared one-second cooldown. Leader, position and
yaw replicate, including late-join state; private transient speech is not replayed.
Clients only present the pose. She follows the player's trail with world collision
and gravity, without blocking players or cutting through furniture. Lead her around
obstacles; she cannot jump over them. She stays within the main gaming floor
(x +/-14, z +/-11.5), not the gallery, rooms or slums. Leaving that area, getting
18 metres ahead, dying, disconnecting, replacing the player, timing out or changing
sessions returns her to the bar. State resets on restart; no persistence or rewards.

`CompanionModel.build_evening_guest(name, dress, hair_color, hair)` shares the
dress silhouette (ClothingCatalog and PlayerAppearance indices); `build_vivienne()` preserves the original appearance.
Celeste adds only cosmetic accessories and reuses `PatronModel.pose()`.
Tests: `test_celeste.gd` (requests, lifecycle, subtitles and appearance) and
`test_celeste_layout.gd` (actual casino floor, clearance, following and collision).

Run real WebSocket recruitment, forged/range requests, competing use, private speech,
late join and disconnect checks with
`tests/features/bar_companion/celeste_network_test.sh` from `game/` (override port with
`CELESTE_TEST_PORT`). The probe disables the server's unrelated weapon-hotbar UI
because it retains a freed remote hand after disconnect on this base snapshot.
To capture the actual salon, run its `celeste_network_probe.tscn` with
`-- --offline --celeste-role=capture` using a display; it writes `/tmp/celeste.png`.

## Bar shop items (#290)

Use the existing bartender at the salon counter to open **THE CROWN — BAR SHOP**.
Choose **Bottled beer — $5**, **Cigarette — $2**, or **Drink now — $5**. The last
option preserves the original immediate drink/charisma service. Opening the shop
never charges money. Close the menu to resume play; stored purchases are equipped
through Inventory, then used with primary action (left click / RB / trigger / FIRE).

The bartender's existing NetworkedInteraction owns `order` with exactly one
`item` string from its fixed stock. It resolves the sender, rechecks range and
allows only one pending payment per player. `PlayerMoney.charge` remains the only
wallet; `PlayerInventory.collect` delivers items. A full inventory rejects before
payment. If it fills or the buyer disconnects during payment, the paid item lands
on the existing customer-side floor at (-6.5, -1.25, -8.35), as a normal shared
pickup. Session generations discard stale callbacks after a mode change.

Bottled beer applies the same intoxication/charisma rules as the original drink,
once on the first of three sips; cigarettes last three puffs and have no stat effects.
Each primary action takes one sip/puff. Shop UI uses the existing
modal pause/resume contract, gamepad focus and phone-sized buttons. Stock is
unlimited and has no persistent state; purchases follow ordinary inventory lifetime.
`test_bar_shop.gd` covers purchase authority, stock/range validation, balances,
capacity, async races, reset and the menu. Original drink/charisma tests now select
`order` with `{"item": "drink"}` after the interaction opens the shop.
