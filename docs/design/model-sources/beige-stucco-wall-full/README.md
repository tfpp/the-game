# Full-height beige stucco wall

Authoritative source: `beige_stucco_wall_full.bbmodel`, authored in Blockbench
Generic Model. Original coarse painted stucco matching the quarter-height model's
warm beige palette, informed by the casino concept. No third-party imagery.

Full module: **1 × 5 × 0.2 m**, one standard building unit tall. Floor-centred
pivot, +Y up, +Z front, X [-0.5,0.5], Y [0,5], Z [-0.1,0.1]. All six faces are
finished so modules can stand alone, join at 1 m spacing, or stack in 5 m steps.
Prefab `game/features/room_kits/beige_stucco_wall_full.tscn` has matching box
collision centred at Y 2.5 m. Casino MeshLibrary **13 StuccoWall** places the
model against the negative-Z cell edge, like existing wall tiles.

The upper casino perimeter extends from world Y 5 to 8.75 m. Library
**14 StuccoUpperWall** uses a fitted **1 × 3.75 × 0.2 m** mesh and collider,
with cropped vertical UVs rather than stretching artwork or scaling GridMap
physics. Upper grids use unit scale and one-metre cells. The original quarter
wall and pit finish remain available as item 12.

Performance preference retained: desktop/web Godot Compatibility, opaque rough
static architecture, no animation or lights, viewed roughly 1–15 m away, intended
for hundreds of repeated instances (not benchmarked). Each variant has
**12 triangles, one surface and one material**, sharing a **64×128** albedo with
nearest mipmap filtering and roughness 0.95. Explicit islands use **24 px/m in
both axes**: front/back 24×120 px, ends 4.8×120 px, rotated caps 4.8×24 px.
Opposite faces share regions. Quiet two-pixel edge padding prevents atlas bleed.
The fitted variant crops vertical islands to 90 px for its 3.75 m height. UV
manifest and template are retained here; the runtime does not load them.

## Rebuild

In a new empty Generic Model project, run `build_blockbench.js`. It creates the
six-face shape, UV mapping and painted atlas with native undo. Load
`export_blockbench.js` and call `exportBeigeStuccoWallFull(repositoryRoot)` to
save editable source, portable glTF, PNG, manifest and UV guide. Blockbench uses
16 units/metre, baked into the native export.

```sh
godot --headless --path game -s ../docs/design/model-sources/beige-stucco-wall-full/build_godot.gd
godot --headless --path game --editor --import
godot --path game -s ../docs/design/model-sources/beige-stucco-wall-full/preview.gd
```

The converter checks bounds, triangle count and atlas limits and saves both native
meshes. The casino offline builder includes library items 13/14 and paints the
upper grids with item 14. Explicit casino rebuilds overwrite manually painted
cells; normal gameplay loads the saved scene without running the builder.

Godot review images in `docs/design/previews/beige-stucco-wall-full/` show front,
back, checker mapping, neighbouring modules and the actual casino upper story.
Casino tests inspect exported UV density, tile shapes, upper grid placement and
actual collision; `harness/verify.sh` checks game integration and multiplayer.
