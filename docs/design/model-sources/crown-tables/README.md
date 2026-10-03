# Crown gaming tables

The poker and blackjack tables are authored from scratch in `remake.gd`, the
native mesh-first source. They replace the earlier assembled kit tables.
Blockbench MCP is unavailable; this uses the repository-supported Godot path.
Only the craps assembly remains in `build.gd`; it skips all remade models so a rebuild
cannot restore the rejected furniture. See the final replacements below for baccarat
and draw poker.

The new card tables use continuous perimeter loops: inset felt meets the padded
burgundy rail, the rail meets a walnut apron with thin brass edging, and two broad
pedestals meet the underside and fitted sloped bases. They are static, floor-centred,
Y-up, metres, with +Z as the player approach. Blackjack has a straight dealer edge
and a semicircular player edge. Poker uses a 16-sided oval. Both retain their original
horizontal collision footprints; collision remains a separate gameplay component.

| Model | Bounds (m) | Triangles | Materials | Copies |
|---|---|---:|---:|---:|
| Poker | 2.42 × 0.98 × 1.42 | 248 | 1 | 1 |
| Blackjack | 2.70 × 0.98 × 1.32 | 212 | 1 | 1 |

The shared 128×128 opaque atlas is painted by ImageGen against
`card-tables-uv-guide.png`. The exact prompt is `paint-prompt.txt`; the full painting
is `card-tables-painted.png`. `remake.gd` exports deterministic charts, uses half-texel
inset sampling and extrudes two native pixels of each island's own colour into its
gutter. Repeated wood surfaces intentionally reuse charts; felt receives the largest
visible allocation. Native texture: `game/assets/table_games/textures/card_tables.png`.
Material uses nearest mipmap filtering. Normal geometry rebuilds preserve the paint.

Run from the repository root with Godot 4.7:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/crown-tables/build.gd
godot --headless --path game -s ../docs/design/model-sources/crown-tables/remake.gd
```

Only when processing new approved paint, run the remake with `-- --paint`, import
again, then rerun without that argument to bind the imported texture. GLBs here
are interchange exports; native ArrayMeshes in `game/assets/table_games/models/`
remain runtime sources. `remake-inventory.json` records the new models; `inventory.json`
records the remaining craps assembly.

Review actual exported meshes using a display and Compatibility renderer:

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  -s ../docs/design/model-sources/crown-tables/review.gd
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/table_games/capture.tscn
```

Retained front, rear, side, underside and UV checker renders plus gameplay room
captures are in `docs/design/previews/crown-games/`. Tests validate indexed geometry,
finite positions, nondegenerate triangles, bounded UVs, small textures and collision.

## Seating and animated dealers

Chairs reuse `game/features/casino_props/props/dealer_chair.tscn` with its approved
painted atlas. `bake_dealer.gd` is the authoritative editable motion source for
full-body idle, greeting, shuffle, deal, reveal, collect, payout and roll clips.
It samples the existing rig, arm IK and finger posing offline at 30 Hz, saving a
compressed native AnimationLibrary. Runtime playback has one pose owner and
bone-attached cosmetic props; floor-centred standing dealers face +Z.

```sh
godot --headless --path game res://../docs/design/model-sources/crown-tables/bake_dealer.tscn
```

The gameplay capture now also produces action stills and a sequence of rendered
frames for an animation preview. Review actual mapped staff and furniture in the
room, including chair facing, hand height and contacts. These are renderer
captures, not performance benchmarks.

To encode the captured 12 fps preview with the existing FFmpeg tool:

```sh
ffmpeg -y -framerate 12 -i /tmp/crown-dealer-frames/frame-%04d.png \
  -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=none' \
  docs/design/previews/crown-games/dealer-animations.gif
```

The GIF shows the actual rig, mapped material and bone-attached props. It covers
all eight native clips; the roll segment uses the craps croupier.

## Final baccarat and draw-poker replacements

`remake.gd` also authors the baccarat table from the same continuous mesh profile,
with its original 3.675×1.7325 m floor footprint, two fitted pedestals and 248
triangles in one material. It reuses the approved shared card-table atlas; the
runtime view supplies Player and Banker labels on the felt. `build.gd` now rebuilds
only craps and cannot overwrite any of the four remade models.

`draw_poker.gd` is the cabinet's authoritative source: a closed nine-point side
profile extruded across a 0.68 m width, with an integrated angled glass face and
control deck. It preserves the 0.68×1.49×0.76 m footprint and uses 32 indexed triangles
and one material. Its dedicated 128×128 opaque atlas is ImageGen-painted against
`draw-poker-uv-guide.png`; the exact prompt is `draw-poker-paint-prompt.txt` and the
full source painting is `draw-poker-painted.png`. The UV charts reuse the two side
panels, isolate the screen and control deck, inset sampling by half a texel, and
extrude two pixels of each chart's own colour into the gutters. Filtering uses
nearest mipmaps. Live card labels follow the angled screen, rather than the
horizontal card-table layout. GLB interchange export is `draw-poker.glb`.

```sh
godot --headless --path game -s ../docs/design/model-sources/crown-tables/remake.gd
godot --headless --path game -s ../docs/design/model-sources/crown-tables/draw_poker.gd
```

The cabinet builder preserves approved paint by default. Add `-- --paint` only
when processing new artwork, import, then rerun without the flag. Review renders
now include the baccarat table and draw-poker cabinet from front, rear, side and
underside, plus their room placement and live draw-poker controls.
