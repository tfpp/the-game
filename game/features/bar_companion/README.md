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
  for 10 minutes, every slot spin gets two extra reel rolls, the same mechanism as
  Kaaba blessings, which it stacks with. Wins don't use it up. She lingers a few
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

Limitation: like Kaaba blessings, extra rolls only change the odds on temporary
(offline / dev) wallets until the accounts API accepts rerolls (see open PRs #255/#257).
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
