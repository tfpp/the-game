# Stackable wooden support column

Authoritative source: `wooden_support_column.bbmodel`, authored in Blockbench
Generic Model. Original geometry and painted coarse walnut/gold texture, guided
by `docs/design/concept-art/casino.png`. No third-party texture or generated image.

## Placement

One **5 m wall unit** tall, matching the casino GridMap's current WoodWall tile.
The square shaft is **0.8 m across**; stepped gold-and-walnut molding reaches
**1 m across**. Bounds are X/Z [-0.5, 0.5], Y [0, 5]. The pivot is floor-centred,
Y points up, and every side is finished. Blockbench uses **16 units/metre**;
conversion bakes all glTF transforms into a native mesh with identity scale.

Instance `game/features/room_kits/wooden_support_column.tscn`. Stack origins at
Y = 0, 5, 10, etc., or use the prefab's `StackTop` marker. Matching square end
profiles meet flush, forming a repeated gold collar at each storey boundary.
Top/bottom caps make solo sections usable and remain hidden when stacked.
One conservative 1 x 5 x 1 m box supplies collision; molding has no extra bodies.
The reusable asset is supplied separately from the casino layout.

## Runtime plan and budget

- User preference: performance, simple silhouette and painted detail.
- Target: desktop/web Godot Compatibility, static opaque prop, roughly 1–10 m view.
- Planning assumption: up to 100 visible sections; no measured instance benchmark.
- One mesh, **54 quads / 108 triangles**, one shared opaque material, no animation.
- **32 x 128 albedo**, nearest mipmap sampling, roughness 0.78, no extra maps/lights.
- Geometry describes only shaft and stepped molding; no internal box faces.

The four long faces share upright walnut artwork, **24 texels/metre on both
axes**: each 0.8 x 4.24 m shaft face maps to 19.2 x 101.76 pixels. Wood shoulders
and gold molding deliberately sample padded uniform swatches. Their collapsed
UVs are intentional; they carry no patterned detail. The atlas reserves U [0,8]
for gold, [8,12] for dark walnut trim, and [12,32] for coarse vertical grain.
Wood and trim boundaries are quiet and distinct swatches remain separated.
`uv_manifest.json` records the actual exported face coordinates and UVs;
`uv_template.png` identifies the shared shaft and palette regions.

## Rebuild and review

Edit the authoritative model in Blockbench. Load `export_blockbench.js` and call
`exportWoodenSupportColumn(repositoryRoot)` to retain the editable source, export
the portable glTF/PNG pair and refresh the UV manifest. Preserve the PNG import's
mipmap setting. `build_blockbench.js` recreates the initial model and painting;
run it only in a new empty Generic Model project.

From the repository root:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/wooden-support-column/build_godot.gd
godot --path game -s ../docs/design/model-sources/wooden-support-column/preview.gd
```

The native conversion checks dimensions, triangle count, single surface, atlas size
and normalized UV bounds. Actual Godot renderer captures in
`docs/design/previews/wooden-support-column/` show both sides, a two-storey stack,
and proportional checker mapping. The prefab references the native mesh/texture
through literal asset paths, so export discovery can include them.
