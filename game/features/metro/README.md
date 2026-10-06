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

The loop is **Crown → Market → Works → Residences → Crown**. Four logical services
run one stop apart: 1.2 seconds opening, 12 seconds boarding (the last two warn),
1.2 seconds closing and 10 seconds traveling. Each station sees a train every
24.4 seconds. Ride multiple stops by remaining aboard. Metro stations and cars
permit combat; the destinations retain their existing safe areas.

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

## Track hazards

Arriving and departing trains kill players whose server-observed capsule overlaps
their swept path at any station, including jumping players. Stay on the platform;
parked trains, the hidden tunnel reset and the separate ride compartments do not
cause train damage. This works offline and on every device without new controls.

MetroService checks the existing timetable's visible motion segments against the
native train bounds (3.15 × 3.66 × 114.3 m), with capsule clearance and a longitudinal
sweep to avoid fast trains skipping targets between ticks. No moving physics bodies
or streamed visuals are required on the server. Validated boarding passengers still
inside their cabin awaiting readiness are protected; leaving it removes protection.
Combat.apply_damage owns the normal death screen, delayed respawn and death listeners,
with self attribution so environmental impacts award no player kills. Metro's existing
death callback clears passenger manifests and pending transfers. No new persistent
state or RPC is introduced; late joiners use the current replicated timetable.

## Runtime and performance

`MetroService` owns the clock and passenger manifest through `NetworkedEntity`.
Clients cannot choose a destination, passenger ID or teleport pose. Boarding uses
server-observed capsule position, a closed-door cutoff and an owner-specific loading
token. Teleports use the existing player-authority RPC. Elevator groups validate
capacity, presence and destination eligibility before committing.

Station trains accelerate into short, dark tunnel mouths. Riders transfer to a
stationary, full five-car compartment with the same relative position/yaw, passing
lights, rail hum and slight camera vibration. They remain free to move and fight.
No train physics, route simulation or scenery runs between destination rooms.

Eight persistent `MetroZone` anchors share two streamed presentation scenes. The
existing RoomVisibility owner loads only the current room and temporary arrival
preloads. Detailed train meshes are absent from the dedicated server. Its shared
collision-only kits support weapon rays and boarding; parked collision changes
once per phase rather than following the animated departure mesh every frame.
Elevator controllers remain present at matching network paths. Their nearby visuals
are culled separately. Existing shared-player replication is unchanged.

Readiness waits for an actual destination floor. A late departure stays at its
already-loaded platform. A failed arrival stays in the safe carriage and retries a
platform readiness handshake. Tokens expire and cannot be reused across requests.
Death, disconnect and removed connectors clear pending transfers. Carried inventory
stays on the player; the existing holdables owner moves `ThrownItem` drops (including
dropped weapons) with their flight segment and network identity intact.

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
put. Skeleton animation updates only within 28 m of the local rider; unloaded
rooms have no resident models or per-frame work.

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
0–10 within that station. Registration creates both elevator endpoints and a GPS
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
trip, and public-room connector coverage. Full verification: `harness/verify.sh`.

Check cross-feature elevator clearance in the complete live game with
`godot --headless --path game res://features/metro/tools/audit_live.tscn`.
