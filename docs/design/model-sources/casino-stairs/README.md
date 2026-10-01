# Casino stair module

Authoritative source: `casino_stair_module.bbmodel`, authored in Blockbench
Generic Model. Original walnut, deep red carpet and muted gold nosing, guided by
the casino concept and existing stair treatment in `world_builder/stairs.gd`.

**1 m wide × 1.25 m rise × 2 m run**, +Y up, rises along +Z. Bounds X [-.5,.5],
Y [0,1.25], Z [-.5,1.5]. The floor-centred cell starts at Z -.5; five steps have
**0.25 m risers** and **0.4 m treads**. Modules join every 2 m horizontally and
1.25 m vertically. Four modules rise one 5 m story. Prefab
`game/features/room_kits/casino_stair_module.tscn` and GridMap item **15** use
smooth wedge collision, following the repository's stair walking-proxy approach.
The visual risers sit up to 0.25 m above that continuous walking plane.

Performance preference retained: static opaque architecture, desktop/web Godot
Compatibility, roughly 1–15 m viewing distance, dozens of repeated modules;
not benchmarked. **44 triangles, one surface, one material, 64×64 albedo** with
nearest mipmaps. Twenty-two quads provide treads, risers, sides, back and underside.
Painted gold nosing adds no geometry, lights, metal maps or transparency.
Named padded islands maintain **24 pixels/metre in both directions**. Side and
cap faces share wood; stair treads and risers reuse their matching UV rectangles.
UV manifest and guide are stored here. Runtime textures remain under 128×128.

GridMap item **16** reuses the original brass/walnut railing span, baked to the
same 1.25 m / 2 m slope with upright balusters. The builder derives its convex
collision from the transformed guard volume. Vertical posts are separate shared
item 10 cells. This variant introduces no new texture or shader.

## Rebuild and review

In a new empty Generic Model project, run `build_blockbench.js`, then load
`export_blockbench.js` and call `exportCasinoStairs(repositoryRoot)`. It saves
editable source, glTF, PNG, UV manifest and template. Conversion bakes Blockbench's
16 units/metre into native Godot mesh coordinates:

```sh
godot --headless --path game -s ../docs/design/model-sources/casino-stairs/build_godot.gd
godot --headless --path game --editor --import
```

The casino offline builder adds items 15/16 and uses the balcony layout recipe.
Do not rebuild the whole casino over manual painted edits without preserving them.
The live game loads saved nodes without regenerating geometry. Review captures in
`docs/design/previews/mariachi-balcony/` show stairs, landing, bar and stage from
the actual saved scene. Tests walk the real controller up/down without jumping,
ray-test module joins, check headroom/guards and retain stage access tests.
