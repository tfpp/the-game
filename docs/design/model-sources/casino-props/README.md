# Casino prop authoring sources

The reviewed 50-prop pack: triangulated Z-up OBJ meshes in meters, manifest,
texture allocation catalog and PNG/SVG UV guides. Final painted diffuse PNGs
are in `game/assets/casino_props/textures/`. Native Godot exports are rebuilt by
`game/features/casino_props/tools/import_props.gd`, which preserves those textures.

Geometry came first, then a single UV1 map, then image generation using the mapped
quadrant guide. Each prop has its own atlas; batching generation into five sheets
of ten independent atlases does not make them shared runtime textures. Each cell
is cropped separately and BOX downsampled to its allocated size. Four zones are
main identifying detail, body, trim and accessories. Repeated faces intentionally
reuse zones; each quadrant has a one-runtime-pixel inset. This is not UV2/lightmap
layout. Cylindrical side surfaces unwrap continuously.

`texture_zones.json` records each prop's exact quadrant instructions in catalog
order. Large authoring guides stay here, outside the runtime asset directory.
