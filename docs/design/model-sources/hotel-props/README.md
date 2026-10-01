# Vintage hotel prop sources

The user approved the rotary phone and suitcase concept, then commissioned fifty
props with their own textures, a 128×128 ceiling, and mesh → UV → texture ordering.
The final meshes were authored and UV-mapped before painting against the UV layout.

`models/` holds triangulated, metre-scale, Z-up OBJ sources. Runtime native meshes
rotate `(x, y, z)` to `(x, z, -y)`, reverse triangle winding for Godot and invert UV V.
`uv/` contains the actual authored UV wireframes. The named atlas zones are main
identifying detail (upper-left), body (upper-right), trim (lower-left), and
accessories (lower-right). Repeated surfaces deliberately share a zone, while
rounded parts use a continuous cylindrical/planar map. There is one runtime-pixel
inset within each zone. These are diffuse UVs, not a unique lightmap unwrap.

`texture_zones.json` records each prop's four painted zones in atlas order.
`texture_prompt.md` records the generation instruction. Five generation sheets
contained ten independent atlases each; cropping and downsampling produced fifty
unique PNGs. Larger painting sources are excluded from the game and this import;
no runtime texture exceeds its declared 32, 64 or 128 pixel size. Rebuilds preserve
paint and use the native GDScript tool described in the feature README.

`placements.json` records the showroom's positions as Godot `(x, y, z, optional yaw)`.
The static editable interior scene is the runtime placement source. Bounding-box
collisions preserve solid furniture while avoiding triangle collision cost. The
standalone GLB/Blender download remains available from the original asset task.
