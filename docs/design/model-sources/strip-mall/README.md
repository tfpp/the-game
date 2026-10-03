# Strip mall native gridset

Authoritative indexed geometry and explicit UV source:
`game/features/strip_mall/tools/build_assets.gd`. Layout source:
`game/features/strip_mall/tools/build_layout.gd`.
No Blockbench tools were exposed in this run; the repository's native GDScript
model-building workflow is used instead. Art direction references:
`docs/design/concept-art/casino.png` and the lore/art-style guides.

One original ImageGen-painted 128×128 opaque atlas, nearest mipmaps, six padded
material regions. `uv-template.png` is the exact flat 8× enlargement of the
128px chart; `paint-source.png` and `paint-prompt.txt` retain the generated
painting and exact request. Bounds in native pixels:
paving (2,2,60,60), asphalt (66,2,60,60), brick (2,66,60,28),
canvas (66,66,60,28), metal (2,98,60,28), leaves (66,98,60,28).
Faces intentionally stack/reuse repeating material patches. Each box face maps
the complete patch, with UVs half a texel inside its interior. Four connected
one-metre wall courses preserve brick scale on the four-metre wall. Primitive
leaf wedges retain their native charts within the same leaf patch. Windows use
a dark blue-green vertex tint of the metal patch, avoiding alpha sorting.

All models have one indexed material surface and simple separate collision:
paving/asphalt/roof/post 12 triangles; brick wall 48; awning 36;
window 48; planter 96; parking stripe 24; site fence 96.
The 1.8×.8 m planter has a floor-centred pivot, joined trough walls, recessed
soil and three faceted foliage clumps. The canopy is 2.2 m wide along X, 1 m
along Z, slopes toward -X and has a metal rear spine with a hanging canvas edge.
Architectural tiles use metre-based grid pivots; ground slabs have top y=0.
All ten assets are native ArrayMeshes under `game/assets/strip_mall/`.
`gridset.glb` is a portable review export, with items laid out along X; the native
ArrayMeshes/MeshLibrary remain the authoritative runtime exports.
Existing modeled signage, service doors, lamps, vans and tenements are reused,
not repainted or copied. No third-party art is introduced.

Normal rebuilds preserve the approved paint:

```sh
godot --headless --path game -s res://features/strip_mall/tools/build_assets.gd
godot --headless --path game -s res://features/strip_mall/tools/build_layout.gd
```

To deliberately process a newly approved painting:
```sh
godot --headless --path game -s res://features/strip_mall/tools/build_assets.gd -- \
  ../docs/design/model-sources/strip-mall/paint-source.png
godot --headless --path game --editor --import
godot --headless --path game -s res://features/strip_mall/tools/build_assets.gd
```
The second build picks up the newly imported PNG; the material stays shared.
Processing downsamples and extrudes each patch's own edges into its two-pixel
gutters. Numerical tests validate finite vertices, normals, winding, indices,
nonzero triangles, UV bounds, collision, texture/mipmap budget and grounding.
Main-game captures review the storefronts, forecourt, portal and planter/awning
contact views. See `game/features/strip_mall/README.md` for the capture command.
