# Crown spawn

New joins, fall recovery and combat respawns start in the Golden Crown, on the north
promenade in front of the elevator. `feature.tscn` holds one `Spawn` marker at
(0, 1, -16) in the `player_spawn` group. `Game._spawn_position()` and
`Combat._respawn_position()` already use the first `player_spawn` marker plus their
±3 m jitter, so the whole spawn square (x -3…3, z -19…-13) is flat floor at y = 0,
clear of the ramp rails, outside the elevator threshold (z -20) and inside the
`safe_zone`. Players face -Z, straight at the elevator doors.

The operations garage (`starter_room`) keeps its own `Room/Spawn` marker for its
floor preloading, but it is no longer in `player_spawn`. It stays reachable through
its door on the north promenade and GPS.

Tests: `tests/features/crown_spawn/test_crown_spawn.gd`.
