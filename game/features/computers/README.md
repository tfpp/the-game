# Mouse-operated computers

Two terminals stand on the **south side of the Adventure Arcade**, at (-84, 0, 4)
and (-76, 0, 4), facing north. Enter the arcade from the casino door at
(-8.6, -1.5, 8.5), then turn around. Use (E / B / Circle / touch Use) opens a
free computer. Click **Start / Retry** on the physical screen, then click the
turkey. Each punch scores 10 points; three punches defeat a turkey and bring
another. A round lasts 30 seconds. Leave or Esc restores the previous camera.
Touch players tap the screen; controllers move the crosshair with the right stick
and press A / Cross. B / Circle or Start exits through the normal menu handling.

This is an original native Godot recreation of **Super Turbo Turkey Puncher 3**,
with original vector artwork and Kenney punch sounds, not an embedded Doom 3
runtime or copied game assets. The requested Doom 3-like behavior is a mouse
operating the actual world-space display. Other players see the live game on
that same display. There is no overlay replacing the screen.

`computer.gd` owns each computer's session and game state on the server. Requests
validate authenticated sender, session generation, distance, facing, occlusion,
click region and a 150ms punch cooldown. One player operates each terminal at a
time. The complete snapshot is replicated by `MultiplayerSynchronizer`, including
scores and remaining seconds, so late joiners see the current game immediately.
Leaving, disconnecting, moving/respawning away, focus loss or a six-second expired
heartbeat releases control and ends the round. Best scores survive handoffs but
reset on server restart or network mode change. There is no money reward.

`computer_view.gd` uses the existing `ScummArcadePointer.project` contract (320x200
coordinates on a 1.18x0.885m plane), with a 640x400 texture for legible type.
It reuses the existing arcade room boundary for cosmetic loading; the two static
RPC/collision nodes always exist. Visuals allocate only in that room, update the
viewport only for state/cursor/short hit animations, and add no lights. The
separate camera restores either first- or third-person view when closed.
No SCUMM emulator, replay, persistence or public API is changed.

Tests: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/computers -gexit`.

Run `python3 game/tests/features/computers/network_test.py` from the repository
root for a real server/operator/late-joiner test. It checks score replication,
competing requests, disconnect release and a fresh round after handoff. The probe
disables the server-only hotbar callback to isolate a pre-existing stale-player
reference on disconnect; production hotbar code is unchanged.

For a desktop render, run `xvfb-run -a godot --path game --audio-driver Dummy
--resolution 1000x700 res://tests/features/computers/visual_probe.tscn` (one line).
It saves `/tmp/computer-screen.png`; use `--resolution 390x844` for portrait.
