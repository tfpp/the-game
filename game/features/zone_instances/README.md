# Zone instances

Server-owned registry of slum zone instances (Phase 1 task A1). `ZoneInstances`
(`/root/Game/Features/zone_instances`, group `zone_instances`) holds one
`ZoneRegistry` that records, per instance id:

- its member peers (a peer is in at most one instance);
- the `SlumArrivalPoint` (slum) it uses;
- a world slot: `offset_of(id)` is `x = 4000 m × slot`. Slot 0 is the slum's
  authored position; the lowest free slot is reused after an instance is freed.

An instance is freed (`instance_freed`) when its last member leaves. Callers call
`leave(peer)` on return or death; the node itself removes disconnected peers and
clears everything when the network mode changes. Shared zones (the Crown, its
rooms, gnome doors, the operations garage) are not tracked.

API: `create(peers, arrival) -> id`, `join(id, peer)`, `leave(peer)`,
`instance_of(peer)`, `members(id)`, `arrival_of(id)`, `offset_of(id)`,
`has_instance(id)`. Look it up with `ZoneInstances.registry_for(tree, fallback)`.

Current user: the south lobby gate (`slum_runs`) records its shared excursion as a
single instance. Only one gate instance exists at a time, so it always gets slot 0
and the slums stay where they are authored.

Not done yet: the slum features are still loaded once at startup with fixed node
paths for their loot and enemies, so nothing is instantiated at the offset. Placing
a copy of the slum scene per instance belongs with A3/A4 (client loading and
elevator travel), which will read `offset_of()`.
