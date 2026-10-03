# Room visibility

The server checks each player's replicated position against existing
`StreamedRoom.bounds` and `GpsDestination.area` volumes. It sends the selected
room to that player when the assignment changes. The client loads only the
selected streamed interior and frees the previous one. Door interactions may
preload the destination briefly so the arrival floor is ready.

For distance culling, the client sets Godot's camera far plane to the farthest corner
of the assigned room. The casino's bounds come from its visible meshes and transformed GridMap cells; other
rooms use their authored extents. This keeps always-loaded geometry in distant
districts out of the draw list without fixed distance cutoffs. Shared gameplay
nodes remain present on every peer, and the server never loads client-only
room interiors.

New door-only districts should have either a `StreamedRoom` anchor or a GPS
destination with an `area` covering their visible district. The server uses
those same bounds for room assignment and camera clipping.

## Garage scene isolation

The P1–P3 and B1–B5 garages are separate `garage.tscn` scenes in their
existing feature directories. Their roots extend `RenderZone`, with local
`render_bounds` and reserved visual layers **19** and **20**, respectively.
`zone_rendering.gd` selects a camera mask from the local camera position each
frame: inside a garage, no casino or other district visuals/lights are drawn;
outside, garage visuals are excluded. This also covers offline play, immediate
teleports, first/third-person camera changes and respawns without waiting for a
room-assignment RPC. The HUD is unaffected.

Static visuals are classified once, new visuals on arrival, and moving
physics-body visuals (players, enemies, held items) at 10 Hz. Cosmetic additions
outside zone roots are also refreshed so transient projectiles/effects follow
their position. Freed visuals are removed from the cache. Lights use matching
illumination masks. When the camera crosses between rooms, cached light entries are
refreshed so only the current room illuminates the first-person handheld layer (18).
The physical basement cab and casino landing use the
`render_zone_shared` group so the crossing remains visible from either side.
Do not use layers 19/20 for unrelated visuals.

This is **render isolation**, not unloading of gameplay or network interest
management. Colliders, authoritative enemies, searchable boots, lift, doors and
RPC paths remain loaded identically on every peer. StreamedRoom's static-only
contents still use the existing load/free lifecycle. Dedicated servers skip the
render classifier. No authority, balance, inventory or persistence changes.

Tests: `tests/features/room_visibility/test_zone_rendering.gd`, plus existing
room assignment, garage layout, portal, lift and enemy suites.

## Teleport arrival protection

A RoomDoor preloads its destination for the existing arrival hold before requesting
travel. Room assignments received while that request is in flight preserve the
held destination instead of deleting its floor. Unused preloads expire after the
hold; an assignment selecting the destination removes its pending eviction.
Procedural socket caps may also disappear before deferred render registration;
the renderer resolves a weak reference and skips those freed visuals.

Street network regression (dedicated server, visitor, late join, real gravity):

```sh
bash game/tests/features/street_district/network_test.sh
```

The probe deliberately delivers a stale departure assignment after preloading,
checks standing floor contact after teleport, then verifies return/unloading.
It also places two authenticated players on the street and verifies their bodies,
nameplates, replicated positions and camera masks. With a display available,
`STREET_RENDER_TEST=1` adds a framebuffer check that the remote body is actually
drawn. Set `STREET_CAPTURE_DIR` to retain the in-game screenshots. Detached visuals
are removed from the cache before their deferred deletion, so unloading a street
cannot query transforms on nodes that have already left the scene tree.

Moving visuals have a separate refresh cache. Static and moving visuals unregister
on tree exit, restore their authored masks and can register again on reentry.
