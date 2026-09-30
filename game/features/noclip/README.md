# Noclip

Enable flight access with `sv_cheats 1` in the ~ console, then use **N** or the
`noclip` command to toggle flight. Look up/down and move to fly. Rebind the action
in Settings > Controls if desired; saved custom bindings are retained.

This feature owns `cheats_enabled`, a server-owned synchronizer property included
in spawn snapshots for late joiners. `request_cheats(int)` accepts only 0/1 from
an existing player's actual RPC sender. Any connected player may change it;
requests are processed in server arrival order. It defaults off and resets on
Network mode changes. A departing player leaves the world switch unchanged.

Movement stays client-authoritative, matching the existing player contract; this
is a gameplay gate, not anti-cheat enforcement against modified movement clients.
`toggle()` is the console/key interface. Turning cheats off restores collision
and moves a still-flying local player back to their flight entry position, so they
cannot be stranded in a wall. A server teleport (including respawn) ends flight at
the new destination. Removing/replacing the local player cleans up flight state.
No remote player's movement or collider is manipulated by this feature.

GUT tests cover flight math, gate validation, revocation, teleport/reset cleanup,
and the replication schema. Run `harness/verify.sh` for standard multiplayer smoke checks.
