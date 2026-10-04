# Pawn street billboard tree

Authoritative geometry: `game/features/pawn_shop/tree.tscn`, a native QuadMesh,
4.8m wide × 6m high, front +Z, upright +Y, bottom-centred origin.
UV1 is the quad's full [0,1] rectangle, shared by every subdivision. Three columns
and eight rows = 48 triangles, one shared shader material. Six copies vary scale
from 0.75 to 1.15; typical viewing distance 8–30m through shop windows.
No Blockbench tools are exposed in this environment; native primitive geometry
is sufficient for the requested camera-facing sprite, not a volumetric model.

`uv_template.png` records the flat painting layout. `texture_prompt.md` is the
exact ImageGen edit prompt; `generated_source.png` is the original generated RGBA
painting (no third-party source assets). The native processing tool crops alpha
bounds before Lanczos reduction to 128×128 so the painted root contacts the quad
bottom. The import fixes transparent-border colours and generates mipmaps.
Runtime material uses nearest mipmap sampling and alpha scissor rather than
sorted blended transparency. Rebuild without repainting:

```sh
godot --headless --path game -s res://features/pawn_shop/tools/build_tree_texture.gd
godot --headless --path game --import
```

GPU fixed-Y billboarding preserves an upright silhouette from front/rear/oblique
views. Two bounded sine waves deform the upper mesh; bottom 28% is fixed.
No tree sounds are added; existing street weather/audio remains the owner.
All animation uses local shader time and spatial phase, with no server state.
Extra cull margin covers camera rotation and maximum sway.

Reviewed actual Godot Compatibility/llvmpipe street-and-van capture from the
existing pawn shop capture scene, with the new trees visible through the windows.
Additional review captures are generated in a temporary directory (not runtime
assets or committed preview images). Tests pin floor contact, quad/texture budgets,
building/road clearance including camera yaw and sway, shared resources and
remote-origin unload/reload. Browser GPU performance and device feel require
manual review; six small cutout meshes add no lights or CPU animation.
