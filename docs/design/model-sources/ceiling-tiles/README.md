# Pressed tin and basic plaster ceiling tiles

Authoritative editable source: `ceiling_tiles.bbmodel`, built in Blockbench Generic
Model with two reusable meshes and original coarse painted artwork. Reference:
`docs/design/concept-art/casino.png` and the existing casino's warm plaster ceiling.
No third-party imagery or new runtime dependencies.

## Placement and mixing

Both tiles cover **1 x 1 m**, matching the current casino CeilingTile grid footprint.
They face **-Y**, so place their origins at ceiling height without rotating them.
The mounting pivot is centred in X/Z at Y = 0; adjacent origins are exactly one
metre apart. All outside edges stay at Y = 0 and their painted seams align.
Tin's shallow pressed borders project **12 mm downward**. The plain panel is flat.
Both have only their visible underside; the room slab supplies backing and collision,
as it does for the existing casino ceiling. They are not freestanding floor slabs.

- `game/features/room_kits/tin_ceiling_tile.tscn`: aged cream-grey painted tin,
  stepped square molding, a floral rosette and four curled ornamental motifs.
- `game/features/room_kits/basic_ceiling_tile.tscn`: quiet warm plaster, broad tonal
  variation and a restrained edge seam, intended to complement the current ceiling.
- `game/features/room_kits/mixed_ceiling_patch.tscn`: a reusable **4 x 4 m** example,
  with four tin panels in the centre and twelve plain panels around them. Place its
  origin at Y = 5 m for the current casino. Individual cells can be replaced.

These are asset prefabs; the existing casino layout and MeshLibrary stay owned by
their current editor/builder. The prefabs can be used as sources for future library
entries. The example has no runtime rebuilding script.

## Performance plan

User preference: performance, carried forward from the column. Target: desktop/web
Godot Compatibility; static opaque architecture, typically viewed from 3–10 m.
Plan for hundreds of visible tiles. No large-instance FPS benchmark is claimed.

| Cost | Tin | Basic |
| --- | --- | --- |
| Triangles | **34** | **2** |
| Mesh surfaces | 1 | 1 |
| Collision bodies | 0 | 0 |

Both reuse **one material and one 128 x 64 albedo atlas**, with nearest mipmap
filtering and roughness 0.72. No alpha, normal maps, lights or animation. Tin is
painted rather than bare mirror metal, consistent with the faded casino palette.
Geometry supplies border depth; the small floral embossing is painted. The mixed
patch totals **160 triangles**. Instanced scene nodes do not themselves guarantee
batched draw calls; GridMap can reuse the two meshes when integrated later.

## UVs and authoring

Two named, non-overlapping **60 x 60 pixel** islands: tin [2,2]–[62,62], plain
[66,2]–[126,62]. Both have two-pixel extruded edge padding and a four-pixel gap.
Planar density is **60 pixels/metre on both axes**. Border UVs project onto the
same tin island, keeping painted lines aligned across the shallow slopes; their
small depth compression is deliberate. `uv_manifest.json` stores named faces and
metre/pixel coordinates; `uv_template.png` includes the tin profile boundaries.

Blockbench uses **16 units/metre**. Its basic tile is offset beside the tin tile
for authoring review. The native conversion removes that presentation offset and
bakes scale, giving each prefab an identity transform and centred one-metre bounds.

To recreate the initial geometry and original painting, run `build_blockbench.js`
in a new, empty Generic Model project. For normal edits, preserve the model's
embedded texture. Load `export_blockbench.js` with the model open and call
`exportCeilingTiles(repositoryRoot)` to save the source, glTF/PNG pair and manifest.
Keep the atlas PNG import's mipmap setting.

From the repository root:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/ceiling-tiles/build_godot.gd
godot --path game -s ../docs/design/model-sources/ceiling-tiles/preview.gd
```

Conversion verifies tile bounds, border depth, triangle counts, single surfaces,
downward normals and UV bounds. Actual Godot captures in
`docs/design/previews/ceiling-tiles/` show both tiles, proportional checker mapping,
the mixed patch and a view from player height under a five-metre ceiling.
