# Noir casino prop kit

Fifty reusable static props inspired by 1960s–1980s casinos and CS 1.6. Open
`showcase.tscn` in the editor to inspect the complete set; instance scenes from
`props/` to furnish a room. This kit does not load a new area at game startup.

Each prop contains one native ArrayMesh, one matte material and a separate box
collision. Models retain meter scale, Y-up and a floor-centered origin. Broad box
collisions are placement defaults; adapt them when a room needs walkable gaps.
Glass is stylized opaque. Tables and machines are decorative assets, without
new gambling interactions.

Every prop has its own image-generated PNG: one 16×16 roulette ball, thirteen
32×32 small items, nineteen 64×64 props and seventeen 128×128 larger props.
Materials use nearest filtering with mipmaps. The complete kit has 9,320 triangles.

Meshes were authored before UV layouts and texture generation. Repeated surfaces
reuse four padded UV zones; this is diffuse UV1, not a unique lightmap unwrap.
OBJ sources, manifests, UV guides and texture instructions live outside `game/`
in `docs/design/model-sources/casino-props/`. No Python or Blender dependency is
introduced. Rebuild native meshes and prefabs without repainting textures:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s res://features/casino_props/tools/import_props.gd
```
