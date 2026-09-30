# Original Source-style developer textures

Twelve opaque 128×128 PNGs, drawn from code for this project. These are original
grid/measurement graphics, not Valve textures or extracted game assets.
No external artwork, fonts, models or runtime dependencies are required.

| Texture | Use |
| --- | --- |
| orange / grey / dark | General blockout surfaces and contrasting volumes |
| floor / wall / ceiling | Read structural roles at a glance |
| checker | Detect stretched UVs and inconsistent scale |
| hazard | Mark edges, restricted volumes or placeholder hazards |
| water | Placeholder sewer/drainage surfaces |
| route | Direction marking on an authored UV plane |
| cover | Placeholder cars, barriers, pillars and crates |
| elevator | Lift/door placeholder sign on an authored UV plane |

One complete surface repeat represents **64 Hammer units = 1.6256 metres**.
Minor grid spacing is **8 units = 0.2032 metres**, and major lines are 32 units
apart. This matches the project's existing 0.0254 metres-per-unit conversion.
These dimensions describe the visual ruler; gameplay generation can use a metre grid.

The ten surface `.tres` materials under `features/procedural_rooms/materials/`
use world-space triplanar scale `1 / 1.6256` to avoid stretching on arbitrary meshes.
Scale is independent of the mesh's authored UVs. Grids repeat; labels repeat with
them. The grid is a ruler on axis-aligned planes; triplanar blending on inclined
ramps is for readability, not precise along-slope measurement.

`route.tres` and `elevator.tres` use one full 0–1 UV tile. Rotate the mesh/UVs to point
the arrow along the intended route; these signs should not use world triplanar
mapping. Surface materials use nearest mipmap filtering, matte lighting and no
normal, roughness or metallic maps. Import mipmaps are enabled for distance readability.

Textures communicate development roles only: water is not a fluid simulation,
hazard stripes do not cause damage, and a lift sign does not implement an elevator.
No 3D models are included yet; the proposed primitive model kit is in the plan.

Regeneration: `res://features/procedural_rooms/tools/build_dev_textures.gd`.
Preview: `docs/design/previews/dev-textures.png`.
