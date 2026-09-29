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

## Swinging doors and keys

`swing_door.tscn` opens a physical passage with the same Use control. Place it at
floor level, with local +Z pointing into the destination room. `width`, `height`
and `door_label` configure the leaf. A nonempty `key_id` starts it locked and names
an ItemCatalog key. The server validates the requesting player, range, key ownership,
cooldown and player clearance in the swing area. Only `net_state` is replicated;
each peer animates its own matching leaf and collision. Unlocking lasts for the session.

Keep swinging doors and key pickups outside streamed `Content`, so their RPC and
synchronizer paths remain present for late joiners. The world builder emits a
`*_doors.tscn` companion with these placements for connection `door` objects.

`room_key_pickup.gd` extends the existing item pickup. Keys go into PlayerInventory's
replicated key ring without using backpack space. Point `locked_door` at the matching
SwingDoor so a key respawns if its holder leaves before unlocking. Session changes
reset the pickup and lock along with player inventories.

Doors and pickups use the shared [`NetworkedInteraction`](../../core/net/README.md)
component for transport, authenticated player lookup, range checks and replication.
Door scripts only register their gameplay validation and toggle callback.

`ladder.tscn` uses two `NetworkedInteraction` endpoints. The server checks endpoint
distance and the upper access door, then sends a mount event only to the owner.
That client moves along the ladder and publishes the normal Player movement fields.
Walking resumes at either landing; session changes release the player. Keep the ladder
outside streamed Content and configure `top_landing`, `bottom_landing` and `access_door`.
The default six-metre ladder descends from y=0 to y=-6 (player centers y=1 and y=-5).

Run `python3 game/tests/features/room_doors/network_test.py` for shared open/close,
server range/key validation, key ring replication, streaming and late-join checks.
