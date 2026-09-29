# Day/night cycle

A full day/night cycle repeats every 48 real-time minutes, the same for everyone in
the world. There's no server state to request or replicate: every peer reads
`Time.get_unix_time_from_system()` (the same real-world clock
`features/money/money.gd` and `core/net/network.gd` already key off of) and derives
an identical time of day, so the sun and sky stay in sync across peers without any
RPC or `MultiplayerSynchronizer`.

## What moves

- A `DirectionalLight3D` ("Sun") crosses the sky during the day, then becomes a soft overhead moonlight at night so outdoor paths and silhouettes stay readable. Its energy and color fade through dawn and dusk.
- The world's `WorldEnvironment` (in `world/room.tscn`) gets its sky material
  swapped for `day_night_sky.gdshader`, which cross-fades the existing day skybox
  against a night skybox from the same Kenney pack, and its ambient light color,
  ambient energy, and sky brightness all lerp toward darker night presets along the
  same twilight band.
- This feature never edits `world/room.tscn`; it finds the single `WorldEnvironment`
  at runtime with `get_tree().root.find_children("*", "WorldEnvironment", ...)`, the
  same read-only, per-peer lookup pattern `features/ui_sounds/ui_sounds.gd` uses for
  nodes outside its own tree. If a scene has no `WorldEnvironment` (e.g. a bare test
  scene), the sun still animates and everything else is skipped.

## Verification

`godot --headless -s addons/gut/gut_cmdln.gd` runs
`tests/features/day_night/test_day_night.gd`, which covers the pure time-of-day,
sun-elevation and day-factor math plus the sun/environment/sky application methods
at noon, midnight and the twilight boundaries.
