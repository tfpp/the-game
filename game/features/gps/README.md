# GPS phone

Press **P** (or pick **GPS** in the Esc menu, which is how touch and controller players
open it) to raise a dual-screen phone. Search the place list on the left screen and
pick one. The phone goes away and a purple route appears on the radar, with a direction
arrow and a turn-by-turn line ("Turn left in 12 m", "Enter the lounge in 20 m") at the
top of the screen. Reopen the phone to pick another place or **End route**. The route
ends by itself a few seconds after you arrive.

Everything is client-side and private to each player: no RPCs, no shared state.

- `gps_destination.gd` (`GpsDestination`): a `Marker3D` place in the list (`label`,
  `hint`, and an optional global `area` for a closed-off space that isn't a
  `StreamedRoom`, like the parking garage).
- `gps_route.gd` (`GpsRoute`): pure routing. `next_hop()` treats every `StreamedRoom`
  and destination `area` as a region and every `GarageDoor`/`RoomDoor` as a link, and
  finds the next door to use. `grid_path()` walks a 0.5 m grid (50 m across) around
  the radar's wall slice, then string-pulls the path into straight legs.
- `gps.gd` (`Gps`): the P action, route state, radar overlay (`radar_overlays` group).
  The walkable path is re-planned every 2 m or 3 s.
- `gps_phone.gd` (`GpsPhone`): the phone (a `modal_ui` panel) and the banner.

The radar only exists on desktop, so phones and tablets get the banner (arrow and
distance) without the map line or wall avoidance.

## Adding a place (do this for every new room or area)

Add a `GpsDestination` child to `Destinations` in `feature.tscn`, on the floor where the
route should end. Rooms built as `StreamedRoom`s with `RoomDoor`s route automatically;
for another closed-off area reached by a `GarageDoor`, also set `area` to its world
extent. `tests/features/gps/test_gps.gd` fails if a streamed room in its `ROOM_SCENES`
list has no destination inside; add new room feature scenes to that list.
