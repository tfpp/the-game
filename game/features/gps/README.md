# GPS phone

Press **P** (or pick **Esc → Activities → GPS**, which is how touch and controller players
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
  finds the next door to use. Operations van destinations also supply links, so the
  separate gun shop routes through the garage and its van. `grid_path()` walks a 0.5 m grid (50 m across) around
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

## People, animals and objects

The list now has **Places**, **People**, **Animals**, and **Objects** headings.
Search matches names, hints and section names. Scroll the list with the mouse wheel
while the phone is open (including over its other screen), or use its scrollbar,
touch drag and controller list navigation. Headers cannot start a route.

`gps_catalog.gd` builds local `GpsDestination` adapters when the phone opens from
existing `players`, `killable` and `interactables` groups. Other players use their
replicated display names; patrons, companions and gnomes are People; frogs, the
penguin and bird are Animals; usable objects and other props are Objects. Only
currently instantiated entities are listed: streamed-out props appear after their
room loads. Existing area markers remain available to navigate to those rooms.
The local player is omitted. Dead animals/NPCs and burrowed gnomes are unavailable.
Reopen the phone to refresh newly spawned entities. A stale row cannot be selected.

`GpsDestination.category` defaults to Places, preserving existing markers and
region consumers. `destination_position()` reads a tracked entity's current global
position. `available()` checks its lifetime and existing replicated alive state.
Active routes clear on death/despawn/disconnect; reopened lists include respawns.
Moving targets replan on the existing distance/time budget and cancel the arrival
countdown if they move away. No new RPCs, shared state, persistence, keys or world
placements are introduced; entity owners retain all simulation and replication.

Places with `dev_only = true` are listed only while `sv_cheats 1` is on, and doors with a
`DevGate` child are left out of routing while they are locked (see
[dev access](../dev_access/README.md)).
