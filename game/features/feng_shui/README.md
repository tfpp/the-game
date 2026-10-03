# Lazy room Feng Shui

`room_harmony.gd` (`FengShuiRoom`) is an engine-facing, tree-independent library.
There is deliberately no `feature.tscn`, new UI, key, scene placement or gameplay
modifier. Luck, money, blessings, health and safe-zone rules are unchanged.

## API

Keep one instance per room in the owning feature. Supply an explicit layout snapshot:

```gdscript
const Harmony := preload("res://features/feng_shui/room_harmony.gd")

var harmony := Harmony.new()

func configure_room() -> bool:
    var furniture: Array[Rect2] = [Rect2(-5, 2, 2, 2)]
    return harmony.set_layout(
        Rect2(-5, -5, 10, 10), Vector2(0, -5), furniture,
        PackedFloat64Array([1, 1, 1, 1, 1])
    )

func harmony_when_needed() -> float:
    return harmony.score()  # 0..100; first query computes, subsequent queries reuse
```

- `set_layout(floor_rect, entrance, footprints, elements) -> bool`: replace inputs
  atomically. Successful replacement only invalidates the cache; it does not score.
  Arrays are copied. If furniture, entrance or decor changes, call this again.
  Mutating the original arrays afterward does **not** update the snapshot.
- `evaluation() -> Dictionary`: lazily return `valid`, `score`, and `components`
  (`entrance`, `centre`, `space`, `elements`, each 0..1). Returned dictionaries are
  defensive deep copies. An unconfigured/cleared room returns `valid: false`,
  `score: 0.0`, `components: {}`; consumers should check validity before effects.
- `score() -> float`: convenience access to the score; zero if unconfigured.
- `clear()`: discard layout/cache, e.g. when replacing a room or resetting a session.

All coordinates use **one room-local X/Z plane in metres** (`Vector2.y` means Z).
Rectangles specify minimum corner and positive size; rotated props should use
conservative axis-aligned footprints. Project `StreamedRoom.bounds.position/size`
X/Z for the floor and authored `ProceduralPopulationRule`/population AABBs for
furniture. Use bounds at the same local transform, not global furniture coordinates
against a local floor. Do not inspect streamed `Content`: it may not exist on the
server. Rectangles model floor occupancy, not walls, ceiling lamps or characters.
No geometry is automatically discovered and no element is inferred from a material.

Inputs must be finite and geometrically representable (including the central area).
The entrance must lie inside or on any floor edge. Supply exactly five nonnegative
finite element weights, in **wood, fire, earth, metal, water** order, with a finite
sum. Zero weights are valid. Up to 128 positive-area footprints are accepted;
footprints crossing the floor are clipped, and wholly outside footprints ignored.
Invalid replacement returns false without changing the last valid layout or cache.

## Scoring model (v1)

This is a deliberately simplified **game abstraction**, not traditional Flying
Stars, a real-world Feng Shui assessment, or a heavenly/calendar simulation.
No wall-clock dependency or implicit time changes are introduced. Future calendar
rules must explicitly provide their context and invalidate results when it changes;
there is no speculative astronomical framework in this change.

Each component contributes 25 points:

| Component | Normalized rule |
| --- | --- |
| Entrance | Distance to nearest occupied footprint / 1 metre, capped at 1; occupied entrance = 0 |
| Centre | Unoccupied fraction of the central rectangle (middle 20% of each floor axis) |
| Space | Unoccupied fraction of the entire floor |
| Elements | `1 - sum(abs(weight / total - 0.2)) / 1.6`, clamped to 0..1 |

Equal element weights score 1; a single element scores 0; no specified elements
score a neutral 0.5. Overlapping footprints count **once**, using exact rectangle
union, not a sum or random samples. An empty room with balanced elements scores
100; an empty room with unspecified elements scores 87.5. Clutter and blocked
entrances/centres lower the result. Footprints and element totals are deliberately
independent: room authors decide which decor contributes each element.

## Lazy cost and multiplayer boundary

There is no node, `_process`, timer, tree traversal, background task, random roll,
or startup evaluation. Layout replacement validates/copies at most 128 rectangles.
The first query after replacement computes bounded O(n² log n) spatial unions;
repeated queries only read the cache and copy the small result. Multiple replacements
before a query collapse into one evaluation of the latest layout. Unqueried rooms
never incur spatial scoring cost. Instances own their cache; no global registry or
persistent state can leak across rooms, players or sessions.

This is pure local computation, so no request RPC, NetworkedEntity or replication
is needed **yet**. Future shared luck/health consumers must keep authoritative
layout snapshots outside client-only streamed content, evaluate on the server
(offline peer 1 follows the same path), and validate requests/replicate resulting
effects using existing `NetworkedEntity`/wallet/combat interfaces. Never trust a
client-supplied score, and do not create a second luck or health authority here.
Late joins, disconnects, respawns and simultaneous players do not alter this library;
they remain the responsibility of the feature consuming the result.

## Tests

From `game/`:

```sh
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/feng_shui -gexit
```

Tests exercise known scores, element scaling, overlapping/clipped/touching occupancy,
entry clearance, central clutter, bounded deterministic layouts, cache hit/invalidation,
input/output isolation, independent rooms, invalid input preservation, and scoring
an unloaded StreamedRoom without constructing its geometry.
