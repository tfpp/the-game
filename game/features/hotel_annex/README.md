# Hotel wing

Use **HOTEL WING** in the [dev room](../dev_room/README.md) to enter, and **CASINO** inside to return to it.
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
The eighteen upper guest rooms (101–106, 201–206, 301–306) use shared swinging
**guest-room doors**, kept outside streamed geometry so state survives unloading
and late joins. Use a door with **E / B or Circle / touch USE** to open its room
panel, then choose **Open / close door**, **Rent ($10 / 30 minutes)** or
**Purchase ($100 / until server restart)**. New offline wallets can afford rental;
local editor wallets can also afford purchase. The renter's name appears on both
sides of the moving leaf. Owners can toggle the lock, grant/revoke access for
connected players, or release the room without a refund. Locking does not close an
open door: close it separately when its swing area is clear.

### Guest-room tenure contract

`guest_door.gd` specializes SwingDoor only for these eighteen actual guest rooms.
Classic/modern/Deco public salons, study keys, portals and **Lily Apartments' free
reservations** are unchanged. No apartment unit, elevator or companion API is used
or replaced. This adds no rooms, geometry, new keys or input bindings.

Each always-present door owns one server-side tenure and pending payment receipt.
The existing NetworkedInteraction validates transport sender, exact payload, live
player, range, owner and selected connected guest; guests may open/close, never
change ownership or permissions. SwingDoor retains physical collision, swing-away
animation, player obstruction checks and shared audio. A locked door blocks
unauthorized operation from the gallery, not tailgating through an open door.
Anyone on the room side may operate it to escape, including after access revocation.
No client movement enforcement or private room instance is introduced.

Public occupant name, tenure, payment reservation, lock, guest peer list and leaf
state replicate through NetworkedInteraction, including spawn snapshots. Stable
account identity and receipts never replicate. Signed-in owners reclaim control
on reconnect; guest owners vacate on disconnect, and guest access always expires
on that guest's disconnect. Respawns retain tenure. Rental time advances on the
server even when the room unloads or an account disconnects. Expiry/release keeps
the leaf in place rather than slamming collision through occupants.

**All tenure is server-session memory**: restart/redeploy/network-mode change
clears rentals and purchases, with no refunds. Prices and these limits are visible
before payment. Account money remains persistent through PlayerMoney alone.
Payments freeze the vacancy before deferring `PlayerMoney.charge`; failure never
grants a room. Uncertain responses reserve the door for the same identity/choice
and retain the exact operation ID for retry. Terminal rejection releases the
reservation. There is no permanent property database or API change.

The modal scrolls between a fixed heading and Close button on phones, supports
controller button focus, and closes on range loss/death. Desktop Esc / controller
Back also closes it. All devices use the existing Use action.

Tests: `test_guest_rooms.gd`, `test_guest_payment.gd` and
`test_guest_network.gd` cover actual wallet charges, contention, permission/range
validation, obstruction, lifecycle, uncertain/delayed receipts, unchanged placements
and real ENet client requests / late joins / disconnects. For a rendered door and
phone/landscape panel probe (output: `/tmp/hotel-{door,phone,landscape}.png`):

```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \\
  res://tests/features/hotel_annex/guest_visual_probe.tscn
``` Both wings register with GPS
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

## Indoor visibility

`interior_lighting.gd` on the feature root applies warm ambient fill (energy 0.8)
while the active camera is within either existing streamed-room bound. This covers
all three hotels, storage, sewers and every atrium floor, even at midnight or when
phones limit local lamps to two. Existing lamps still add contrast. No new lights,
shadows, controls or replicated state are added.

The camera receives a private Environment copy; the outdoor environment is never
modified. The shared sky and its day/night brightness keep updating. Leaving the
hotel, changing cameras (including F3), or removing the feature restores the prior
camera environment. This is local presentation for every peer and offline play.
