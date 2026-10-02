# Casino lounge prop study

A 1970s-inspired burgundy leather lounge chair and matching two-seat couch, with walnut framing and aged brass legs. Low polygon geometry and a single low-resolution painted atlas give the assets a PSX / GoldSrc aesthetic.

## Files

- `casino-lounge-preview.html`: self-contained interactive WebGL viewer. Open directly in a browser. Drag to orbit, scroll to zoom, toggle wireframe, and inspect the atlas. No CDN, server, or external dependency.
- `casino-lounge-chair.glb`: chair with embedded texture, 116 triangles.
- `casino-two-seat-couch.glb`: couch with embedded texture, 150 triangles.
- Matching `.obj` files, `casino.mtl`, and `casino-atlas-256.png`: alternative import route.
- `uv-template-256.png`: flat UV chart painting template.
- `uv-guide.png`: annotated guide for island identity; this is a reference image, not a model texture.
- `casino-lounge-render.png` and `casino-qa-views.png`: rendered mesh previews.
- `imagegen-prompts.txt`: exact painting and edge-padding instructions.
- Python source and HTML template: reproducible mesh generation and viewer packaging.

## Geometry budget

The chair was reduced from 432 to 116 triangles (73% fewer), and the couch from 520 to 150 triangles (71% fewer). Bevel rings, cushion undersides, leg caps, separate brass shoes, and arm inlay meshes were removed. Legs have four sides; cushion bevels exist only at silhouette corners. The original padded 256 x 256 texture is retained.

## Geometry and UVs

Coordinates are in metres, Y is up, and the front points along +Z. Chair bounds are approximately 0.935 x 0.995 x 0.830 m; couch bounds are 1.600 x 0.995 x 0.830 m. Each asset has one mesh, one primitive, and one material. Furniture components and trim are disconnected surfaces within that mesh. Normals are flat and UV seams duplicate vertices.

Repeated cushions and symmetrical components intentionally reuse UV chart regions. The couch adds a second cushion of the same size instead of stretching one seat texture over its width. This preserves matching upholstery detail scale. Painted surface texture is capped at 256 x 256 pixels. Higher-resolution guides are not material textures.

## Painting and filtering

The atlas was painted with the built-in ImageGen tool using an exported flat UV template, then reduced to 256 x 256. A second edit extends material edge colours outward into unused gutters to reduce dark edge contamination. The dark underside cloth is an actual material and remains dark.

Nearest-neighbour sampling is embedded in the GLB and used in the viewer. Padding reduces edge contamination; it does not guarantee isolation at arbitrarily low mipmap levels. Use engine-appropriate filtering and mipmaps for your target renderer.

The GoldSrc reference is aesthetic. These GLB and OBJ files are not compiled GoldSrc MDL files. Engine-native import, collision, and export are separate steps.

## Rebuild

Requires Python 3, NumPy, and Pillow:

```sh
python build_models.py
python build_models.py --texture /path/to/painted-atlas.png
python build_preview.py
python render_preview.py
```

Do not use the UV template as the final painted texture. Rebuilding without a supplied painting reuses the existing final atlas.

## Verification

Geometry checks cover finite coordinates, unit normals, nondegenerate triangles, face winding, UV bounds, index bounds, binary glTF structure, and nearest texture sampling. Rendered front, rear, and side views were visually inspected. Viewer JavaScript passed a syntax check; browser interaction was not run in this environment.
