# Casino dealer

Editable Blockbench Generic Model based on `docs/design/concept-dealer.png` and
`docs/design/concept-dealer-side.png`.

## Files and usage

Open `dealer.bbmodel` in Blockbench. Both 128×128 PNG atlases are embedded and
supplied separately: `dealer.png` for the approved body, `dealer-head.png` for the
head and neck. Use nearest texture filtering. The source has 40 mesh elements,
16 rigid joint groups and 1,632 triangles. There are no animation clips or skinned
weights, and this source asset does not replace the game's player scene.

Front is -Z, up is +Y, and feet rest at Y=0. The current model is 34 model units
tall; scale authored coordinates by approximately 0.05294 for a 1.8 m character.
The target is Godot's Compatibility renderer on desktop/browser, with faceted,
opaque color materials and no PBR channels.

`build_dealer.py` rebuilds the editable model and head atlas using Python 3's
standard library. `body_base.json` preserves the originally approved body. The
28 clothing/limb elements, their UVs and the original body atlas are unchanged.
The neck is authored with the head; the latest profile correction tapers it above
the collar to meet the jaw. Its original base and collar-height cross-section
are retained. Joint groups are unchanged.

## Reference-driven head revision

The side image informed the lower swept-back crown, compact raised forelock,
short nose projection, chin behind the forehead, reduced cheek hollow, smaller
ear and jaw-to-neck transition. The front image constrains the narrow jaw and
solid stylized brow/eye shapes. These shapes occupy the eye line; there are no
separate eyeball marks beneath them. Lip colors stay close to the surrounding skin.

`face-front.png`, `face-left.png` and `face-preview.png` show the front, true side
and three-quarter head. `face-oblique-side.png` is an additional diagnostic view
at a 10-degree yaw, not a calibrated reconstruction of the reference camera.
`front.png`, `back.png`, `left.png` and `preview.png` show the full character.

Head UVs are face-projected at 5 pixels/model unit on front-facing skin and 2 on
other head surfaces. Horizontal caps deliberately sample uniform palette texels.

## Validation

All mesh faces have nonzero area, every face has bounded UV coordinates and
valid texture references, and the 28 approved body elements and original atlas
were compared directly with their saved baseline. Front, profile, oblique side,
three-quarter and back renders were inspected.

Blockbench geometry validation reports zero errors, no floating parts and no
mirror or hierarchy issues. Seven bounding-box overlap warnings remain at the
original rigid-joint/clothing connections: seat/thighs, seat/vest, shoulders/vest,
neck/vest and neck/collar. These are intentional construction overlaps.

Repository verification previously passed harness tests, GDScript formatting
and lint, then stopped because `godot` is unavailable on this machine. Engine
import, unit and smoke checks could not be completed. This delivery changes no
runtime game code.
