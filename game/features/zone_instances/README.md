# Zone instances

Server-owned registry and elevator excursion lifecycle. `ZoneInstances`
(`/root/Game/Features/zone_instances`, group `zone_instances`) holds one
`ZoneRegistry` that records, per instance id:

- its member peers (a peer is in at most one instance);
- the `SlumArrivalPoint` (slum) it uses;
- a world slot: `offset_of(id)` is `x = 4000 m × slot`. Actual private scenes add
  `INSTANCE_ORIGIN` at z = 12000 m; the lowest free slot is reused after cleanup.

An instance is freed (`instance_freed`) when its last member leaves. Callers call
`leave(peer)` on return or death; the node itself removes disconnected peers and
clears everything when the network mode changes. Shared zones (the Crown, its
rooms, gnome doors, the operations garage) are not tracked.

API: `create(peers, arrival) -> id`, `join(id, peer)`, `leave(peer)`,
`instance_of(peer)`, `members(id)`, `arrival_of(id)`, `offset_of(id)`,
`has_instance(id)`. Look it up with `ZoneInstances.registry_for(tree, fallback)`.

The Crown elevator creates a `SlumInstance` for its validated riders after the
doors close. The server selects a registered destination, spawns a garage or Rain
Alleys copy through `InstanceSpawner`, and retains its collision and gameplay.
Each copy has a return cab. Transfer preserves cab-relative position and facing,
waits at least one second and requires an authenticated destination-ready message.
The south lobby gate is scenery; legacy `slum_runs.begin()` remains for development
fixtures. It does not provide a normal-play entrance.

`garage_instance.tscn` and `alley_instance.tscn` are separate destination templates.
Both use `SlumInstance` for the shared lifecycle. The spawner selects the template
from server-owned destination data before applying membership and seeded actors.

`ZoneScope` restricts root spawning, descendant state, events and actions to
members. `NetworkedEntity` discovers this policy through ancestors. Membership is
also published in a shared roster so client-authoritative player movement can be
filtered while retaining player identity nodes for chat and owner teleport RPCs.
Irrelevant remote player visuals and colliders are disabled on clients.

Held items use the same roster policy. Dropped items retain the instance containing
their spawn origin, reject outsider pickups, and are removed when that instance
empties. Initial drop visibility is evaluated before the spawner sends its snapshot;
membership updates synchronously refresh held-item, generated-rig and health
visibility. Generated projectiles carry their origin instance and scope their
impact/explosion effects and splash force. Health snapshots and death notifications
stay within the group; public identity, global chat and leaderboard kill totals
remain available across instances. Player damage cannot cross membership boundaries.

`encounter_points.tscn` supplies saved enemy and supply-crate markers for five garage
floors. `GarageRunPlan` makes server-seeded enemy selections and floor-scaled loot
tables. Plans are sent as spawn data; clients do not roll encounters independently.
New copies get fresh containers without resetting other groups' loot.

Static garage visuals use saved GridMaps behind the existing `StreamedRoom`
lifecycle. The server retains a separate collision-only structure. Real
server/client tests verify group map spawning, late state and cab round trips;
render-mask tests keep the Crown hidden even when a private member noclips outside
the map bounds. Actual main-scene captures review arrivals, return doors and enemy
readability. See `docs/project/phase-one-delivery.md` for evidence and remaining
performance and shipping work.

Tests cover registry lifecycle, real server/three-client map spawning and movement
privacy, held-item/drop visibility and late entry, seeded encounters, floor support,
loot reset, and cab-relative offline travel. Tests live in
`tests/features/zone_instances/`.
