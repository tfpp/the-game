# Hotel wing

Use **HOTEL WING** in the casino's south lobby to enter, and **CASINO** inside to return.
Use is E, controller B/Circle, or the mobile Use button.

Eight rooms connect through seven swinging doors. Anyone can open and close them;
the server validates distance and synchronizes the result, including for late joiners.
Doors swing away from the player and refuse to swing through someone standing nearby.

The East Salon is 1 m above the Gallery, reached by a ramp below 10 degrees.
Two stair flights continue through the Conservatory (2.5 m) to the Upper Study (4 m).
Both stairs are 36.9 degrees with level landings. Only the study door is locked.
Find its key on the pedestal in the Reading Room, then Use the study door to unlock it.
It stays unlocked for everyone until the session resets. Keys use a separate inventory
key ring, even with a full backpack. If the holder leaves before unlocking, the key respawns.

The Reading Room connects to a concrete storage room. Open its sewer door and Use
the ladder, then move forward/backward to climb up/down. A branching sewer network sits six
metres below the hotels. It connects the classic hotel to a modern hotel 84 metres
east and an Art Deco hotel 84 metres west, with a loop offering an alternate route. The storage floor and sewer roof have matching shaft openings.
Storage walls and ceilings also use the plain concrete service kit, with steel
doors and strip lights. Hotel kits have their own geometry and materials.
Window panes have opaque sky backdrops; corridor pendants follow a spaced centerline.
Door state has no floating labels or lock-status text.

Thirteen hotel rooms have broad skylights with frames matching their hotel kit.
Live daylight fills the rooms, with softer fill retained after sunset. The glazed
openings replace the central pendant, retain ceiling collision above the opening,
and show the sky immediately outside. Concrete service rooms retain their strip lights.

The hotel sits at `(0, 0, -1400)`. Geometry, collision and live lamps stream in for
visitors. Door and key synchronizers remain on the always-present Hotel anchor so
unloading the room never resets shared state. The game supplies the sky/day-night cycle.

## Atrium wing

Use the **ATRIUM** door beside the casino return door in the classic hotel's Grand
Lounge. The **CLASSIC HOTEL** door returns to that lounge. The atrium wing streams
separately at `(0, 0, -1500)`, retaining the four floors, fountain, glass roof,
gallery railings and guest rooms from the upstream hotel rebuild. Floors sit at
y = 0, 4, 8 and 12. Its switchback ramps run 24 m for a 4 m rise (9.46 degrees).
The eighteen upper guest rooms use shared swinging doors, kept outside streamed
geometry so state survives unloading and late joins. Both wings register with GPS
as separate regions connected by the existing RoomDoor links.

Edit `atrium_hotel.gd` for its layout; it builds when loaded with no bake step.
`test_atrium.gd` retains the upstream floor, headroom, landing and railing checks.
Portal tests cover round trips, arrival clearance, independent streaming and GPS.

## Fast authoring (no lighting bake)

Edit `hotel.json`, then run from the repository root:

```sh
godot --headless --path game -s res://features/world_builder/build.gd -- \
  res://features/hotel_annex/hotel.json res://features/hotel_annex/hotel.scn --force
```

This writes the room geometry and `hotel_doors.tscn`, the companion instanced under
Hotel in `feature.tscn`. Keep both generated scenes with the blueprint. Live lamps
work immediately; normal builds do not unwrap UV2, start an editor worker or bake lightmaps.
The optional world-builder lighting tools remain available for later.

Rebuild the sewer and storage fixtures with
`godot --headless --path game -s res://features/hotel_annex/tools/build_service.gd`.
The workspace's `Rebuild Hotel.cmd` rebuilds all three hotel blueprints, the sewer
and the reusable kit scenes. The nearby hotels use `modern.json` and `deco.json`.

Keep the GrandLounge north door at offset 8 aligned with the return trigger and
arrival marker. Connection `door` objects create corridor partitions and interactive
leaves; the older exterior `openings` describe static joinery.

Validation: GUT `test_hotel_annex.gd` and `test_swing_doors.gd`, plus
`godot --headless --path game -s scripts/network_checks.gd -- doors` for real WebSocket peers,
shared doors/key pickup, range checks, late joins and stream unloads.

Use the same command with `-- hotel` for the full-game hotel/atrium round trip.
