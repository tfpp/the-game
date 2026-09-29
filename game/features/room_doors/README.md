# Room doors

Doors that link rooms, where each room is its own scene that a peer builds only while
its local player is inside. A booth in the casino's south lobby at `(-6, 0, 31)` leads
to the Lounge, and a door in the Lounge leads to the Wine Cellar. Every door goes
both ways. Press **E** (or Use) at a door.

- `streamed_room.gd` (`StreamedRoom`): an always-present anchor node. Its contents,
  `room_scene`, are instantiated as `Content` while the local player is inside
  `bounds`, and freed once they leave (with `unload_margin` of slack). A dedicated
  server has no local player, so it never builds any room, and each client only builds
  the room it's in.
- `room_door.gd` (`RoomDoor`): extends the parking garage's `GarageDoor`, so the
  server validates range and teleports the same way. On `use()` the client builds
  the destination room first and holds it for `ARRIVAL_HOLD_MSEC` while the teleport
  RPC is in flight, so the player doesn't land on missing floor.

Room scenes (`rooms/`) exist on only some peers, so they may hold only static geometry
and client-side decoration. Spawners, synchronizers and RPC nodes break there. Doors
and arrival markers belong on the `StreamedRoom` itself, outside the room scene.

To add a room, add a `StreamedRoom` to `feature.tscn` far from the rest of the map
(for example `(80, 0, -600)`). Point it at a new scene in `rooms/` and add arrival
markers plus `RoomDoor`s whose `destination` names the other side's marker. Then
add the room to the GPS (`features/gps/README.md`). Every `StreamedRoom` joins the
`streamed_rooms` group and `global_bounds()` gives its world extent; the GPS uses both.

Tests are in `tests/features/room_doors/`.
