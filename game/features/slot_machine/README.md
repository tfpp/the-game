# Slot machine

One machine stands at `(0, 0, 6)`, facing the initial spawn area. Approach its front,
look at it within 3.5 metres, then press **E**, **Circle / B**, or mobile **USE**.
The on-screen prompt identifies the machine. Menus and chat suppress interaction.

Each spin costs **$1**. Each of the three reels independently selects one of five
symbols with equal probability. Three equal symbols pay the following gross prizes:

| Triple | Prize |
|---|---:|
| 7 | $30 |
| BAR | $20 |
| STAR | $10 |
| BELL | $15 |
| GEM | $25 |

Pairs and nonmatches pay $0. There are five winning combinations out of 125 (4%).
The prizes sum to $100 across those 125 equally likely outcomes, so the expected
return is **80 cents per $1 spin** (20% house edge). Wins can grow a wallet, but
repeated spinning is a challenge, not a guaranteed money generator.

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

## Sound assets

Place these two **Ogg Vorbis** files in `audio/`:

- `win.ogg` — the winning “cha-ching!” sound.
- `lose.ogg` — the negative/losing sound.

Use short, non-looping clips. Restart/re-export after adding or replacing them.
They play spatially from the cabinet for nearby players. Missing files are silently
optional, so the feature works before assets are supplied. No code edits are needed.

## Layout

- `feature.tscn` places the machine in the world.
- `machine.tscn` is the reusable entity: collision, replication, view and sound.
- `slot_machine.gd` owns validation, spin progression and replicated state.
- `spin_cycle.gd` generates independent reels for offline/dev play.
- `slot_machine_view.gd` builds the placeholder cabinet and text symbols.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another machine, instance `machine.tscn` under `feature.tscn` with a unique
node name and position. All peers must load the same scene; each instance has its
own busy state. All machines share player wallets.

## Verification

`harness/verify.sh` runs unit and standard multiplayer checks. For the slot-specific
real server + two-client test (including a mid-spin join):

```sh
python3 game/tests/features/slot_machine/network_test.py
```

Set `GODOT` to the Godot executable if it is not on `PATH`. The test checks identical
results and balances on all peers, correct prizes, left-to-right stops, exactly one
result-audio event per spin, and rejection of out-of-range and competing requests.

For the real accounts API and SQLite integration, including a full minute of income:

```sh
SLOT_TEST_DATABASE=1 python3 game/tests/features/slot_machine/network_test.py
```

This builds a temporary API binary, creates an isolated database and test key, and
uses signed account join tickets. Nothing is written to a production database.
