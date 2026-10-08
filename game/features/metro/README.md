# Metro loop and R44 train

Five furnished cars for the metro, with 1980s-style fictional graffiti,
opposing cab ends, four paired boarding doors on each side, underbody hardware,
car numbers 5408–5412 and a muted, coarse-pixel finish matching Casino Royale.
The five-car formation and mixed-era decoration are game adaptations.

## Inspect it

Open `preview.tscn` in Godot and run the current scene (F6), or run:

```sh
godot --path game res://features/metro/preview.tscn
```

- F1: exterior view; F2: walk inside using the existing player controller.
- Arrow keys: move; Shift: jump; Esc: release the mouse.
- L / R: toggle the train's left / right doors; O / C: open / close all doors.
- Commands wait until the current door animation finishes. Review platforms beside
  the first car let you walk through its entrances.

Blender source: `docs/design/model-sources/r44-metro/r44_five_car_set.blend`.
It includes packed artwork and imported door actions. Scrub frames 1–30 to see
its active `close_all` action move from open to closed. The saved pose is open.

## Model and animation

`r44_five_car_set.tscn` is the native reusable assembly. Each `Car01`…`Car05`
contains `CabinStructure` (GridMap), `PassengerFurniture`, `SeatCollision`,
`DoorL1A`…`DoorR4B` (16 AnimatableBody3D leaves), lights and trucks.
The cars contain orange/ochre molded seats, wood-look panels, pale curved ceilings,
fluorescent diffusers, steel poles/rails and transparent side/door windows.

The root `Doors` AnimationPlayer provides `open_left`, `close_left`, `open_right`,
`close_right`, `open_all`, `close_all`. Each clip lasts 1.2 seconds; leaves slide
0.74 m into real wall pockets. Left/right refer to the train's +Z forward direction,
including the reversed rear car. Play clips from their corresponding starting
pose; the metro timetable controls the platform side and clears the boarding threshold.
Door collision travels with the leaves. Open entrances clear the existing player
capsule; floor, walls and seats have collision. End partitions remain closed.

- Metres, +Y up, front +Z; assembly origin is rail level at mid-consist.
- Car centres: Z = 45.72, 22.86, 0, -22.86, -45.72 m; last car rotated 180°.
- Bounds: 3.15 × 3.66 × 114.3 m. Floor height 1.20 m above rail level.
- 40,322 instanced triangles; six shared materials; 80 moving leaves; ten trucks.
- Four atlases: metal/interior/graffiti 128×128, exact livery 128×64; nearest mipmaps.
- CouplerFront / CouplerRear: local Z ±11.43 m, Y 0.74 m.
- Cab and trailer scenes are undecorated base cars; animation clips belong to the
  five-car assembly. GLB exports flatten GridMaps into portable meshes and retain
  the train's animation clips. Use the native scene for Godot collision.

`feature.tscn` loads the shared metro automatically. The asset preview remains
available independently of the live service.

See [authoring and validation](../../../docs/design/model-sources/r44-metro/README.md).

## Travel

Public travel rooms now have a METRO elevator. Call it, enter, and close the doors
(or wait for its normal door cycle). It holds four riders. At the station, use the
countdown and board through a platform-side doorway before closing starts. Missing
that cutoff leaves you on the platform for the next train. Existing direct routes,
warps and the private slum excursion elevator remain available.

The two directions are **Crown → Market → Works → Residences → Crown** (uptown)
and **Crown → Residences → Works → Market → Crown** (downtown). Four services
run one stop apart in each direction: 1.2 seconds opening, 12 seconds boarding
(the last two warn), 1.2 seconds closing and 18 seconds traveling. Each track sees
a train every 32.4 seconds. Trains stop on opposite sides of a 12 m-wide island
platform, with independently opened platform-side doors. Track centres are x=0
and x=16; the platform extends from x=2 to x=14 at y=1.2.
Ride multiple stops by remaining aboard. Metro stations and cars
permit combat; the destinations retain their existing safe areas.

Every train runs the same trip (`MetroRules.distance` / `speed`): 300 m between
stations, 7.5 s accelerating, 3 s cruising at about 103 km/h, 7.5 s braking. The
acceleration (at most 4.4 m/s², under half a g) builds up and eases off over a
second at each end, so trains creep away from platforms and settle into them
without jolts. The station view, the window scenery, the rail rumble's pitch and
the ride's rattle all sample that one profile.

| Station | Room elevators |
| --- | --- |
| Crown | Golden Crown, Gaming Suites, Grand Lounge, Wine Cellar, Backroom Book, eligible discovered VIP destination |
| Market | Strip Mall, Rusty Hogg |
| Works | Operations Garage, Street District, Shooting Gallery, Dev Room; Gnome Tunnels when enabled |
| Residences | Hotel Wing, Hotel Atrium, Lily Apartments lobby, developer-only Hotel Props |

The shipped scene currently enables 16 of these connectors. The existing gnome
feature is excluded by the main scene; its authored connector is ready if that
feature is enabled again.

Apartment resident floors stay behind the resident elevator. The VIP metro exit
requires both prior discovery and current eligibility; it calls the VIP owner's
entry/leave methods. Hotel Props retains its developer gate. Room-owned cleanup,
including refunds when leaving the betting room, continues to observe player location.

## Casino wall recess (#540)

The Golden Crown connector is recessed into the south wall, west of the entrance
corridor, at `(-12, 0, 19.8)` facing north. The cab occupies the unused former-shop
floor behind the wall instead of the promenade. Its existing METRO sign, call
button, four-rider limit, Use controls and Crown station exit are unchanged;
registration moves the GPS marker with it. Other room/station elevators and the
north-wall excursion elevator are unchanged. The saved casino GridMaps and
`casino_hub/gridmap/metro_alcove.gd` own the doorway; no runtime geometry changes.

## Track hazards

Arriving and departing trains kill players whose server-observed capsule overlaps
their swept path at any station, including jumping players. Stay on the platform;
parked trains, the out-of-sight hand-over between the departing and arriving train
and the separate ride compartments do not cause train damage. This works offline and
on every device without new controls. The victim hears an original heart-monitor
beep and flatline (`metro_flatline`, a homage to the shooter-classic death cue, not
sampled game audio); bystanders hear it from the tracks.

MetroService sweeps the departing and arriving trains separately against the
native train bounds (3.15 × 3.66 × 114.3 m), with capsule clearance and a longitudinal
sweep to avoid fast trains skipping targets between ticks. No moving physics bodies
or streamed visuals are required on the server. Validated boarding passengers still
inside their cabin awaiting readiness are protected; leaving it removes protection.
Movement is client-authoritative, so after the metro teleports someone off a departing
train (to the ride, or back to the platform after the cutoff) the server briefly still
sees their old cabin position. Passengers and riders shielded that cycle are therefore
safe while that stale position is inside the parked train's cars, never on the tracks.
Combat.apply_damage owns the normal death screen, delayed respawn and death listeners,
with self attribution so environmental impacts award no player kills. Metro's existing
death callback clears passenger manifests and pending transfers. The flatline is a
transient NetworkedEntity event, so late joiners never replay past impacts. Rebuild it
with `godot --headless --path game -s res://features/metro/tools/build_flatline.gd`.

## Runtime and performance

`MetroService` owns the clock and passenger manifest through `NetworkedEntity`.
Clients cannot choose a destination, passenger ID or teleport pose. Boarding uses
server-observed capsule position, a closed-door cutoff and an owner-specific loading
token. Teleports use the existing player-authority RPC. Elevator groups validate
capacity, presence and destination eligibility before committing.

Station trains pull out into short, dark tunnel mouths; the view hands over to the
next train at mid-trip, while both are behind the tunnel end walls. Riders transfer
to a stationary, full five-car compartment with the same relative position/yaw.
They remain free to move and fight. No train physics or route simulation runs.

Instead, the ride's `Scenery` slides along +Z (uptown) or −Z (downtown) by the
distance covered, so the windows show the trip in reverse: the station just left (a copy of the platform,
its benches, boards and residents), 166 m of tunnel, then the next station, which
lines up exactly as the doors open. The tunnel carries window-height lamps whose
light sweeps through the cabin, cables, tags from the R44's own graffiti atlas,
three block signals that drop to red behind the train, refuge niches with blue
alarm lamps and a columned stretch beside an older parallel track. Scenery has no
collision. `passing_surface.gdshader` keeps world-anchored textures riding with it;
lights beyond 60 m are switched off, and the ride's render bounds let riders see
along the platforms. Rail rumble pitch/volume and camera rattle follow the speed.

Twelve persistent `MetroZone` anchors share station, forward-ride and reverse-ride
presentation scenes. Each station owns seating on both tracks. The
existing RoomVisibility owner loads only the current room and temporary arrival
preloads. Detailed train meshes are absent from the dedicated server. Its shared
collision-only kits support weapon rays and boarding; parked collision changes
once per phase rather than following the animated departure mesh every frame.
A validated departure retains its supporting collision until readiness succeeds
or its bounded loading timeout returns the rider to the island.
Elevator controllers remain present at matching network paths. Their nearby visuals
are culled separately. Existing shared-player replication is unchanged.

Readiness waits for an actual destination floor. A late departure stays at its
already-loaded platform. A failed arrival stays in the safe carriage and retries a
platform readiness handshake. Tokens expire and cannot be reused across requests.
Death, disconnect and removed connectors clear pending transfers. Carried inventory
stays on the player; the existing holdables owner moves `ThrownItem` drops (including
dropped weapons) with their flight segment and network identity intact.

## Island stations and entrance ironwork

All metro elevators reuse the existing 3.2 m cabin and destination permissions.
Green entrance posts and green/white globe lamps identify both endpoints;
station-only GridMap shafts join the cab roof to the ceiling at y=5.475.
No new texture images are needed: ironwork, lining and doors reuse the small
painted-concrete, rust and plaster atlases already shipped in the project.

The station identities share a collision kit, with distinct saved dressing:

- **Crown:** faded cream panels and ochre trim.
- **Market:** exposed brick, rust-red trim and spray paint.
- **Works:** blue-grey trim, overhead ducts and service panels.
- **Residences:** peeling sea-green panels and neighborhood signage.

Both directions have their own departure boards, seat providers, boarding checks,
track hazards, recovery positions and GPS links. Reverse rides pass the platform
layout to the left, with reverse-scrolling scenery and textures.

## Transfer reliability and rendering

Departure cleanup ignores riders already in the passenger manifest. Otherwise,
a successful owner teleport could be followed by another platform teleport while
the server still had the owner's previous cabin position. Cabin validation also
includes crouching, jumps and positions beside seats. Train transfers keep the
owner's current viewing direction. Readiness tokens cancel obsolete loading loops;
an unusual arrival pose retains its transfer until it can finish or recover.

The native R44 source stays editable. The offline builder merges static car
surfaces by material and puts the 16 animated door leaves of each car in one
MultiMesh. Animation still owns the original leaf transforms and collision;
`MetroDoorBatch` copies poses only when aperture changes, with a separate MultiMesh
per instance. Stations and both ride scenes reference the saved train scene,
sharing its baked meshes instead of embedding additional copies.
Elevator signs rebuild only when their displayed text changes.
Servers use the collision-only station kit without duplicate colliders in streamed
presentation. Unloaded MetroZones have no frame callback.

Run the fixed-camera rendering census at 1280×720 with:

```sh
godot --path game --audio-driver Dummy --rendering-method gl_compatibility \
  --resolution 1280x720 res://features/metro/tools/performance_probe.tscn
```

On Apple M1, Godot 4.7.2 Compatibility, the same station camera changed from
**863 to 691 draw calls** with two trains instead of one; the ride camera changed
from **552 to 379**. These are native fixed-view draw counts, not browser FPS.
The second train and station dressing increase visible station triangles
(77,994 → 124,570); batching reduces submissions, not geometry. The probe also
reports primitives, mesh counts and scene nodes so that tradeoff stays visible.

`tools/station_details.gd` authors shared elevator ironwork, shafts and station
identity layers; `tools/batch_train.gd` authors the rendering batches.
`tools/build_realm.gd` remains the complete reproducible recipe. Runtime
architecture remains GridMap/MeshLibrary based.

## Seats and sheltering residents

Board first, then Use a free orange lengthwise bucket: **E / B or Circle / touch USE**.
Each car has ten usable buckets facing its aisle. Use again, move or Jump to stand
in the clear centre aisle. Looking, aiming and the existing seated avatar work in
first/third person and on other peers. Seats stand riders up at the two-second
departure warning, and four seconds before the arrival cycle ends; board/ride
transfers then use their original position, readiness and authority rules. Sit again
once aboard the ride compartment or the next parked train. This is deliberately not
moving-train attachment physics.

Each permanent MetroZone owns a `MetroSeating` (FoodCourt subclass) and
NetworkedInteraction endpoint outside streamed Content. The inherited server-owned
`net_seats`, validated sit/stand actions, single-provider exclusion, local player
pinning, avatar `seating` queries and death/disconnect/teleport/session cleanup
remain the only seating implementation. Metro additionally checks that riders are
alive, actually aboard a parked/ride train, outside the transfer warning window,
and not waiting on a loading token. Occupancy replicates to observers and late
joiners; no seat state persists. Food court, casino and table seating are unchanged.
Cushions are y=1.68 (native R44 floor 1.2 + molded bucket surface 0.48); exits are
floor-relative x=0 with real capsule clearance. Two other left buckets per car
remain reserved for sleepers.

People sheltering in the metro bring all five cars and all four stations to life:
two slumped sleepers and one strolling resident per car, plus four bench sleepers
and three platform walkers at each station. They are unnamed, non-hostile ambient
residents, not combat targets, quest NPCs or sources of money/loot. They reuse
PatronModel's existing skinned avatar, clothing and poses without casino named
looks, new meshes/textures, lights or colliders. Doorways, aisles, boarding and
elevator approaches remain passable.

`MetroResidents` is streamed presentation only: bounded out-and-back walks and
rests sample the existing server-owned metro clock/cycle. There is no separate
client simulation, NPC state or network endpoint inside the room. Reloading or
joining mid-cycle samples the current pose rather than restarting a route.
Train residents follow the train's departure presentation; platform residents stay
put. Skeleton animation updates at 15 Hz within 28 m of the camera; residents beyond
56 m are hidden. Train transforms still follow each rendered frame. Unloaded rooms
have no resident models or per-frame work.

Tests cover authority, occupancy, automatic standing/boarding, original booth
exclusion, capsule/floor placement, streamed lifetime, residents' bounds/facing,
and WebSocket owner/observer/late-peer requests and disconnect cleanup.
For native visual review, run
`godot --audio-driver Dummy res://tests/features/metro/residents_visual_probe.tscn`
from game/. It captures platform, cabin and seated first/third-person views to
`/tmp/metro-residents-*.png`.

## Adding future travel rooms

Add one `MetroAccess` Node3D to the permanent room anchor, **outside streamed Content**.
Set a stable `zone_id`, player-facing `label`, station index 0–3 and unused `slot`
0–10 within that station. Station cabs face west from x=6.4; their shafts reach
the ceiling, leaving clear lanes along both platform edges. Registration creates
both elevator endpoints and a GPS
marker automatically, including markers added after startup. Do not hand-build RPC
endpoints inside streamed scenery. Choose `public`, `developer`, or `vip` policy;
VIP connectors also need `vip_path` pointing to their owning `VipLounge`.

The marker is the cab threshold, at floor height, with +Z facing the room. Reserve
3.2 m width, 3.2 m depth behind the marker, 2.55 m headroom and a clear approach.
Keep this footprint inside the owning room's bounds. Build any added room shell
with GridMap tiles. The placement test checks real capsule clearance and floor;
the scene-catalog test rejects new authored public streamed rooms without a connector.
Private generated excursions/resident floors intentionally use their existing gates.

## Preview and checks

Run `realm_preview.tscn` for the actual service: F1 platform, F2 ride compartment,
F3 elevator bank, F4 walk/board, Esc releases the mouse. The full game exposes the
same service through room elevators and GPS. Rebuild the saved kits with:

```sh
godot --headless --path game res://features/metro/tools/build_realm.tscn
```

GUT coverage in `tests/features/metro` includes all 40 train entrances, native player
boarding, all 17 room connectors, timing and missed trains, elevator round trips,
loading recovery, item flight preservation, a real server/owner/observer/late-peer
trip, and public-room connector coverage. `test_metro_motion.gd` checks the trip for
jolts, the out-of-sight hand-over, platform alignment at both ends, scrolling
textures, signals, the light budget and speed-scaled rumble and rattle.
Full verification: `harness/verify.sh`.

Check cross-feature elevator clearance in the complete live game with
`godot --headless --path game res://features/metro/tools/audit_live.tscn`.

## Platform drop-offs (#538)

`MetroService.deliver(player, position, yaw)` carries one player to a platform point
using the same readiness handshake (`MetroTransfers` kind `wake`): the client loads the
station and reports its floor, then the server teleports the owner and emits
`delivered(peer)`. Expired handshakes retry; `cancel_delivery(peer)` abandons only a
`wake` transfer. It refuses dead, respawning, instanced or already-transferring
players and removes any stale passenger entry. `features/booze` uses it to wake
blacked-out drinkers in the lanes beside either track (`platform_recovery` x).
