# Service cabinet

Original low-poly mesh authored in GDScript; painted artwork generated with the
built-in imagegen tool against its exported UV template. No third-party game assets
are used. The saved prompt and large source are in
`docs/design/model-sources/service-cabinet/`, outside the runtime asset tree.

- `mesh.tres`: native runtime mesh, explicit UV1 and tangents, 12 triangles.
- `albedo.png`: final 128×128 colour atlas with extruded island edges.
- `uv_checker.png`: 128×128 distortion checker.
- `uv_manifest.json`: named islands, pixel rectangles, density, dimensions and pivot.
- `service_cabinet.glb`: portable model with the same UV map and embedded 128px atlas.

The runtime prefab is `features/procedural_rooms/service_cabinet.tscn`. Rebuild with
`features/procedural_rooms/model_tools/build_model.gd`; no source argument preserves
existing painted artwork. See `docs/design/model-workflow.md` for the complete process.
