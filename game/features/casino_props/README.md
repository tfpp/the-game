# Noir casino prop kit

Fifty reusable static props inspired by 1960s–1980s casinos and CS 1.6. Open
`showcase.tscn` in the editor to inspect the complete set; instance scenes from
`props/` to furnish a room. This kit does not load a new area at game startup.

Each prop contains one native ArrayMesh, one matte material and a separate box
collision. Models retain meter scale, Y-up and a floor-centered origin. Broad box
collisions are placement defaults; adapt them when a room needs walkable gaps.
Glass is stylized opaque. Tables and machines are decorative assets, without
new gambling interactions.

Every prop has its own image-generated PNG: one 16×16 roulette ball, thirteen
32×32 small items, nineteen 64×64 props and seventeen 128×128 larger props.
Materials use nearest filtering with mipmaps. The complete kit has 9,320 triangles.

Meshes were authored before UV layouts and texture generation. Repeated surfaces
reuse four padded UV zones; this is diffuse UV1, not a unique lightmap unwrap.
OBJ sources, manifests, UV guides and texture instructions live outside `game/`
in `docs/design/model-sources/casino-props/`. No Python or Blender dependency is
introduced. Rebuild native meshes and prefabs without repainting textures:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s res://features/casino_props/tools/import_props.gd
```

## Uploaded mesh-first prop bundle

Fifteen additional props live in `props/bundle/`, with separate native assets in
`assets/casino_props/bundle/`. Inspect `bundle_showcase.tscn` for the full collection.
`bundle_furnishings.tscn` places selected props in the live casino lounge and bar;
original kit names and placements are preserved. These are static scenery.

Read the [generation standard](../../../docs/design/prop-generation.md) before
creating new models or textures. It adopts deliberate indexed meshes, exact UV
chart painting with ImageGen and exported-model review. The uploaded Python tools
are replaced by a native Godot importer and oversized source paintings become
128px runtime versions. All approved paint is preserved during rebuilds:

```sh
godot --headless --path game -s res://features/casino_props/tools/import_bundle.gd
godot --headless --path game --editor --import
```

[Authoring sources and rebuild details](../../../docs/design/model-sources/casino-codex-bundle/README.md)
include original artwork, mesh JSON, prompts, UV guides and offline viewers. The
historical galvanised bin remains in the review kit; its rejected handle design
is not an approved modelling reference. Collider boxes are for broad placement;
small tabletop and wall decorations disable collision in the placement scene.

## Live lounge seating

`bundle_furnishings.tscn` places the reusable bundle props on the casino's saved
GridMap floor. Six lounge chairs are distributed between the east lounge and
pairs along the south-east/south-west walls. The east and west cocktail tables
have two matching burgundy pedestal stools each. These are separate editable
prop instances with their existing collision, not new floor tiles or seating
interactions. Positions leave the central ramp mouths and shop corridor open.
Actual saved-level renders live in `docs/design/previews/casino-seating/`.

Both cocktail tables have a small translucent glass ashtray, a cigar resting on
its rim and a wine bottle. The new 150 mm bowl uses 64 triangles and a 32×32
painted UV atlas; its source and rebuild recipe are in
`docs/design/model-sources/glass-ashtray/`. Tabletop props are static decoration
with collision disabled, keeping furniture placement independent of pickups.
