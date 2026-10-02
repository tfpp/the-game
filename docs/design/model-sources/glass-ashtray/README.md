# Small glass tabletop ashtray

Authoritative mesh source: `build.gd`, a closed eight-sided pressed-glass bowl
with an open/recessed interior and a continuous thick rim. In metres, Y up,
floor-centred: 150 mm diameter, 26 mm high, 6 mm interior floor. Static decoration
at cocktail-table viewing distance, with no pickup or rigid-body behavior.

64 triangles, one mesh surface, one material, one 32×32 atlas. Four padded UV
regions share the source template: outer wall (2,2,28,10), inner wall (2,16,28,6),
floor (2,26,10,4), rim (16,26,14,4), in native pixels. Bands unwrap by circumference;
repeated facets share a strip and caps reuse the floor patch. Runtime UVs stay
half a texel inside the strips. The rim and bowl are geometry, not a painted
object silhouette. Translucent sea-green glass uses nearest mipmaps and alpha
depth prepass; no extra lights, refraction or reflective capture is introduced.

ImageGen painted `uv-template.png` using the exact retained `paint-prompt.txt`.
The original painting stays here as `paint-source.png`; the runtime PNG is 32×32.
Do not repaint during a geometry rebuild. From the repository root:

```sh
godot --headless --path game -s ../docs/design/model-sources/glass-ashtray/build.gd
```

The reusable scene is `game/features/casino_props/props/glass_ashtray.tscn`.
Table decorations have collision disabled. Actual tabletop and room captures
are in `docs/design/previews/casino-seating/`. Tests inspect exported dimensions,
the recessed floor, native paint/mipmaps, normals, nondegenerate faces and winding.
