# Walnut and polished brass pit railing

The current mesh-first geometry is maintained in
[casino-fixtures-v2](../casino-fixtures-v2/README.md). Use that rebuild recipe for
the current rail meshes. This folder retains the original Blockbench authoring
history and the approved 32×32 paint reused by the replacement.

Authoritative source: `brass_pit_railing.bbmodel`, created in Blockbench Generic Model.
The model follows the casino concept's mid-century, warm wood-and-brass direction.
It uses original geometry and a hand-painted palette; no third-party artwork.

The user's repeated-tile performance preference carries forward: static desktop/web
Godot Compatibility asset, viewed from roughly 1–10 m, with no animation, alpha,
normal maps or extra lights. The bright gold brass is intentionally polished at the
user's request; dark walnut shafts keep it compatible with the aged wood walls.

## Parts and cost

- `BrassRailSpan`: 2 m along +X, 56 triangles, two faceted brass crossbars and three
  walnut uprights. The upper rail is centred at y 1.025 m.
- `BrassRailPost`: 1.105 m tall, 104 triangles, octagonal walnut shaft with brass
  foot, collars and cap. It uses a floor-centred origin.
- Two reusable meshes, one shared opaque material and one **32×32** albedo atlas.
- The 48 spans and 50 posts around the pit total **7,888 triangles**. Corners share
  one post. Span ends terminate inside posts; hidden end caps and foot undersides
  are omitted. No large-copy FPS benchmark is claimed.
- Blockbench uses **16 units/metre**. Export scale 16 is baked into the native meshes.

The atlas's left half holds padded gold and darker fitting swatches, sampled at
single UV points deliberately. Its right half is coarse vertical walnut grain.
Repeated wood sides share the same grain region at about 24 texels/metre vertically;
narrow facets have deliberately simplified transverse detail. All UVs have padding
and remain within [0,1] after export. Material selection comes from atlas U:
left = brass, right = walnut. No extra mask texture or second material is needed.

`game/features/room_kits/brass_railing.gdshader` gives the brass a small,
light-dependent gold specular highlight; the wood remains rough. It uses the
actual light direction and attenuation, with no emission or fullbright shading.
The glTF is a portable textured fallback; Godot's prefab owns the richer finish.

## Integration

`game/features/room_kits/brass_railing.tscn` supplies both reusable parts and box
collision. Casino MeshLibrary IDs 9/10 are RailSpan/RailPost. The saved
`PitRailing` GridMaps keep horizontal spans, vertical spans and shared posts apart
so cells at corners never overwrite one another. `gridmap/railings.gd` is only
an offline recipe; cells remain editable in Godot and are not rebuilt on load.
The rim is x ±15, z ±12 at ground level, with the original six-metre ramp mouths
open. Collision blocks walking off the rim while preserving the existing ramps.

## Export and rebuild

Open the authoritative `.bbmodel` in Blockbench. Run `export_blockbench.js`, then
call `exportPitRailing(repositoryRoot)`. This retains the model, exports glTF at
scale 16 and writes the external atlas. Preserve the PNG import's mipmap setting.

```sh
godot --headless --path game -s ../docs/design/model-sources/brass-pit-railing/build_godot.gd
godot --headless --path game --editor --import
godot --headless --path game -s res://features/casino_hub/gridmap/build.gd
```

The conversion checks triangle and surface counts. Integration tests cover UV
bounds, finishes, texture size, guard continuity and standing clearance through
both ramps. The casino lighting audit includes the new GridMaps. Actual renderer
captures are in `docs/design/previews/brass-pit-railing/`.
