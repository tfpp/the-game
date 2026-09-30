# Code cleanup

Reminders for code and content that is kept temporarily and should be removed later.

## Old parking garage mock-up (issue #317)

The casino staff door into the old P1–P3 parking garage mock-up was removed. The
scene is intentionally still loaded so the removal can be done separately. Delete
it once nothing needs it any more:

- `game/features/parking_garage/feature.tscn` and `garage.tscn`, plus the
  garage-only scripts, materials and tests in `game/tests/features/parking_garage/`.
- Its `SlumArrivalPoint` (`Garage/GarageArrival`): the Golden Crown's slum gate can
  still pick it for an excursion until it is removed.
- Its enemies in `game/features/garage_enemies/` (placed at `(0, 0, 600)`) and the
  tests that load the old garage (`loot`, `slum_runs`, `room_visibility`,
  `day_night/lighting_probe.gd`, `gps`).
- Keep the shared pieces other features still use: `garage_door.gd` (`GarageDoor`,
  base of `RoomDoor`), `fluorescent_fixture.tscn`, `procedural_audio.gd`,
  `garage_ambience.gd`, `car_loot.tres`, `car_boot.tscn`/`car_wreck.tscn` and the
  puddle material. Check `rg parking_garage game` before deleting anything.
