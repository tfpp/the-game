# Shared parking garage utilities

The retired P1–P3 map and its automatically loaded feature scene have been removed.
The official five-floor garage lives in `features/procedural_rooms/`; normal trips
use private copies created by `features/zone_instances/`.

This directory retains assets used by other features:

- `garage_door.gd`: shared door base used by room doors and developer portals.
- `car_boot.tscn`, `car_boot.gd`, `car_loot.tres`: searchable vehicle stash behavior.
- `car_wreck.tscn` and `car_wreck.gd`: painted wreck model and boot animation.
- `fluorescent_fixture.tscn` and `fluorescent_light.gd`: shared working/failing lights.
- `garage_ambience.gd` and `procedural_audio.gd`: synthesized ambience and sound helpers.
- `materials/puddle.tres`, tube and rubber materials: retained shared surfaces.
- `preview_car_boots.tscn`: standalone shared-car model review scene.

Shared door, car, audio and light tests remain under `tests/features/parking_garage/`.
Garage geometry and seeded encounter coverage target the five-floor destination.
Historical release notes remain available.
