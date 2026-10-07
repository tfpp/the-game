# Honkers / fuller chest rendered review

These are native Godot 4.7.2 Compatibility-renderer captures of the actual
connected runtime mesh, not generated concept art:

- [Front/oblique](front.png): unchanged Default beside Full on both human builds,
  white underwear top, inventory shirt, tactical outfit and unchanged penguin.
- [Side](side.png): front projection, shoulder/waist clearance and connected form.
- [Rear](rear.png): no back deformation; underwear top and original clothing.
- [Phone-sized settings](settings-phone.png): 390×844 native window, existing
  scaled/scrolling settings panel with Chest → Full (honkers) selected.

Regenerate from the repository root (omit `xvfb-run -a` with a display):

```sh
for view in front side rear; do
  xvfb-run -a godot --audio-driver Dummy --path game --resolution 1280x960 \
    res://tests/features/player_models/chest_visual_probe.tscn -- \
    --chest-view="$view" --avatar-capture="/tmp/chests-$view.png"
done
xvfb-run -a godot --audio-driver Dummy --path game --resolution 390x844 \
  res://tests/features/player_models/chest_visual_probe.tscn -- \
  --character-page --scroll-chest --avatar-capture=/tmp/chest-settings-phone.png
```

The native definition is `game/features/player_models/player_chest.gd`, based on
the unchanged original `game/assets/player_models/models/human.glb`. It appends
one morph, not new polygons: **1,707 imported vertices, 2,926 triangles, one
surface/material, 45 bones, six runtime shapes (five original plus FullChest)**.
No new textures; all original runtime artwork is 128×128. Existing skin/cloth
UVs, weights and indices are retained. Front is -Z and the added projection is at
most 0.16 authored metres, before existing build/identity-height scaling.

Mesh generation runs once and shares its result across avatars. Tests check
bounded front-only deformation, unchanged legacy geometry/UVs/weights/morphs,
quantized-normal tolerance, culling bounds, connected seams, and nondegenerate
outward triangles in the affected torso with both builds/outfits. All renders
use the existing shader, not substitute materials; no Blockbench or historical
Python builder was used, and no new artwork was needed.

These stills are visual review, not a WebGL performance measurement or interactive
touch/controller test. First-person body masking and held-item arms are covered
by automated integration tests; browser first-person presentation was not
visually checked here.
