# Model and texture workflow

World and model textures have a hard **128×128 maximum on both dimensions**.
Use 64×64 or 128×128 power-of-two images, nearest mipmap filtering, and a
GoldSrc-inspired look: simple low-poly silhouettes, broad painted colour,
readable vents/seams, restrained rust and grime. Detail must survive at the
actual runtime resolution. Keep high-resolution painting drafts and enlarged
UV guides outside `game/`; they are authoring sources, not runtime assets.

## Author, unwrap, paint, review

1. Define the silhouette, dimensions, floor-centred pivot, collision bounds and
   intended room placement. Use the existing gameplay footprint as the constraint.
2. Give each visible surface a named UV1 island. Orient vertical surfaces upright,
   stack or mirror repeated faces and allocate density by visibility and detail
   importance. Keep distinct painted surfaces separate; reuse repeated ones. Export the mesh and UV template from the same geometry definition.
3. Validate non-overlap between distinct islands, atlas bounds, winding, geometry and
   padding. The sample uses two runtime pixels of edge padding and a four-pixel
   gap between neighboring islands. Use a UV checker before painting.
4. Supply the UV template to image generation as an edit reference. Preserve the
   island positions and ask for flat diffuse artwork, not a perspective rendering
   of the object. Describe each named island separately. Remove guide labels and
   preserve a quiet edge border. Save the exact prompt with the authoring source.
5. Resample to 128×128, extrude island edge colours into their padding, and keep
   unused atlas space neutral. Import with mipmaps and use nearest mipmap filtering.
   Do not automatically overwrite existing painted atlases during mesh rebuilds.
6. Review the actual mapped model from front, back, side and at gameplay distance.
   Check flipped or stretched artwork, handle/vent placement, seams, and distant mip
   bleeding. Generation can move painted boundaries; visual review is required even
   when the numerical UV checks pass. Iterate the artwork against the same template.
7. Save a reusable scene with one material where practical and collision separate
   from visual detail. Export a GLB for external inspection; preserve the native scene
   and mesh as the runtime source. Test its original placement and route clearance.

The first implementation is the garage service cabinet: **12 triangles, one material,
24 UV/normal vertices, six unique islands, 30 pixels per metre, 128×128 albedo**.
Positions coincide at hard edges; vertices split there because different face normals
and UV coordinates are required. This does not create physical gaps.
The cabinet preserves the existing 0.6×2.5×1 m collision footprint and now replaces
the developer-box cabinets in utility sets and elevator lobbies.

## Tools and assets

- [Model definition and UV validation](../../game/features/procedural_rooms/model_tools/uv_model.gd)
- [Build/export tool](../../game/features/procedural_rooms/model_tools/build_model.gd)
- [Runtime prefab](../../game/features/procedural_rooms/service_cabinet.tscn)
- [Runtime assets](../../game/assets/procedural_rooms/models/service_cabinet/)
- [UV template](model-sources/service-cabinet/uv_template.png)
- [Generation prompt](model-sources/service-cabinet/texture_prompt.md)
- [Painted render](previews/models/cabinet-textured.png) and
  [checker render](previews/models/cabinet-checker.png)

Rebuild geometry, checker, manifest and GLB without replacing the painted atlas:

```sh
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_model.gd
```

Process new generated artwork and refresh the GLB:

```sh
godot --headless --path game -s res://features/procedural_rooms/model_tools/build_model.gd -- \
  "$PWD/docs/design/model-sources/service-cabinet/generated_albedo_source.png"
godot --headless --path game --editor --import
```

Inspect the model interactively (arrow keys rotate, C checker, T texture):

```sh
godot --path game res://features/procedural_rooms/model_tools/preview_model.tscn
```

Capture front/checker/rear views by passing an output folder after `--`.
The numerical checks cover UV space, padding, texel density, winding, exported UV
coordinates, collision bounds, edge extrusion and all runtime PNG dimensions in
this feature. They run under `tests/features/procedural_rooms/test_uv_model.gd`.

## Reuse and current limits

Existing `world_builder/geometry.gd` projects repeating architectural UVs and creates
lightmap UV2. That is appropriate for room shells, but does not define semantic prop
UV1 islands for painting. The existing frog model owns vertex-coloured organic meshes.
Neither is the owner of this cabinet workflow; the new helper stays within
`procedural_rooms` and the existing set placement and collision systems remain owners
of gameplay behavior.

The cabinet helper supports rectangular planar faces. The
[prop kit](../../game/features/procedural_rooms/props/README.md) extends it with planar
polygons, shared islands, rotated packing and visibility budgets. Four wheels reuse
one mesh and share the car body atlas and material. Both tools reuse the same checker
and edge-extrusion processing. These tools are not automatic unwraps of imported or
organic meshes. AI paints the atlas; geometry and UVs remain deterministic native data.

The prop packer now stacks repeated panels/caps/tread, mirrors car sides, shares front
and rear glass, and allocates only 20% of body density to the underside. Hubs/tread
receive twice body density. Unique island rectangles occupy 94% (crate), 67% (barrel)
and 64% (combined car/wheels) before padding and polygon cutouts. The retained original
painting is resampled per island from its high-resolution source, rather than enlarging
the previous 128px atlas. `--repack` explicitly performs this layout migration; normal
builds preserve current paint. Templates and manifests record the shared layout.

The [loot model kit](loot-models.md) applies the same packer to dumpster, scrap
and wallet meshes. Inventory and stash thumbnails render directly from these
models, with automatic camera framing and a shared 128×128 texture cache.
