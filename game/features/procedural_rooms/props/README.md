# Reusable garage props

Drag `barrel.tscn`, `crate.tscn` or `car.tscn` into any room. Each root is at floor
centre, +Z is the car rear, and transforms place the entire visual/collision prefab.
They are static cover props. Resources are shared across instances.

| Prefab | Bounds (metres) | Triangles | Materials | Texture density |
| --- | --- | --- | --- | --- |
| Crate | 1 × 1 × 1 | 12 | 1 | 124 px/m |
| Barrel | .86 × 1.2 × .86 | 28 | 1 | 103 px/m |
| Car | 1.74 × 1.45 × 4 | 140 | 1 | 28 px/m body, 56 wheels, 5.6 underside |

Runtime uses three 128×128 atlases, with mipmaps and nearest mipmap filtering. The
crate's six faces share one panel. Barrel facets share one strip, and its caps share
one island. Both car sides share mirrored artwork; front/rear glass share a patch.
All tyre facets share one tread patch and both hub faces share one hub patch, across
all four wheels. Wheels and body use the same atlas and material.

Distinct islands retain two pixels of edge padding. The MaxRects packer tries rotated
placements and maximizes density. Unique rectangular islands occupy 94% of the crate
atlas, 67% of the barrel atlas and 64% of the combined car/wheel atlas; these measurements
exclude gutters but include unused corners of polygon islands. Hubs are now 31×31 pixels
instead of 13×13, and the car body has 28 instead of 18 pixels per metre. The underside
uses a small budget rather than displacing visible details.

Collision uses a box for the crate, cylinder for the barrel, and fitted convex body
plus wheel cylinders for the car. Existing seeded set population owns placement,
permitted types and rotation rules; the central three-metre lane stays clear.

## Build and paint

`model_tools/prop_model.gd` authors exterior planar polygons and semantic reuse groups.
UVs preserve projected edge lengths at each surface's chosen density. Hard edges share
positions while normals and UV vertices split; sharing artwork creates no geometry gaps.
The manifest records distinct islands, face bindings, mirroring, rotation and budgets.

```sh
# Rebuild geometry and guides; preserve existing paint.
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_props.gd
# Repack retained original high-resolution painting into the current layout.
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_props.gd -- --repack
# Apply a newly painted atlas matching the current UV template.
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_props.gd -- \
  car "$PWD/docs/design/model-sources/props/car/packed_albedo_source.png"
godot --headless --path game --editor --import
godot --path game res://features/procedural_rooms/model_tools/preview_props.tscn
```

Car GLB includes four wheels sharing its material; standalone wheel export uses that
same atlas. Native scenes retain collision. C shows UV checkers, T restores paint,
arrow keys rotate. Pass a capture folder after `--` for screenshots. Sources, original
imagegen prompts and layout-v1 manifests are under `docs/design/model-sources/props/`.
Original prompts describe layout-v1; `uv_template.png` now shows the packed layout-v2.
`--repack` uses the original source with `painting_layout_v1.json`; a direct source image
argument must match the current layout instead. Higher-resolution sources remain outside
`game/`. Assets and GLBs are under `game/assets/procedural_rooms/models/`.
