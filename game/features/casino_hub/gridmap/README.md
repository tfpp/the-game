# Casino GridMap

`main.tscn` now loads `playable.tscn`, which wraps the saved
`res://features/casino_hub/casino_gridmap.tscn` with the game's stable `Room/Spawn`
marker. F5 runs the normal game with login, HUD, multiplayer, eight functional slot
machines and roaming NPCs supplied by the existing feature loader. The overview
camera is disabled in this wrapper so the local player's camera controls the view.
`world/room.tscn` retains the original casino for reference during migration.

Open `casino_gridmap.tscn` to edit its saved cells with Godot's GridMap editor.
For collision-aware exploration, run `preview.tscn` (F6), or from the repository root:

```sh
godot --path game res://features/casino_hub/gridmap/preview.tscn
```

F1 shows the overview; F2 or a mouse click enables the existing `Player` controller.
Arrow keys move, Shift jumps, and Escape releases the mouse. Controller movement
and jumping use the same Controls autoload as the main game. This standalone review
scene includes the static furnishings and stationary NPCs, but does not load the
live feature system; use F5 for functional slot machines and roaming patrons.

## Shared tiles

`casino_tiles.tres` is a real Godot MeshLibrary. `tiles.tscn` is its editable tile
source. IDs are stable; keep them when extending the library so existing painted
cells continue to refer to the same parts.

| ID | Name | Visual / collision | Dimensions |
| --- | --- | --- | --- |
| 0 | Floor | BoxMesh / BoxShape3D | 1 × 0.25 × 1 m slab; top at cell Y |
| 1 | Wall | BoxMesh / BoxShape3D | 1 m wide × 2.5 m high × 0.2 m deep |
| 2 | Ramp | PrismMesh / matching convex wedge | 6 m run, 1.25 m rise, 1 m wide |
| 3 | WoodWall | Existing Blockbench wall, scaled in width and height / box | 2 m wide × 5 m high × 0.2 m deep |
| 4 | WoodPitWall | Shared wood mesh, shortened vertically / box | 1 m wide × 1.25 m high × 0.2 m deep |
| 5 | TileFloor | Food court BoxMesh / BoxShape3D | 1 × 0.25 × 1 m slab |
| 6 | WoodFloor | Pawn shop BoxMesh / BoxShape3D | 1 × 0.25 × 1 m slab |
| 7 | DoorHeader | Walnut BoxMesh / BoxShape3D | 2 m wide × 2.5 m high, above 2.5 m clearance |
| 8 | CeilingTile | Downward-facing QuadMesh | 1 × 1 m; room slabs supply collision |
| 12 | StuccoPitWall | Authored beige stucco / box | 1 m wide × 1.25 m high × 0.2 m deep |
| 13 | StuccoWall | Authored full-height beige stucco / box | 1 m wide × 5 m high × 0.2 m deep |
| 14 | StuccoUpperWall | Cropped full-height stucco / box | 1 m wide × 3.75 m high × 0.2 m deep |

The authored wood mesh is duplicated once to carry the prefab's material override
in the library, then shared by both wall entries and every placed instance. Its
104 triangles, one material and 64×128 texture are preserved. The 1.25 m retaining
facing uses a library transform; the original Blockbench model is unchanged.
Structural tiles have one collider; ceiling tiles use the existing room slab
colliders. Collision uses world layer 1, matching player movement.
Floor and ramp tiles reuse the existing casino carpet material and texture.

Grid cells are **1 × 0.25 × 1 m**, centered in X/Z and floor-aligned in Y.
Cell `(x, y, z)` has its origin at `(x + 0.5, y × 0.25, z + 0.5)`.
Walls sit on the local negative-Z edge, face +Z and start at the cell's floor height.
Rotate around Y to put them on the other edges. The ramp's default high edge is
negative Z. Its wedge is solid, covers six Z rows and rises five Y layers. Adjacent
strips along X make a wider 1:4.8 ramp. The mesh center is offset half a cell toward
negative Z: north ramp anchors are at z -9, south anchors at z 8 with 180-degree
rotation. Both use Y layer -5. Leave their six-row floor footprints empty; the
layout recipe reserves them explicitly.

The floor GridMap and two wall GridMaps share this library. North/south and east/west
walls use separate maps because perpendicular walls may occupy the same cell at
corners; a GridMap supports only one item per cell. Walls also coexist with floors
without overwriting them. These are native serialized cells with no runtime layout
script, so editor changes remain intact when the scene runs.

## Layout and current scope

- Footprint: x -24…24, z -20…20 m: a compact rectangular hall around the unchanged pit.
- Central gaming pit: x -15…15, z -12…12 m, floor **y -1.25 m**.
- Continuous surrounding floor: **y 0 m**. It is ground level, not another storey.
- Two ramps: x -3…3 m, z -12…-6 and 6…12 m. Each uses six one-metre-wide solid wedge strips.
- Perimeter panels: 2 m wide × 5 m high, with their decorated faces inward. The
  tile doubles the original model's width and height, keeping its proportions,
  104 triangles and shared material. Panels occupy two horizontal cells, so the
  perimeter uses half as many instances. Its mesh and collider have a local X
  offset of 0.5 m; reversed faces anchor one cell later to align their two-cell spans.
- Pit retaining walls: 1.25 m high, leaving the six-metre ramp mouths open.
- Player spawn: on the south promenade at `(0, 1, 16)` with the existing spawn jitter.
- A feature-owned GPS marker identifies the pit when the scene is instantiated.

The casino has a tiled plaster ceiling, with its main hall underside at y 8.75 m and the
existing efficient room slab colliders. The standalone preview hides it to keep
the overview visible; the main game displays it. The wood model's open backs
are oriented away from the interior. `furnishings.tscn` restores the imported bar,
its counter collision, bartender, three card tables and their seated patrons.
The former gallery guests stand on the north promenade at ground level. The
previous elevated gallery and architecture remain in the old scene.

The main scene's `Features` node supplies `excluded_features` metadata, read by
the existing feature loader before instantiation on every peer. This map omits
`frogs`, `penguin`, their `water` pond, `nyc_ferry`, `gnomes`, and the legacy
`annex`, `casino_wing` and annex `wall_sconces`. Their scenes remain
discoverable and load normally in maps without these exclusions. Slot machines,
casino patrons and the bar companion continue to load normally.

## South shops

`shops.gd` adds a pawn shop (x -16…-2, z 20…30), food court (x 2…34,
z 20…38) and the connecting four-metre corridor (x -2…2, z 20…30).
Floors share the main floor GridMap; two additional GridMaps hold shop walls.
The south casino opening and both shop doors are four metres wide with tiled
headers above 2.5 m. The ceiling GridMap covers both rooms and the corridor, with
room-sized box collision at y 5 m; the main hall ceiling is higher at y 8.75 m.

The food court, kebab shop, pawn shop, Gun-O-Matic and loot-fence features keep
their original transforms, networking and prices. Only their obsolete food/pawn
room shells are removed; props and booth collisions remain. GPS destinations
still point to the same counters. Shop geometry is serialized by the offline
builder, so scene loading does not replace edits made in the GridMap editor.

## Rebuild and verification

`Decor` is a separate, editable GridMap using `casino_decor.tres`. IDs 0/1/2 are
the former salon's framed landscape painting, imported brass sconce and brass
chandelier. The offline builder merges each model by material once; repeated
cells share those meshes. Decor has no collision. Its grid uses 1 × 0.25 × 1 m
cells with all centering disabled, so wall anchors use exact room coordinates.
Paintings and sconces face +Z locally, rotate toward the room and mount at y 3 m.
Main hall chandeliers hang at y 5 m with suspension extensions to the taller ceiling. The recipe in `decor.gd` places
artwork between fixtures along solid walls, clear of doors and merchandise.

`decor_lighting.gd` supplies matching local lights for the painted cells, once at
runtime and after editor changes. It uses warm, bounded sconce/chandelier pools
with 28 omni lights and two shadow pools. Only two lights cast shadows, at the bar and card tables;
the remaining fixtures avoid shadow-map costs. Ambient energy is 0.3, and casino
surface/prop shaders respond to real lights instead of fixed fullbright shading.
The indoor environment's `fixed_indoor_lighting` metadata prevents the outdoor
day/night feature from changing this scene's ambient light or adding a global sun.
Maps without that metadata retain the existing clock behavior.

The Compatibility renderer limits local lights per mesh. Structural and decor
GridMaps use four-cell render batches, and ceiling quads replace the former whole
room mesh. 13 m perimeter sconces and 8 m chandeliers keep each batch within the eight-light budget
without raising project limits. Thirty authored positional lights also stay below the
32-light frame limit, leaving space for player lights. `test_decor_lighting.gd` audits overlaps across all
GridMaps; the render probe also samples the same ceiling point across camera turns
to detect lighting changes. These checks guard against camera-dependent flicker.

Run `tests/features/casino_hub/polish_probe.tscn` for actual main-game renders;
it includes the food court and pawn shop as well as the gaming pit. This is a
visual review tool, not an FPS benchmark.

`layout.gd` is the deterministic initial layout recipe; `scene_source.tscn` owns
lighting, markers, furnishings and the overview camera. The build is an explicit offline action:

```sh
godot --headless --path game -s res://features/casino_hub/gridmap/build.gd
```

This overwrites `casino_tiles.tres` and `casino_gridmap.tscn`. Preserve manual cell
edits in `layout.gd` before deliberately rebuilding. It is never run on scene load.
Update `tiles.tscn` when changing a tile; `build.gd` transfers its mesh/material and
collision transforms into the library. The pit variant's dimensions are also there.

Focused tests under `tests/features/casino_hub/test_casino_gridmap.gd` inspect the
saved assets and exercise actual GridMap physics: floor elevations, ramp seams,
inward-facing walls, closed corners, standing capsule clearance, and the existing
player walking both ramps in both directions. Run all checks with `harness/verify.sh`.

Capture the real renderer by supplying an output folder after `--`:

```sh
godot --path game res://features/casino_hub/gridmap/preview.tscn -- \
  "$PWD/docs/design/previews/casino-gridmap"
```

The capture includes overview, pit, ramp and wood-wall views. It needs a graphical
renderer; physics tests and asset builds work headlessly. No FPS benchmark is implied.

Godot references: [GridMap](https://docs.godotengine.org/en/stable/classes/class_gridmap.html),
[MeshLibrary](https://docs.godotengine.org/en/stable/classes/class_meshlibrary.html),
[PrismMesh](https://docs.godotengine.org/en/stable/classes/class_prismmesh.html).

## Pit railing

`PitRailing` has separate `SpansNorthSouth`, `SpansEastWest` and `Posts` GridMaps.
The shared MeshLibrary adds **9 RailSpan** and **10 RailPost**, authored in
Blockbench with walnut uprights and polished gold brass fittings/crossbars. The
48 two-metre spans and 50 shared posts surround x ±15 / z ±12 at ground level,
leaving both six-metre ramp mouths open. The guard is 1.105 m high and has simple
box collision. Separate direction grids prevent corner cells overwriting a span.

The parts share one 32×32 atlas and opaque material; 56 triangles per span and
104 per post. Brass catches real light with a restrained gold highlight; no new
lights or emission are added. Authoring/export instructions and validation are in
[the source guide](../../../../docs/design/model-sources/brass-pit-railing/README.md).

## Stationary elevator

MeshLibrary item 11, `ElevatorBay`, replaces the north wall's central eight meters.
`Elevator` instances the complete reusable `elevator.tscn` at (0,0,-20). Its
`Bay` uses a single 8 × 5 × 4 m cell, +Z
facing the casino and all cell centering disabled. `Elevator/Cab` supplies the
moving leaves and authenticated buttons, recessed 20 cm; the fixed tile contains
no scripts or moving geometry. Move the parent to reposition both together.
The recess belongs to the asset; maps need no controller offset. Travel is
disabled. Rebuild the elevator library before this casino scene if its
fixed source changes. See [the elevator guide](../../elevator/README.md).

## Quarter-height pit and beige stucco

The pit is exactly one quarter of the five-metre standard wall: **1.25 m**.
Its floor and retaining bases occupy Y layer **-5** of the 0.25 m grid, and the
six-metre ramps rise five layers to ground level. Furniture, slots, roulette and
patron routes stand on the raised floor; the ground-level railing is aligned
with the rim. MeshLibrary item **12**, `StuccoPitWall`, supplies a reusable
1 × 1.25 × 0.2 m beige stucco segment with box collision. Existing pit cells
retain their wood finish; select item 12 to paint stucco into a saved layout.
The authoring and one-time saved-scene migration are documented in
[the stucco guide](../../../../docs/design/model-sources/beige-stucco-wall/README.md).

The main hall ceiling underside is **8.75 m** in world space, **10 m above
the -1.25 m pit floor**. `PitStructure` has four walnut/gold column towers at
(x, z) = (±13, ±10), two 1 m tiles inward from the pit's (±15, ±12) corners.
Each tower instances two unchanged 5 m column modules. Beige stucco upper walls
close the hall above the original 5 m wood panels; brass suspension extensions keep
existing chandeliers at their established height. Shop roofs remain at 5 m.
`pit_structure.gd` is the offline recipe used by `build.gd`; the live scene stores
editable nodes and does not rebuild them at runtime.

MeshLibrary **13 StuccoWall** is a full 1 × 5 × 0.2 m wall module.
**14 StuccoUpperWall** fits the 3.75 m gap above the main hall’s 5 m wood walls.
Both use the same 64×128 albedo at 24 pixels/metre, with cropped UVs on the
upper variant. Its mesh and collider have baked dimensions, so the upper grids
use unit scale. Item 12 remains the 1.25 m quarter-height pit wall.

## Mariachi balcony bar

`MariachiBalcony` expands the west side to **x -32…-24, z -14…12 m**, joining
at ground level and keeping the mariachi at (-20.8,0,0). The **5 m-high** wood
balcony covers x -32…-18, z -4…6, with **3.75 m headroom** beneath the existing
ceiling. Wood lower walls and stucco upper walls close the extension; a separate
roof collider matches its painted ceiling cells. Existing west fixtures move to
the new wall, preserving the light count and original stage/audience route.

**15 CasinoStairFlight** is a one-metre-wide, two-metre-run, 1.25 m-rise module
with five visible 0.25 m risers, carpeted treads and a smooth convex walking proxy.
Four modules stack in 1.25 m steps; four lanes make the staircase 4 m wide at
x -30…-26, z -12…-4. **16 CasinoStairRail** bakes the same slope into the
existing brass/walnut span mesh and matching convex collision. The top landing
has an open railing mouth, and the remaining balcony edges are guarded. Floor,
wall, stair and guard geometry remain editable saved GridMap cells.

The balcony reuses the salon bar and stool assets, matching counter collision and
5 m support columns. GPS lists **Mariachi Balcony Bar**. `mariachi_balcony.gd`
is the offline recipe called after the base layout and upper story are built.
The review scene includes the stage and captures balcony/stair views. The old
casino doorway is supplied by the separately loaded `casino_legacy` feature.

## Burgundy pedestal bar stools

`models/casino_stool.tscn` reuses the imported bundle's burgundy-and-brass stool,
including its matching collision and 32×32 atlas. The three balcony stools and
Vivienne's main-bar stool share this wrapper. A 0.9840426 vertical scale fits the
0.752 m source to the established 0.74 m seat height, preserving her seated pose.
Rebuilding the balcony uses this same wrapper. The bundle retains authoritative
mesh, paint and UV sources; no duplicate model or texture is needed.
