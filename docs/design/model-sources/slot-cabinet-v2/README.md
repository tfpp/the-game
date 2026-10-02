# Mechanical slot cabinet refinement

`build.gd` is the authoritative indexed native geometry recipe. Units are metres,
Y is up, the root is floor-centred and the front faces +Z. The machine remains
roughly 2.2 m wide, 2.8 m tall and 1.2 m deep, with the existing collider and
interaction point. Eight live machines share one cabinet mesh (488 triangles),
one moving lever mesh (144 triangles) and one painted 128×128 atlas/material.
Reels and readable engine labels remain separate because they animate/change.
The prior imported cabinet remains available as legacy authoring history.

Walnut side panels follow a continuous stepped profile. The metal frame has an
open reel aperture and inward walls with a recessed backing. Three curved drums
retain their positions and shader. The coin throat is recessed; the folded payout
tray meets the lower front and remains aligned with the coin emitter. A fixed
socket meets the moving shaft at its existing pivot; the faceted bakelite knob
meets the shaft. Each manufactured component has closed end/side faces.

## Rebuild

From the repository root:

```sh
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v2/build.gd
godot --headless --path game --editor --import
```

Geometry rebuilds reuse approved paint. `paint-source.png` is the ImageGen edit of
`uv-template.png`; `paint-prompt.txt` retains the exact request. The SVG expresses
the same chart boundaries in native pixels. The PNG is a 1024px painting reference,
not a runtime texture. The native atlas uses nearest mipmaps. Rectangles are:

| Material | Pixel origin | Size |
| --- | --- | --- |
| Walnut | 2,2 | 54×60 |
| Worn metal | 60,2 | 28×60 |
| Green enamel | 92,2 | 34×60 |
| Blue marquee | 2,66 | 64×16 |
| Paytable | 2,86 | 64×24 |
| Dark cavities | 70,66 | 24×44 |
| Brass hardware | 98,66 | 28×44 |
| Bakelite | 2,114 | 64×12 |

UVs stay half a texel inside their island. Repeated planar parts share material
charts; side panels map along their full physical outline. No new light, emission
map, normal map or runtime geometry builder is required.

## Review and checks

With a graphical display, render the real reusable gameplay machine:

```sh
godot --path game -s ../docs/design/model-sources/slot-cabinet-v2/review.gd -- /tmp/slot-review
```

Create the destination folder first. Review captures front, rear, underside,
coin/lever hardware, a spinning snapshot with the lever pulled, and the live casino bank. Screenshots
are retained in `docs/design/previews/slot-cabinet-v2/`. The spin screenshot drives
presentation from a preview snapshot; it is not evidence of a paid transaction.
Tests retain the reel stop order, late-join results and label bounds, and check
native winding, nondegenerate triangles, unit normals, small shared paint,
unchanged collision, open payline and lever response. `harness/verify.sh` checks
normal offline/multiplayer behavior. No performance benchmark is claimed.
