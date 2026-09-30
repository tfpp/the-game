# Bar companion (Vivienne)

The salon bar at the back of the gaming floor (bar at (-7.4, -1.5, -10.7)) now has a
working bartender and **Vivienne**, who sits on a brass stool at (-5.2, -1.5, -8.55)
facing the counter. Everything uses Use (E, Circle / B, or mobile **USE**).

- **Bartender** (Use at the counter): a drink costs $5 through `PlayerMoney.charge()`.
  Each drink adds one point of intoxication, which wears off one drink per 90 s.
- **Charisma** (0–10): +2 for every slot win (up to +6, fading 1 point a minute) plus
  one per drink for the first three drinks. Each drink past three costs 2 points, so
  getting drunk also eats into charisma from wins.
- **Vivienne** (Use near her): costs $50, minus 7% per charisma point (at least $15).
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
- `companion_model.gd` restyles `casino_patrons`' `PatronModel` (dress, long hair) and
  adds a seated pose. `charm_math.gd` holds the pure rules.
- `features/slot_machine` adds `rerolls_for()` to its spin rerolls and calls
  `note_win()` when the reels stop on a win (not earlier, so charisma can't spoil the
  result). `features/apartments` gained `unit_bounds()` and `in_unit()`.

Limitation: extra rolls only change the odds on temporary (offline / dev) wallets;
Kaaba blessings also apply to authenticated accounts, through a separate bonus.
Nothing is persisted: charisma, drinks and luck reset on disconnect and server restart.

Tests: `tests/features/bar_companion/`.

## Celeste: an uncertain ally

Celeste stands beside the bar at **(-6.6, -1.5, -7.8)**, in a dark green evening
dress with black opera gloves, a swept fringe and a brass brooch. Use **E**, **B /
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

`CompanionModel.build_evening_guest(name, dress_color, hair_color)` shares the
existing dress silhouette; `build_vivienne()` preserves the original appearance.
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
on the existing customer-side floor at (-6.5, -1.5, -8.35), as a normal shared
pickup. Session generations discard stale callbacks after a mode change.

Bottled beer applies the same intoxication/charisma rules as the original drink,
once on the first of three sips; cigarettes last three puffs and have no stat effects.
Each primary action takes one sip/puff. Shop UI uses the existing
modal pause/resume contract, gamepad focus and phone-sized buttons. Stock is
unlimited and has no persistent state; purchases follow ordinary inventory lifetime.
`test_bar_shop.gd` covers purchase authority, stock/range validation, balances,
capacity, async races, reset and the menu. Original drink/charisma tests now select
`order` with `{"item": "drink"}` after the interaction opens the shop.
