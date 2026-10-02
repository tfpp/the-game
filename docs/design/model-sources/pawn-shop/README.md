# Pawn shop furniture

The display case and retail shelves follow the repository's mesh-first modeling
prompt in `../casino-codex-bundle/casino-props/asset-generation-prompt.txt` and the
current `../../prop-generation.md` limits. Blockbench was unavailable; the supported
native Godot workflow supplies the indexed geometry, named UV charts, painting
template, runtime prefabs and interchange exports.

Authoritative source: `game/features/pawn_shop/tools/build_furniture.gd`.

- Display case: 2.8 × 1.15 × .8 m, floor-centred, customer face +Z. Walnut plinth,
  felt bed, fitted brass corner posts and upper rails; inset glass. 132 opaque
  triangles + 12 glass triangles, two materials. Merchandise reuses existing models.
- Shelves: 2.4 × 2.6 × .55 m, floor-centred, front +Z. Four uprights, four fitted
  shelves and veneer backing. 108 triangles, one material. Shelves support stock at
  .18, .96, 1.74 and 2.52 m. There are three placed units.
- Both share a single **64×64** opaque atlas. Four semantic UV charts reuse walnut,
  cream enamelled steel, dark felt and brass. 2 px extruded gutters and half-texel
  inset UVs prevent bleeding. Hardware detail is painted; glass is a plain material.
- `uv_template.png` is the exact 512px guide sent to ImageGen with
  `texture_prompt.txt`. `painted_source.png` is retained original artwork. Native
  processing reduces it to 64px and extrudes each chart's own colour into its gutter.
- `display_case.glb` / `shop_shelves.glb` and OBJ/MTL exports contain the furniture,
  with native paint. Godot prefabs live in `features/pawn_shop/models/`; runtime
  mesh and texture resources are in `assets/pawn_shop/`.

Rebuild mesh, template, manifest and exports **without repainting**:

```sh
godot --headless --path game -s res://features/pawn_shop/tools/build_furniture.gd
```

Apply a new painting matching the retained guide:

```sh
godot --headless --path game -s res://features/pawn_shop/tools/build_furniture.gd -- \
  "$PWD/docs/design/model-sources/pawn-shop/painted_source.png"
godot --headless --path game --editor --import
```

The builder checks finite, in-bounds UVs, nondegenerate triangles and outward
winding. Layout tests check the fitted counter hull, usable sale position, gun
access, return path and closed storefront. Actual renderer review uses
`tests/features/pawn_shop/capture.tscn` and includes close views of the finished
counter and shelves. Captures are presentation evidence, not performance measurements.

`build_dressing.gd` saves editable furniture, stock, modeled signs and security
bars into `features/pawn_shop/dressing.tscn`. It reuses existing painted TVs,
radios, telephones, clocks, lamps, suitcases, boxes, a fan, an armchair, a table and
framed art. The three pawn balls reuse the old counter's low-poly sphere-and-post
construction at storefront scale. No new inventory items or sales rules are added.

Render the actual exported GLBs from front, rear and underside with a display:

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  -s "$PWD/docs/design/model-sources/pawn-shop/preview.gd"
```

The six reviewed images are saved in `docs/design/previews/pawn-furniture/`.
Final in-game counter, stock and storefront views are in
`docs/design/previews/gun-shop/`. Full repository verification passed with 1,818
GUT tests plus offline and multiplayer smoke tests.
