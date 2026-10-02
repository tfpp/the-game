# Beige quarter-height stucco wall

Authoritative source: `beige_stucco_wall.bbmodel`, authored in Blockbench Generic
Model. Original geometry and coarse painted beige stucco, guided by the casino
concept's warm, aged plaster palette. No third-party texture or generated image.

## Dimensions and placement

**1 m wide x 1.25 m high x 0.2 m deep**. Height is exactly one quarter of the
casino's **5 m** standard wall. Bounds: X [-0.5,0.5], Y [0,1.25], Z [-0.1,0.1].
Floor-centred pivot; +Y up, +Z front, all six sides finished. Place neighbouring
origins one metre apart, rotate around Y for corners, or stack origins in 1.25 m
steps. No decorative trim protrudes past the module bounds.

Prefab: `game/features/room_kits/beige_stucco_wall.tscn`. It has one box collider
matching the visual bounds, centred at Y 0.625 m. Casino MeshLibrary item **12**,
`StuccoPitWall`, mounts the same mesh on the local negative-Z cell edge, matching
the wood retaining wall. The existing pit retains its wood-facing cells, and the
stucco tile is available for painting into that layout.

## Pit conversion

The active casino GridMap's gaming floor is **Y -1.25 m**, Y layer **-5** of its
0.25 m grid. Five vertical grid steps equal one quarter-wall height. The promenade
and railing remain at ground level. Ramp footprint stays **6 m run x 6 m width**;
the rise is now 1.25 m, giving a **1:4.8** slope. Visual and collision wedges agree.
Wood retaining visuals/colliders are also 1.25 m high. The floor furnishings,
slot machines, roulette, bartender, companions and roaming routes moved up 0.25 m
with the pit, including their interaction and dropped-item origins.

`update_pit.gd` is a **one-time migration** from the old saved -6 layer. It moves
only pit floors, ramp bases and retaining-wall cells to -5, updates the GPS marker,
and rebuilds the shared library. It preserves all other painted cells and checks
destination cells before moving anything. Normal scene loads do not run it.
`gridmap/layout.gd`, `tiles.tscn`, `build.gd` and `scene_source.tscn` now reproduce
the new dimensions on subsequent explicit offline builds. The legacy CSG room is
retained as a historical reference; the active game uses the saved GridMap room.

## Budget and UVs

Performance preference carried forward from the earlier casino assets. Target:
desktop/web Godot Compatibility, static opaque architecture, viewed at 1–10 m;
planning assumption of hundreds of copies, with no measured instance benchmark.

- **12 triangles**, one shared mesh and one rough opaque material.
- **64 x 64** albedo with nearest mipmap filtering, roughness 0.95.
- No lights, animation, transparency, metalness or additional maps.
- Three padded UV regions at **32 pixels/metre in both axes**: front/back
  32 x 40 px, ends 6.4 x 40 px, caps 32 x 6.4 px. Opposite faces share artwork.
- At least two pixels of extruded quiet edge colour; distinct islands stay apart.
  Subtle broad beige variation and small low-frequency wear avoid visible cracks
  or black seams between neighbouring plaster modules.

`uv_manifest.json` records metre coordinates, UVs and island rectangles.
`uv_template.png` labels the three regions by layout: large upper-left front/back,
narrow upper-right ends, short lower-left caps. Blockbench uses **16 units/metre**;
conversion bakes that scale into the native shared mesh.

## Rebuild and review

Edit the authoritative model in Blockbench, load `export_blockbench.js`, then call
`exportBeigeStuccoWall(repositoryRoot)` to preserve the source and export the
portable glTF/PNG pair and manifest. Preserve the PNG import's mipmap setting.
`build_blockbench.js` recreates the initial geometry and original painted texture
in a new empty Generic Model project.

From the repository root:

```sh
godot --headless --path game -s ../docs/design/model-sources/beige-stucco-wall/build_godot.gd
godot --headless --path game --editor --import
godot --path game -s ../docs/design/model-sources/beige-stucco-wall/preview.gd
```

For an existing old saved casino only, run the one-time migration after importing
the new prefab:

```sh
godot --headless --path game -s ../docs/design/model-sources/beige-stucco-wall/update_pit.gd
```

The native converter checks exact bounds, 12 triangles, one material surface and
UV limits. Casino tests check actual collision heights, quarter-wall proportions,
GPS elevation, ramp joins, standing clearance, controller traversal, slot approaches,
furniture support and companion floor contact. Review renders in
`docs/design/previews/beige-stucco-wall/` show both finishes, checker mapping,
neighbouring modules and the actual migrated pit and ramps.
