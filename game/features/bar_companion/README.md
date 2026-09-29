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
