# Service elevator authoring

The working garage lift instances reusable native cab, paired sliding-door and
button models. The cab has three paneled walls, carpet, ceiling, handrails, a
lamp, a recessed door attachment and a backed floor indicator. Landing doors use
the same frame/leaves. The authored interior stays within the existing 3×3×3 m
cab; collision and movement remain owned by the physical lift and door systems.

Geometry and UV1 share `elevator_model.gd` and the existing prop atlas packer.
Eight padded islands occupy 68.6% of the atlas. Three walls stack `WOOD`, both door
faces/leaves share `DOOR`, and all brass/steel trim uses small shared swatches.
The control plate gets twice wall density; low-detail floor and ceiling get less.
The tiny trim islands are deliberate uniform material swatches. Runtime textures
are 128×128 with nearest mipmaps. The cab, frame, leaf and button contain 156, 36,
32 and 14 triangles respectively; the assembled model is 326 triangles.

The retained guide and painting source here are authoring images. `texture_prompt.md`
records the built-in imagegen prompt; `generated_albedo_source.png` is its output.
The builder downsamples it and extrudes two pixels of island padding.

```sh
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_elevator.gd
# To deliberately process a new painting:
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_elevator.gd -- \
  "$PWD/docs/design/model-sources/elevator/generated_albedo_source.png"
```

Normal rebuilds preserve the painting. Native scenes are
`elevator_cab_model.tscn`, `elevator_door_model.tscn` and
`elevator_button_model.tscn` under the procedural rooms feature. Meshes, the
atlas, UV checker/manifest and `elevator.glb` live under
`game/assets/procedural_rooms/models/elevator/`. Gameplay/checker captures are
in `docs/design/previews/world-level/elevator-model-*.png`.
