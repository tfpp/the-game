# Slot machine

Eight machines stand in two rows outside the initial spawn area, each with its own
buy-in. Approach a machine's front, look at it within 3.5 metres, then press **E**,
**Circle / B**, or mobile **USE**. The on-screen prompt and cabinet show that
machine's price. Menus and chat suppress interaction.

| Machine | Buy-in |
|---|---:|
| Machine | $1 |
| Machine2 | $5 |
| Machine3 | $25 |
| Machine4 | $100 |
| Machine5 | $1,000 |
| Machine6 | $100,000 |
| Machine7 | $10,000,000 |
| Machine8 | $1,000,000,000 |

Each of the three reels independently selects one of five symbols with equal
probability. Three equal symbols pay the following gross prizes, scaled to the
machine's buy-in (the table below is per $1 of buy-in; a $1,000 machine's BAR
triple pays $1,000 × 20 = $20,000):

| Triple | Prize per $1 wagered |
|---|---:|
| 7 | $30 |
| BAR | $20 |
| STAR | $10 |
| BELL | $15 |
| GEM | $25 |

Pairs and nonmatches pay $0. There are five winning combinations out of 125 (4%).
The prizes sum to 100x the buy-in across those 125 equally likely outcomes, so the
expected return is **80% of every spin's buy-in** (20% house edge) on every machine.
Wins can grow a wallet, but repeated spinning is a challenge, not a guaranteed money
generator. `SlotMachine.buy_in_cents` (and the matching `wager_cents` sent to the
accounts API, capped server-side at $1,000,000,000 — see
[player money](../money/README.md)) is the only difference between machines; the rest
of the mechanic, replication and validation is shared.

The left reel stops after 1.2 seconds, the middle after 2.1 seconds, and the right
after 3 seconds. The cabinet shows the prices and the winning prize; the interaction
prompt includes your balance. See [player money](../money/README.md) for persistence
and the $5-per-minute income.

The server validates the actual RPC sender's player, distance, facing and clear
line of sight. Only one spin runs at a time. Other requests during it are ignored.
Visible reel frames, stopped reels, operator name and result are replicated together
in a server-owned `MultiplayerSynchronizer` snapshot. Late joiners receive the
current state. Result audio is a separate reliable server event, so joining after
a result does not replay an old sound. A spin finishes even if its player disconnects.
The API commits the charge and prize together before animation begins, so disconnects
or a game-server crash during animation cannot lose a prize. Requests are locked
while payment is pending as well as during animation.

## Win celebration

A win sets off fireworks above the cabinet and sprays gold coins out of the payout tray
at the front (`slot_celebration.gd`). Both scale with the prize on a log scale from $10
(one small rocket, a handful of coins) to $30 billion (seven big, fast bursts and about
80 coins). They start from the reliable `play_result` event, which now carries the
payout, so every nearby peer sees them once and late joiners don't replay old shows.
Coins and sparks are `CPUParticles3D` with no collision or lights, and free themselves.

## Sound assets

Place these two **Ogg Vorbis** files in `res://assets/slot_machine/audio/`:

- `win.ogg` — the winning “cha-ching!” sound.
- `lose.ogg` — the negative/losing sound.

Use short, non-looping clips. Restart/re-export after adding or replacing them.
They play spatially from the cabinet for nearby players. Missing files are silently
optional, so the feature works before assets are supplied. No code edits are needed.

## Layout

- `feature.tscn` places the machines in the world, each with its own `buy_in_cents`
  override.
- `machine.tscn` is the reusable entity: collision, replication, view and sound.
- `slot_machine.gd` owns validation, spin progression, replicated state and the
  `buy_in_cents` export.
- `spin_cycle.gd` generates independent reels and the scaled payout for offline/dev
  play.
- `slot_machine_view.gd` presents the walnut, enamel and chrome cabinet, curved
  printed reel drums, lever, price and payout multipliers. `reel_mesh.gd` builds the
  shared curved surface; `reel.gdshader` scrolls the generated symbol strip.
  Moving drums are cosmetic; each stopped drum settles onto its server-selected
  symbol, including immediately showing stopped symbols for late joiners.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another machine, instance `machine.tscn` under `feature.tscn` with a unique
node name, position, and (optionally) a `buy_in_cents` override — it defaults to 100
($1). All peers must load the same scene, so every peer computes the same price;
each instance has its own busy state. All machines share player wallets.

## Verification

`harness/verify.sh` runs unit and standard multiplayer checks. Set `GODOT` to the
Godot executable if it is not on `PATH`.

## Visual assets

The original cabinet model lives in `res://assets/casino_hub/models/`. `res://assets/slot_machine/textures/reel_symbols.png`
contains five generated icons in the exact gameplay order: 7, BAR, STAR, BELL,
GEM. Prompts and provenance are in `res://assets/casino_hub/textures/GENERATED_ASSETS.md`.
The cabinet keeps its existing collision hull and interaction point. Materials
are shared; each reel only owns its small animation shader state.

The PS1 cabinet uses 844 triangles and flat, matte finishes. The reel texture imports
at 128×128 with nearest mipmap filtering; its five icons and server-selected results
keep their original order. Drums use eight segments and idle reels skip redundant
shader uploads. Labels and interaction prompts keep their normal readable fonts.

## Kaaba blessings

Players who prayed at the Kaaba ([kaaba](../kaaba/README.md)) carry blessings. The
server passes them to `PlayerMoney.spin()` through the legacy `rerolls` argument.
Each stack adds 200% of the base win chance (4% becomes 12% with one, up to 44%
with five); a win spends all stacks. Temporary wallets and the authenticated API
use the same exact odds and equal winning-symbol probabilities. The 80% return
above is for unblessed spins; blessings increase it without changing prize sizes.
