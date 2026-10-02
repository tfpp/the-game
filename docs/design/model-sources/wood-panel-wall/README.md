# Wood panel wall

A standalone wall segment based on the user-supplied
`assets/characters/interior/wood-panel-wall.png` concept and the casino art direction.
It does not replace existing rooms or create a GridMap/MeshLibrary yet.

- **Authoritative editable model:** `wood_panel_wall.bbmodel`, authored in Blockbench
  Generic Model (`free`). The supplied JS uses Blockbench's native mesh APIs and Undo.
- **Godot prefab:** `game/features/room_kits/wood_panel_wall.tscn`.
- **Runtime assets / portable glTF:** `game/assets/room_kits/wood_panel_wall/`.
- **Review images:** `docs/design/previews/wood-panel-wall/`.

## Dimensions and placement

Exactly **1 m wide × 2.5 m high × 0.2 m deep**, including trim. Pivot is at floor
height, centered across width and total depth. X = width, Y = up, decorated face =
**+Z**. Bounds: X [-0.5, 0.5], Y [0, 2.5], Z [-0.1, 0.1].
Blockbench dimensions are 16 × 40 × 3.2 units; export scale is **16 units/metre**.
The native mesh and prefab use identity transforms and no runtime rescaling.

For straight runs, space origins exactly 1 m along X. Trim terminates flush at the
module edges. Rotate around Y for another wall direction. GridMap cell size, cell
centering, wall-edge placement and corner pieces remain for the next task; the mesh
origin is already suitable for deterministic placement. Current room kits use a
different four-metre module and 3.5-metre ceiling; this asset is intentionally separate.

**The back, top and bottom are open at the user's request.** This is a one-sided
wall facing, intended where those surfaces stay hidden. Retain the narrow end faces
for exposed ends. Rooms that view both sides will need another facing or a dedicated
two-sided module. The prefab's simple 1 × 2.5 × 0.2 m box collision is independent
of the decorative surface and remains closed.

## Budget and materials

Performance-first asset for repeated desktop/web interiors: hundreds of static copies,
viewed from roughly 1–10 m. No animation, alpha blending, normal maps or special shader.

| Cost | Result |
| --- | --- |
| Geometry | 52 quads / **104 triangles** |
| Exported vertices | 208, split for hard normals and UVs |
| Render surfaces | **1 mesh, 1 opaque material** |
| Texture | **64×128** RGB albedo, nearest filtering with mipmaps |
| Material | Nonmetallic aged walnut, roughness 0.78 |
| Collision | One box |

Two lower panels and one tall upper panel have 2 cm real recesses with sloped edges.
The three horizontal rails project up to 4 cm from the frame. These faces catch real
light while avoiding stacked closed boxes and hidden backing faces. Fine grain is
painted into the texture. No normal-map sampling is needed.

The UVs intentionally overlap one continuous walnut swatch. Fronts and end faces use
48 texels/metre; horizontal rails rotate the same grain by 90 degrees, preserving
scale. Each mapped region has at least four pixels of surrounding wood, so there are
no contrasting adjacent atlas islands to bleed. Narrow sloped bevels use projected
UVs with intentional compressed depth; they carry no unique artwork. The checker
review predates removal of the three hidden faces; visible face UVs are unchanged.
`uv_manifest.json` records the final face names, metre coordinates and pixel UVs.

## Rebuild

Normally edit the `.bbmodel` in Blockbench and preserve its embedded painted texture.
`build_blockbench.js` is the reproducible initial geometry/checker authoring script;
run it only in a new, empty Generic Model project. To rebuild from scratch, replace
its checker with the retained runtime albedo before exporting.

With the authoritative model open, run `export_blockbench.js` in Blockbench's
JavaScript context, then call `exportWoodPanelWall(repositoryRoot)` using the local
repository path. It saves the editable model and exports glTF with scale 16, no
animation, one external albedo, an opaque rough material and nearest sampling.
The GLTF file and its sibling PNG are a portable pair.

Then, from the repository root:

```sh
godot --headless --path game -s ../docs/design/model-sources/wood-panel-wall/build_godot.gd
godot --headless --path game --editor --import
```

The native conversion validates triangle count, bounds, identity transform and one
surface, then saves the shared `.res` mesh. The prefab owns its explicit material
and box collision. Keep the supplied PNG `.import` settings to generate mipmaps.

Artwork came from the built-in image-generation tool, guided by the UV layout and
user-supplied concept; see `texture_prompt.md`. The larger painting is authoring-only.
The runtime PNG was reduced with ImageMagick:

```sh
magick docs/design/model-sources/wood-panel-wall/generated_wood_source.png \
  -filter box -resize '64x128!' -alpha off -strip \
  game/assets/room_kits/wood_panel_wall/wood_panel_wall_albedo.png
```

No third-party texture was incorporated. The concept remains at the user-supplied
path and is not modified.

## Validation

Inspected checker mapping in Blockbench and the actual Godot Compatibility-renderer
prefab from front, back and opposite light directions. Three instances at one-metre
spacing verify contiguous rails and panel repetition. Backface culling confirms the
open rear. Native conversion checks dimensions, identity scale and the 104-triangle
single-surface export. `harness/verify.sh` passes. No large-instance performance
benchmark or GridMap integration is claimed.
