# Slot machine

One machine stands at `(0, 0, 6)`, facing the initial spawn area. Approach its front,
look at it within 3.5 metres, then press **E**, **Circle / B**, or mobile **USE**.
The on-screen prompt identifies the machine. Menus and chat suppress interaction.

Each machine has its own shuffled sequence containing exactly four wins and one
loss per block of five accepted spins. This is not an independent 80% probability
per spin. The sequence resets with the server/session. Three equal symbols win;
a loss always has a different final symbol. The left reel stops after 1.2 seconds,
the middle after 2.1 seconds, and the right after 3 seconds.

The server validates the actual RPC sender's player, distance, facing and clear
line of sight. Only one spin runs at a time. Other requests during it are ignored.
Visible reel frames, stopped reels, operator name and result are replicated together
in a server-owned `MultiplayerSynchronizer` snapshot. Late joiners receive the
current state. Result audio is a separate reliable server event, so joining after
a result does not replay an old sound. A spin finishes even if its player disconnects.

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
- `spin_cycle.gd` generates the four-win/one-loss blocks.
- `slot_machine_view.gd` builds the placeholder cabinet and text symbols.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another machine, instance `machine.tscn` under `feature.tscn` with a unique
node name and position. All peers must load the same scene; each instance has its
own sequence and busy state.

## Verification

`harness/verify.sh` runs unit and standard multiplayer checks. For the slot-specific
real server + two-client test (including a mid-spin join):

```sh
python3 game/tests/features/slot_machine/network_test.py
```

Set `GODOT` to the Godot executable if it is not on `PATH`. The test checks identical
results on all peers, four wins per five spins, left-to-right stops, exactly one
result-audio event per spin, and rejection of out-of-range and competing requests.
