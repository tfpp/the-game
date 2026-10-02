# Operations garage

New joins, fall recovery and combat respawns start in this shared concrete garage.
Walk to the van's driver side and press **E / B or Circle / touch USE**. Pick a
numbered destination on its schematic route map: **The Golden Crown**, **Basement
Garage B1**, or **Street District**. A two-second engine-start/acceleration sound
and opaque driving screen precede travel. Buttons support touch and controller
focus; the list scrolls on small/landscape screens. Esc / Back to garage dismisses
an unsubmitted map. There is no extra key or purchase.

The walking exit reaches the casino without the driving screen. Return through
**OPERATIONS GARAGE** on the casino north promenade at (-7, 1.1, -19.7), or find
**Operations Garage** in GPS. The street's existing casino entrance returns to the
Crown; the basement garage's existing return portal reaches the dev room, whose
exit reaches the casino. Existing elevator, shop and slum-gate behavior is unchanged.

## Ownership and integration

- `Room` is a `StreamedRoom` at (0,0,-3000), bounds x ±8.2, z ±9.2, y -1…6.
  Only static GridMaps, fixtures and workshop props live in `interior.tscn`.
  Van, collision, authenticated endpoints and markers remain on every peer.
  `starter_room.gd` checks the local initial/respawn position before player physics
  and preloads the base floor while the server assignment is in flight. Dedicated
  servers skip it; subsequent content lifetime stays with RoomVisibility.
- `Spawn` joins `player_spawn`. Game's initial/fall spawn and Combat's respawn use
  its world position plus their existing ±3m jitter. Without a marker, each retains
  its old fallback. The entire spawn square is clear of the van and workshop props.
- Structure uses the casino's **1 × .25 × 1m GridMap** and existing floor/wall tile
  shapes/transforms, copied to `garage_tiles.tres` with existing concrete materials.
  Separate east/west and north/south grids preserve corner panels. Floor top is y=0,
  ceiling bottom 4.75m; two shadowless lights illuminate the room.
- `OperationsVan` uses `NetworkedInteraction.register_use/request_use` to open a
  private map. Its `travel` action accepts exactly one integer `zone`, resolves only
  configured existing arrival markers, and validates the authenticated player,
  range, pending trip and Combat's `is_respawning()` again on the server.
- Pending trips are server memory, per peer (no van-wide cooldown). Death,
  disconnect, walking away and network mode changes cancel them. After two seconds
  the server calls the existing owner `server_teleport` and `SlumRuns.finish()` like
  existing development portals. No new excursion, private instance, money, loot or
  persistence system is introduced. Late joiners see the same static base, not old
  transitions. Offline uses the same authority path.
- The owner-only departure event preloads a destination StreamedRoom before the
  teleport. The destination button recaptures the pointer inside its user gesture;
  the noninteractive transition preserves that lock while `modal_ui` blocks gameplay.
  The modal closes when the player arrives, on death/session changes, or after a
  bounded timeout. GameAudio owns the shared `van_departure` UI cue and bus.

## Assets and review

Van: one indexed 176-triangle mesh, one 128×128 painted atlas, floor-centred pivot,
5m long × 2.2m wheel width × 2.25m high, front **+Z**. The simple gameplay collider
is separate. Rolling shutter: one static mesh using an existing small steel-like
texture. Cabinet, crate and barrel reuse the procedural prop kit.

Authoritative native builder, exact UV guide, original painting and prompt:
`docs/design/model-sources/operations-van/`. Normal rebuilding preserves approved
paint. See that README for commands. Actual Compatibility renderer captures under
`docs/design/previews/operations-garage/` include arrival, rear, underside, route map,
phone layout and driving screen. No browser performance claim is made.

```sh
# From game/
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/starter_room -gexit
# Requires a display (xvfb-run works in CI):
godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/starter_room/capture.tscn -- /tmp/operations-garage
```

Tests cover spawn fallback/override, actual initial floor contact, spawn and approach
clearance, indexed winding/UVs/budget, all real arrival links, streamed floor preload,
excursion finish, validated requests, cancellation, concurrent preparation, modal
cleanup and real ENet sender/private-event/late-join/disconnect behavior.
