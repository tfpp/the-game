# Code cleanup

## Retired parking garage mock-up (issue #317)

The P1–P3 map, its automatically loaded scene, garage-only stairs/drips/materials,
and fixed enemy placements have been removed. The official Parking Garage arrival
belongs to the five-floor B1–B5 destination. Shared prop, door, loot and rendering
tests have been migrated; lighting capture uses B1 and B5.

The `features/parking_garage/` directory remains a shared utility library: room-door
base, fluorescent fixtures, ambience/audio synthesis, vehicle loot/boots/wrecks,
and puddle/material assets used elsewhere. It has no automatically loaded map.
