# Armoured operations van review

The capture scene loads `van_model.tscn` and renders the actual exported meshes,
approved atlas and native material with Godot's Compatibility renderer.

```sh
# From repository root, with an X display available:
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture_van.tscn
```

Local images (ignored by repository policy): `front.png`, `rear.png`,
`undercarriage.png`, `doors-open.png`, `cargo-interior.png`, `cab-interior.png`,
`driver-door-closed.png`, `passenger-door-closed.png`, `driver-door-open.png`.
Reviewed all six poses plus garage placement and the driving transition through
`tests/features/starter_room/capture.tscn`. The final geometry has 1,416 triangles,
five indexed meshes and two 128px textures. No browser performance
claim is made. Native builder and construction notes:
`docs/design/model-sources/armoured-operations-van/`.
