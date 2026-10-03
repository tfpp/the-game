# Dev access

`dev_gate.gd` (`DevGate`) keeps development and test entrances out of normal play.
Add a `DevGate` node as a child of a `GarageDoor` (or a subclass such as `RoomDoor`
or the procedural garage portal). Until someone turns on `sv_cheats 1` in the `~`
console (the server-owned switch in [noclip](../noclip/README.md)), the door and any
`extra` nodes (signs) are hidden, its collision is off, and the server refuses to
use it. Turning cheats off again hides it. Clients poll the replicated switch every
0.5 s; the server checks it on every request, so a stale client cannot travel.

`GpsDestination.dev_only` hides a place from the GPS list the same way, and GPS
routing skips gated doors.

Gated today:

| Door | Feature |
| --- | --- |
| OLD CASINO, north promenade | `casino_legacy/` (`Entrance`) |
| STREET CASINO, north promenade | `street_district/` (`CasinoStreetEntrance`) |
| Street District teleporter, dev room | `street_district/` (`Entrance`) |
| Hotel Props teleporter, dev room | `hotel_props/` (`Entrance`) |
| Procedural garage teleporter, dev room | `procedural_rooms/` (`Entrance`) |

The DEV ROOM booth itself stays open: the lounge, wine cellar, hotel wing and Lily
Apartments are still entered through its doors. Return doors are never gated, so a
player inside a dev area can always walk back. The operations van still drives to
the Street District and B1; phase 1 task B1 reworks those routes.

This directory has no `feature.tscn`; it is a library. Tests live in
`tests/features/dev_access/`, whose `cheats_fixture.gd` turns cheats on for other
features' tests.
