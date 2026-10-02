# Golden Crown elevator

The current casino has one stationary elevator in the center of its north wall,
opposite the south lobby. New players spawn just in front of it (`../crown_spawn/`). Its eight-meter facade replaces four two-meter wall
panels. A broad brass-lettered sign, matching wood facade and flanking sconces make
it a landmark. The entrance is recessed 20 cm behind the wall; the header and roof
have separate front planes to avoid z fighting. The floor remains at y = 0.

Press Use at the hall plate to open the doors. They stay open for 4.5 seconds before
closing. Both the hall and interior plates can close them sooner. A player in the
threshold holds the doors open or reverses a closing door. Doors and buttons use
the existing keyboard, controller and touch interaction system.

The cab carries at most **four riders**. The server counts players inside the cab
every tick; with five or more the doors refuse to close (the plates show "Over
capacity") and closing doors reopen. A small brass lamp with a red emissive lens
lights above the hall doors (right of the floor indicator) and on the cab's back
wall. The replicated `net_overloaded` flag drives both lamps, so late joiners see
the current state. `rider_count()` exposes the server count.

**Travel is disabled in the casino.** There is no destination cab or basement trip
loaded by this feature. The elevator car never translates vertically.

## Files and ownership

- `elevator.tscn`: reusable complete kit, a one-cell GridMap plus its cab controller.
- `elevator_cab.tscn` / `elevator_cab.gd`: moving leaves, control plates, sign, one
  warm light and the stationary state machine. Its `Car` child owns the internal
  recess; the scene root shares the fixed module's doorway origin.
- `call_button.tscn` / `call_button.gd`: visible control with authenticated nearby Use.
- `elevator_math.gd`: relative position/facing and door math, independent of scenes.
- `gridmap/bay.tscn`: fixed wood interior, facade and box collision; no CSG.
- `gridmap/build.gd` / `elevator_library.tres`: offline bake of the fixed structure.
- `models/`: shared painted cab, door and button prefabs and their material. The
  procedural garage's separate physical service lift also uses these prefabs.

This directory is a reusable kit, not an automatically loaded feature scene.
The casino instances the complete `elevator.tscn` once.

Original painted meshes, the 128×128 atlas and the native authoring tools remain
under `assets/procedural_rooms/models/elevator/` and
`features/procedural_rooms/model_tools/`; see the
[authoring notes](../../../docs/design/model-sources/elevator/README.md).
Those are shared source assets, rather than a second stationary elevator system.

## GridMap placement

The casino library exposes **11: ElevatorBay** for fixed-grid authoring. The
complete kit owns a smaller library with the same module at item 0. Its `Bay`
GridMap has **8 × 5 × 4 m** cells, centering disabled, octant size 1 and a cell at
(0,0,0). Its origin is the wall threshold at world (0,0,-20). The structure extends
backwards from there. Front sign trim projects 13 cm. The fixed mesh has 400
triangles, shared materials and seven simple box collision shapes. Moving leaves
remain in the companion scene because GridMap items cannot contain behavior.

For another scene, place `elevator.tscn` with its +Z axis facing the approach.
In the casino, `Casino/Elevator` is an ordinary instance of that same scene at
(0,0,-20). There are no placement overrides or external recess offsets.
Leave doorway clearance in the surrounding wall and align the fixed floor with
the adjoining floor. Runtime code never rebuilds saved GridMap cells.

Rebuild after editing fixed source geometry:

```sh
godot --headless --path game -s res://features/elevator/gridmap/build.gd
godot --headless --path game -s res://features/casino_hub/gridmap/build.gd
```

## Optional transfer API

To connect two compatible cabs later, set a cab's `destination` NodePath and opt in
with `travel_enabled = true`. A departure transfers only its occupants, after the
doors fully close, using the existing owner-authorized `Player.server_teleport`
RPC. It preserves their cab-relative positions, yaw and pitch. A missing or busy
destination safely leaves riders where they are. `server_arrive()` opens the
receiving cab for unloading without automatically scheduling a return trip.
This is a same-world transfer hook, not the future zone-instancing system.

`NetworkedEntity` owns state replication and session resets;
`NetworkedInteraction` authenticates both control plates. State and aperture are
included in late-join snapshots, so joining during a slide applies the actual
leaf positions instead of replaying a complete animation. Arrival audio uses a
transient event and is not replayed to late joiners.

Tests cover door cycles, authenticated requests, optional group transfer, doorway
obstruction, current-map placement, collision and standalone-kit alignment.
`tests/features/elevator/network_probe.tscn` additionally runs with `-- server PORT`
and `-- client PORT` to check a late join over real WebSocket transport. Render
captures live in `docs/design/previews/casino-elevator/`.
