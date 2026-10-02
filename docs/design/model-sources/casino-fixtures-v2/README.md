# Casino fixtures and railings, mesh-first revision

Authoritative geometry is `build.gd`: indexed faceted profiles and shared-ring
tube sweeps, in metres with Y up. It supersedes the old Blockbench railing
geometry while retaining the approved walnut/brass paint and shader. Bent arms
share their joint rings; their ends meet the mounting plate, hub and lamp cups.
Caps close the exposed profile ends. Tube ends are buried inside fittings/posts.

| Export | Triangles | Dimensions / pivot |
| --- | ---: | --- |
| Rail span | 168 | 2 m along +X; same floor-cell pivot and guard volume |
| Rail post | 144 | 1.105 m high, 0.14 m wide; floor-centred |
| Sconce | 200 | 0.26 × 0.64 × 0.565 m; wall origin, lamp projects +Z |
| Chandelier | 604 | 1.58 × 1.107 × 1.548 m; ceiling pivot, hangs down |

These static meshes are repeated at roughly 1–15 m viewing distance. Each has
one surface and one material. The chandelier uses four supported lamps; its
larger budget includes the hub, four continuous bent arms, cups and diffusers.
The 48 pit spans and 50 posts total 15,264 triangles (previously 7,888).
No performance benchmark is implied. Existing box/convex guard collision,
GridMap cells, ramp mouths, stair slope, fixture light count and energies remain.

Fixtures share one 64×64 atlas painted by ImageGen from `uv-template.png`.
The exact two flat material strips are exported in `uv-template.svg`:
brass at pixels (2,2)…(30,62), opal at (34,2)…(62,62). Mesh UVs stay inset:
brass U .08… .42, opal U .55… .90, V .08… .92. Facets intentionally share
strips; axial UVs follow profile height/path length by segment. Caps sample
their corresponding material interior. The source painting remains outside
`game/`; runtime paint uses nearest mipmaps. Rebuilds reuse approved paint.

The railings reuse `aged_brass_palette.png`, 32×32: brass in the left half,
long walnut shafts in the right half. Their shared material still receives real
lighting. Brass UVs stay in the upper-left swatch (V .12–.38); they never cross
the atlas's second brass colour at V .5. Fixture opal emission is limited to the glass UV region; it does not
add lights or make brass emit. Existing local lights continue to light the room.

## Rebuild

From the repository root:

```sh
godot --headless --path game -s ../docs/design/model-sources/casino-fixtures-v2/build.gd
godot --headless --path game -s ../docs/design/model-sources/casino-fixtures-v2/build.gd -- --libraries
```

The second command replaces only meshes in library items 9/10/16 and the decor
library. It does not repaint cells or rebuild the saved casino layout. Item 16
retains the existing slope conversion and collider. The standard casino builder
also picks up these native rail meshes and fixture scenes for future rebuilds.

`review.gd` renders native exports front/rear/underneath; run it with a graphical
display and a destination directory after `--`. The existing GridMap preview
captures actual placement. Review images are in `docs/design/previews/casino-fixtures-v2/`.
Tests check native geometry winding, nondegenerate faces, normals, UV interiors,
texture budgets, shared materials, saved decor integration and existing guards.

ImageGen painting prompt: paint the exact supplied flat UV template; left strip
restrained aged warm yellow brass with broad vertical brushed variation; right
strip cloudy cream opal glass. Remove BRASS/OPAL labels, preserve chart positions,
fill gutters with edge colours, keep outer margins neutral tan. No lettering,
objects, perspective, scene shadows, silhouettes, microdetail or noise. Broad
variation must survive 64×64 downsampling. Original generated source is retained
as `paint-source.png`; no new external art or runtime dependencies are used.
