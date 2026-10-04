# Dev elevator

A debug-only warp pad for testing slum maps, not part of the game world proper. It
lives in its own sealed, hazard-striped room far from everything else
(`DevElevator` sits at world `(0, 0, 900)`), so
reach it with noclip (`sv_cheats 1` in the `~` console, then `V`) rather than on foot. Bright warning signage ("DEVELOPMENT
ELEVATOR — INTERNAL TESTING ONLY — NOT PART OF THE GAME") makes it unmistakable if
anyone stumbles onto it anyway.

With cheats enabled, step onto the orange pad and press Use: the server selects
a registered destination and creates a private excursion through `ZoneInstances`.
It waits for destination readiness before moving you into its return cab. You can
use that cab to return normally. Standalone pad fixtures without the zone service
retain the authored-marker warp.

## Destination registry

`slum_arrival_point.gd` tags a `Marker3D` as a valid slum arrival point by adding it to
the `slum_arrival_points` group. The five-floor garage registers
`procedural_rooms/Garage/Arrival`; Rain Alleys registers its own marker.
`slum_destinations.gd` selects a random entry and can restrict selection to the
caller's MultiplayerAPI. Normal Crown trips create private copies through ZoneInstances.

The pad remains a developer shortcut. The Crown's cab uses the same registry for
group travel into independent slum instances with arrival and return cabs.

`tests/features/dev_elevator/` covers the pad's range gating and teleport (like
`test_garage_door.gd`) and the registry's null/single/multiple-entry behavior.
