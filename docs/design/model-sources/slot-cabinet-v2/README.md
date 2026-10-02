# Mechanical slot cabinet refinement

`build.gd` is the authoritative indexed native geometry recipe. Units are metres,
Y is up, the root is floor-centred and the front faces +Z. The machine remains
roughly 2.2 m wide and 2.8 m tall (3.005 m including the beacon), with the existing collider and
interaction point. Eight live machines share one cabinet mesh (844 triangles),
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

Geometry rebuilds reuse approved paint. `polish-paint-source.png` is the current ImageGen edit of
`uv-template.png`; `polish-paint-prompt.txt` retains the exact request. Original
`paint-source.png` / `paint-prompt.txt` remain as authoring history. The SVG expresses
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
charts; side panels map along their full physical outline. The metal samples the quieter central portion of its chart to avoid harsh striped
reflections across narrow trim. The runtime finish remains one 128×128 atlas; no
normal maps or high-resolution emission maps are used.

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


## Mechanical polish

The cabinet now has a beveled crown, continuous sloped control shelf, recessed
cashbox seam and keyed lock, bezel-mounted indicator lamps, rear service door with
hinges/vents, and a beacon joined to its base and cap. Cabinet and lever remain
separate indexed surfaces sharing paint; the collider is unchanged. Moving reels,
readable labels, thin glass and lights are separate runtime presentation elements.
The light implementation uses 24 bulbs in one MultiMesh, one candle, two indicator
lenses and at most one short-range, shadow-free light per nearby cabinet. It does
not rely on bloom. Dedicated servers skip that feedback allocation.

Regenerate the native atlas (explicit opt-in) and export the cabinet/lever GLB:

```sh
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v2/build.gd -- --paint
godot --headless --path game --editor --import --quit
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v2/build.gd -- --export
godot --headless --path game -s ../docs/design/model-sources/slot-cabinet-v2/audio/build.gd
```

The cabinet/lever GLB is an interchange export of the static meshes and shared
128×128 paint, not the Godot gameplay scripts, labels or dynamic effects. Native
GDScript is the authoritative editable source; Blockbench tools were unavailable.
Sound effects are original, seeded synthesis baked to short mono PCM16 WAVs. The
synthesis recipe contains no external samples and adds no runtime synthesizer.

### Motion and audio preview

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  --write-movie /tmp/slot-spin.avi --fixed-fps 30 --quit-after 240 \
  -s ../docs/design/model-sources/slot-cabinet-v2/motion_review.gd
```

The eight-second fixture captures the actual engine animation and audio mix with
a listener at player distance. It uses a known winning presentation result without
a wallet transaction; real transactions are covered separately by the feature's
real-peer network test. The audio recording was checked for a non-silent signal
and peak headroom; subjective listening was not available in this agent environment.
No hardware/browser performance benchmark is claimed.
