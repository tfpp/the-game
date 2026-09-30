# Dev elevator

A debug-only warp pad for testing slum maps, not part of the game world proper. It
lives in its own sealed, hazard-striped room far from everything else
(`DevElevator` sits at world `(0, 0, 900)`, the same "isolated pocket" trick
`features/parking_garage/` uses for its own garage), so
reach it with noclip (`sv_cheats 1` in the `~` console, then `V`) rather than on foot. Bright warning signage ("DEVELOPMENT
ELEVATOR — INTERNAL TESTING ONLY — NOT PART OF THE GAME") makes it unmistakable if
anyone stumbles onto it anyway.

Step onto the orange pad and press Use: the server immediately teleports you to
whichever slum map is currently registered — see `slum_destinations.gd` and
`slum_arrival_point.gd`.

## Destination registry

`slum_arrival_point.gd` tags a `Marker3D` as a valid slum arrival point by adding it to
the `slum_arrival_points` group; `features/parking_garage/feature.tscn`'s
`Garage/GarageArrival` already carries it. `slum_destinations.gd` reads that group and
picks one entry — today there's only one, so it's deterministic, but the lookup already
goes through `randi() % points.size()`, so registering a second slum (just adding
`slum_arrival_point.gd` to that slum's own arrival marker) is all a real random pick
needs.

This pad is the first consumer of that registry. The eventual plan (not built yet) is
for the Golden Crown's real elevator to read the same registry and send players to a
random slum on arrival, instead of the fixed destination it has today.

`tests/features/dev_elevator/` covers the pad's range gating and teleport (like
`test_garage_door.gd`) and the registry's null/single/multiple-entry behavior.
