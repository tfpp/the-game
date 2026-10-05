# Garage finishes

Native indexed meshes exported by `build.gd`: ribbed shutter (380 triangles),
framed alley window (108), and ajar broom cupboard with bucket, broom, mop and
cleaning bottles (432). Total: 920 triangles, one shared 128px mipmapped atlas.
`uv-template.png` is the exact chart layout; `paint-source.png` and
`paint-prompt.txt` preserve the painted source and painting instructions.

Run from the repository root with Godot:

```sh
godot --headless --path game -s ../docs/design/model-sources/garage-finishes/build.gd
godot --headless --path game -s ../docs/design/model-sources/garage-finishes/build_surroundings.gd
```

The second builder makes the window aperture in the original GridMap wall and
exports the alley's native GridMaps. The view reuses existing small brick/wet
asphalt textures and street props. Glass closes the opening for collision.
The shutter and cupboard are scenery; the van doors remain interactive.
The alley storm reuses the pawn shop audio clips, bounds rain outside the room,
and runs only while the local camera is in the garage.

For the working roller door, the same builder also exports
`garage_shutter_frame.res` (48 triangles) and `garage_shutter_leaf.res` (332).
Their UVs retain the approved paint. The original 380-triangle combined output
remains reproducible; only the separate frame and leaf are used in gameplay.
