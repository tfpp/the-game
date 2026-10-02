# Operations garage stairs and planning boards (#445)

Authoritative geometry recipes: `game/features/starter_room/tools/build_upstairs.gd`
and `game/features/starter_room/planning_board.gd`. Native GDScript uses the existing
SurfaceTool/SignBoard pipeline; Blockbench tools were not exposed in this session.
No new dependency or interchange importer is required.

## Stair kit

Preserve the two-metre-wide, four-metre-run, 2.5 m rise route at x -7…-5,
z 0…-4. Each stair module is 1 m wide, 2 m run, 1.25 m rise (five risers).
Reuse the existing casino module's 44-triangle indexed profile and proven convex
walking collision, but merge the surfaces into one weathered concrete material.
A feature-owned MeshLibrary keeps IDs 9/10/15/16 so all saved cell placements stay
unchanged. New 48-triangle guards use square steel tubes with continuous hand/knee
rails meeting upright supports. The 12-triangle post fills shared endpoints.
Shear the stair guard into the 0.625 slope, keeping supports upright, transforming
normals by inverse transpose. Guard top is 1.105 m above the walking line.

Reuse existing garage concrete/steel paint (128px world-mapped textures), not a
new paint atlas or the old casino brass/walnut. These are intentionally repeating
architecture materials; primitive UVs remain finite and indexed. All geometry uses
saved GridMaps and matching original collision shapes. Rebuild from repository root:

```sh
godot --headless --path game -s res://features/starter_room/tools/build_upstairs.gd
```

## Paper boards

Two wall-backed planar posters, 2.8 × 2.1 m, one of each; centre pivot, face +Z.
East wall placements rotate -90 degrees to face -X. Backing rests at x=7.9, boards
project 4.9 cm into the room; centres (7.9,2.4,3.2) and (7.9,2.4,6.4).
No collision; routes, van, spawn square and jobs approach are unchanged.

Paper/front mesh has explicit UV1: first chart u .02… .48, second .52… .98,
both v .02… .98. The 1024px template exports these padded chart regions. ImageGen
painted `paint-source.png` from `uv-template.png` using `paint-prompt.txt`. Only the
128×128 downsampled `game/assets/starter_room/planning_paper.png` ships, nearest
mipmap filtered. Source paint and enlarged guide remain outside game. The simple
backing reuses weathered steel. No repaint happens on normal stair/geometry rebuilds.

Diagram lines and hand-marked red rings/arrows use indexed planar strips. Exact
letter quads reuse SignBoard and SignLetterAtlas; shared glyph texture is 64px.
Each board has six mesh submissions (backing, paper, ink lines, red markup, ink
letters, red annotations), constructed once per streamed load with no process loop
or new lights/shadows. Paper is two triangles and backing 12; diagram/text budgets
vary with fixed annotation content (six triangles per non-space letter). Text is
geometry rather than noisy unreadable lettering painted into the paper atlas.

World content is intentionally schematic: the operations base and van's three real
routes, with YOU ARE HERE at the base, not the basement excursion garage. The
blueprint is a main-hall study based on actual GridMap dimensions (48×40 m hall,
30×24 m pit, 6 m ramp widths) with the west balcony extension and a 5 m upper-bar
section. It is not a complete architect's plan or a new casino objective. City
geography and elevator lore remain undefined.

Regenerate the template (does not change approved paint), or explicitly process a
new source (commands from repository root):

```sh
godot --headless --path game -s ../docs/design/model-sources/garage-planning/build_paint.gd
godot --headless --path game -s ../docs/design/model-sources/garage-planning/build_paint.gd -- \
  "$PWD/docs/design/model-sources/garage-planning/paint-source.png"
godot --headless --path game --import
```

## Review and tests

Actual Godot 4.7.2 Compatibility/Mesa captures under
`docs/design/previews/garage-planning/` show stairs, underside/oblique guard joins,
mezzanine, both mapped posters and their first-person-height wall placement. The
paper is blank in the generated painting by design: rendered diagrams are the
actual authored topology, not an AI-invented casino. No browser FPS benchmark or
physical-device playtest is claimed.

```sh
cd game
xvfb-run -a godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/starter_room/capture.tscn -- /tmp/garage-planning-review
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/starter_room -gexit
```

Tests validate indexed winding/normals, stair/guard material replacement, identical
collision dimensions/transforms, board facing/bounds, 128px mipmapped paint, correct
labels/marker, art not obstructing routes and streaming unload/reload. Existing
actual-player stair walking/headroom, van travel, jobs and ENet late-join tests
continue to cover the unchanged gameplay interfaces.
