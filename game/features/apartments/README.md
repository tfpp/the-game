# Lily Apartments

Enter the signed door at **(-10, 0, 31)** in the casino's south lobby, next to
(the west of) the lounge. Use at the reception counter speaks to the clerk and
claims a free furnished unit. The prompt replies with your unit and floor. Use
the brass **express elevator** on reception's right to reach your assigned floor;
the matching elevator at the corridor's west end returns to reception. The wooden
CASINO door returns to the casino. All interactions use E, B/Circle, or touch Use.

Each residential floor has exactly ten units, five on each side of a 4m corridor.
Unit 101–110 are floor 1, 201–210 floor 2, etc. The first claim builds floor 1;
claim 11 builds floor 2, and so on, without a fixed floor limit. Units have open
2m doorways, beds and kitchen counters; they are shared visitable spaces, not locked
private instances. The elevator is instant express travel, not a moving platform.

`apartments.gd` owns reservations on the server. `claim(peer)` validates an existing
player and desk range. Only the request's sender is passed by the desk RPC. Allocation
is synchronous/idempotent; no client supplies unit or floor. Account IDs stay in a
server-only dictionary and come from `Network.peer_accounts`, never player input.
Signed-in reservations survive reconnects until server restart/redeploy; talk to the
desk again to restore the assignment. Guest reservations are released on disconnect.
Respawns keep the assignment. Floors never shrink during a session, so remaining
residents and visitors keep their support and exits. Mode changes clear the session.
No money is charged and there is no permanent housing storage.

A server-owned synchronizer replicates public peer-to-unit assignments, including to
late joiners. A custom MultiplayerSpawner builds matching named floor anchors from
floor numbers. Each is a `StreamedRoom` at `(200, floor * 6, 1200)`; reception is at
`(200, 0, 1200)`. Geometry only exists while a local player visits. All RPC-bearing
doors stay outside streamed Content. `resident_elevator.gd` specializes RoomDoor's
destination selection, then reuses its preload, sender/range validation and owner
teleport; a missing replicated floor safely disables travel until it arrives.
Existing elevator and room-door interfaces are unchanged.

Tests: `tests/features/apartments/` covers allocation thresholds, repeated requests,
invalid peers/range, reconnects, guest reuse, late snapshots, preloading and return
travel, and actual collision support/capsule clearance through all ten rooms.

The receptionist reuses the casino's static `salon_dealer.glb` and
`model_materials.gd` finishes. It has no separate NPC simulation or combat state.
No new textures, dynamic lights or frame-by-frame geometry rebuilding are added.

Run `python3 game/tests/features/apartments/network_test.py` from the repository
root for real WebSocket coverage: server/resident/late observer, distant rejection,
replicated claims and floors, idempotence, preloaded lift travel, return and unload.
