# Retired old casino

Issue #487 removed the auto-loaded comparison room, both travel doors, its GPS
destination and the duplicate slot/roulette instances. There is no `feature.tscn`
here, so FeatureLoader does not load the old casino, even with `sv_cheats 1`.

Released notes remain as immutable history. Shared legacy architecture in
`res://world/room.tscn` and `casino_hub/interior.tscn` remains for authoring,
reference scenes and regression tests; it is not loaded by the live game.
The current casino remains `casino_hub/gridmap/playable.tscn`.
