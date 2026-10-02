# Operations van and garage export

`build.gd` is the authoritative native mesh recipe; Blockbench tools are not
available in this run. It reuses the existing procedural Prop/UV helpers instead
of adding a toolchain. The van is one continuous angular cargo shell with cut-in
wheel arches and four fitted octagonal wheels. Front is +Z, pivot floor centre;
5m length, 2.2m overall width, 2.25m height, 176 triangles, one material, one 128px
atlas. At runtime there is one copy, with no animated parts or dynamic shadows.
The side panels intentionally mirror, and tyres/hubs share islands.

`uv-template.png` and `islands.json` derive from the exact indexed geometry before
painting. `paint-prompt.txt` records the ImageGen edit request; `paint-source.png`
is its original square response. It is diffuse artwork, not a model render.
Native processing downsamples to 128px and extrudes each island's own edge into
two-pixel gutters. Ordinary mesh rebuilds leave the approved paint untouched.

The builder also exports the saved concrete garage GridMaps/MeshLibrary from the
casino floor/wall dimensions with existing garage materials, the ribbed rolling
shutter (existing dark material), and an original deterministic two-second PCM van
sound (starter churn, ignition/acceleration, low-pass road rumble and fades).
No third-party vehicle image or recorded sound is included.

```sh
# From repository root; import once before running the builder.
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/operations-van/build.gd
# Only when explicitly approving a new painting:
godot --headless --path game -s ../docs/design/model-sources/operations-van/build.gd -- \
  "$PWD/docs/design/model-sources/operations-van/paint-source.png"
```

Runtime exports: `game/assets/starter_room/`; gameplay prefab:
`game/features/starter_room/van_model.tscn`. Captures from actual native imports
(front/arrival, rear and low underside) and UI views:
`docs/design/previews/operations-garage/`. Reproduce through the feature README.
Tests validate finite indexed positions, normals, clockwise winding, nonzero areas,
UV bounds, ground contact, texture size and sound duration/non-looping settings.
