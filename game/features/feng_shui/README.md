# Lazy room Feng Shui

`room_harmony.gd` (`FengShuiRoom`) is an engine-facing library. There is no loaded
`feature.tscn`, new UI, control or gameplay modifier. Luck, money, blessings, health
and safe-zone rules are unchanged. Keep one scorer per room in its owning feature.

## Furnished rooms and default elements

Existing hotel, casino (including the bundle), street and procedural props already
have default elements through `furniture.gd`. It uses existing `prop_id` metadata,
or semantic node names for older furniture, rather than guessing from painted
textures. Each prefab contributes **one unit**, not one per mesh or collider.
Numbers in names (`Rack0`, `Rack1`) do not change their classification.

| Element | Default examples |
| --- | --- |
| Wood | Plants/planters, tables, chairs, beds, sofas, counters, wooden crates, books/cards |
| Fire | Lamps/sconces, bulbs, chandeliers, heaters, radiators, monitors/televisions |
| Earth | Ceramics, textiles, soap, otherwise unidentified furniture |
| Metal | Slot machines, cars, barrels, fans, clocks, phones, carts, bins, keys |
| Water | Fountains, pumps, drinks/glasses, bottles, pitchers, ice buckets |

These are deliberately simple game defaults, not a traditional Feng Shui assessment
or a claim about every object's real material. Keyword precedence is fire, water,
wood, metal; remaining objects are earth. The token lists in `furniture.gd` are the
single source of defaults. For example a brass chandelier is fire, a wine rack is
water, and a wooden-looking barrel defaults to metal unless overridden.

For new or changed furniture, set **one metadata field on the furniture root** in
the Godot Inspector (Metadata), or in its scene:

```ini
[node name="UnusualCabinet" type="Node3D"]
metadata/feng_shui_element = "wood"
```

Values are `wood`, `fire`, `earth`, `metal`, `water`. `none` excludes that node and
its whole subtree, useful for structural or cosmetic objects with ambiguous names.
Overrides take precedence over defaults. Unknown values are rejected, not silently
converted to earth. Children within a prefab are parts of that object; place separate
decor objects as siblings if they should contribute additional elements.

The adapter derives conservative X/Z footprints from mesh AABBs and box/cylinder/
sphere CSG primitives, including nested rotations, offsets and scale. Collision
padding and interaction areas do not inflate them. GridMap architecture, character
bodies and named floors/walls/ceilings/ramps are excluded. Unknown loose meshes are
earth furniture; mark unusual architecture `none` rather than relying on its name.
No material, imported mesh or scene-placement changes are required.

Furniture wholly outside the floor contributes nothing. Crossing footprints are
clipped during scoring. Tabletop/raised decor and wall/ceiling fittings contribute
elements but not floor occupancy. An object counts as floor-standing when its mesh
minimum Y is at most `floor_height + 0.3` metres (default floor height is zero).
For multi-floor scenes, select the appropriate room subtree and floor height; a
whole district/interior scene is not automatically partitioned into separate rooms.

## API

### Static authored rooms (also on a dedicated server)

```gdscript
const Harmony := preload("res://features/feng_shui/room_harmony.gd")
var harmony := Harmony.new()

func configure_room(anchor: StreamedRoom, entrance_xz: Vector2) -> bool:
    var bounds := anchor.bounds
    var floor_rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
    return harmony.set_scene_layout(
        floor_rect, entrance_xz, load(anchor.room_scene) as PackedScene
    )

func harmony_when_needed() -> Dictionary:
    return harmony.evaluation()  # Check valid before applying any future effect.
```

`set_scene_layout(floor_rect, entrance, scene, floor_height = 0.0) -> bool` copies
the PackedScene state and invalidates the cache. Geometry is read only on the first
query. The reader walks authored SceneState data (including nested scene instances,
inherited scenes and instance overrides) into temporary **script-free** nodes,
then frees them. It never runs `_init`, `_ready`, gameplay code or adds Content to
an unloaded StreamedRoom. Loading the resource itself is the caller's responsibility.
A null/empty scene or invalid floor/entrance/height preserves the previous layout.
Invalid furniture metadata or too many footprints found at evaluation produces a
cached `valid: false` result; fix the scene and configure again.

### Runtime-generated rooms

`set_furnished_layout(floor_rect, entrance, room_root, floor_height = 0.0) -> bool`
snapshots an already-generated subtree, copies its geometry/elements, and invalidates
the cache **without scoring**. It retains no nodes: freeing, moving or unloading
the source afterward does not change the score. Call it again after furniture changes.
Invalid replacements preserve the last valid layout/cache.

Script-only interiors such as `apartments/lobby_content.tscn` contain no authored
furniture: use this generated-subtree API after their owning builder has produced
geometry, not `set_scene_layout` on an empty recipe. The scorer does not execute room
builders or pretend to discover furniture that has not been generated. This boundary
keeps existing streaming and procedural ownership unchanged. Future authoritative
effects need server-owned generated snapshots, not client-only streamed Content.

### Existing explicit layout API (unchanged)

- `set_layout(floor_rect, entrance, footprints, elements) -> bool`: atomically replace
  a defensive snapshot, without evaluating. Element weights are exactly five finite,
  nonnegative values in **wood, fire, earth, metal, water** order, with a finite sum.
  This remains useful for builders with declared placement AABBs or custom weights.
- `evaluation() -> Dictionary`: return `valid`, `score` (0..100), and normalized
  `components` (`entrance`, `centre`, `space`, `elements`, each 0..1). Defensive deep
  copies prevent callers mutating the cache. Unconfigured/cleared results are invalid,
  score zero, with empty components.
- `score() -> float`: convenience access, zero if invalid.
- `clear()`: discard layout, pending scene and cache.

Use one **room-local X/Z plane in metres** (`Vector2.y` means Z). Root placement in
world space is ignored. The entrance must be inside or on any floor edge. Rectangles
need positive, finite, geometrically representable dimensions. Up to **512** footprints
are supported (raised from 128 for furnished interiors); excess layouts fail explicitly,
never silently truncate. Arrays are copied. Replacing a layout multiple times before a
query evaluates only the last replacement. Authored mesh resources should be immutable;
for mutable runtime geometry, use the generated snapshot API.

## Scoring model (v1)

This remains a simplified **game abstraction**, not Flying Stars or a heavenly/calendar
simulation. Each component contributes 25 points:

| Component | Normalized rule |
| --- | --- |
| Entrance | Distance to nearest occupied footprint / 1 metre, capped at 1 |
| Centre | Unoccupied fraction of the central rectangle (middle 20% of each floor axis) |
| Space | Unoccupied fraction of the entire floor |
| Elements | `1 - sum(abs(weight / total - 0.2)) / 1.6`, clamped to 0..1 |

Equal element weights score 1; one element scores 0; no elements score a neutral 0.5.
Overlap counts once using exact rectangle union. Empty balanced rooms score 100;
empty unspecified rooms score 87.5. Explicit weights remain independent of footprints.

## Lazy cost and multiplayer boundary

No processing, timers, clock, startup scoring, RPCs or persistent player state are added.
The first query computes bounded O(n² log n) spatial unions; subsequent queries read
that room's cached result. Unqueried scenes never incur geometry traversal or evaluation.
No global registry leaks room state across sessions. Future shared luck/health consumers
must query server-owned layouts and use existing validated NetworkedEntity/wallet/combat
interfaces for their effects. Never trust a client-supplied score. Offline peer 1 can use
the same API; late joins, disconnects and respawns introduce no new protocol here.

## Tests

```sh
# From game/
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/feng_shui -gexit
```

Tests retain the original scoring/cache regressions, exercise all 169 existing reusable
props, real static interiors and generated apartment furniture, metadata overrides,
scene instance transforms, script-free reading, non-occupying decor, layout replacement,
unloaded-room scoring and input/output isolation.
