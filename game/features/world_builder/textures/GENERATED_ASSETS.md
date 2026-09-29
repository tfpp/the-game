# Hotel texture set

Created with the built-in image-generation tool on 2026-09-29. The user's room and
hallway references guided the warm plaster, walnut, damask and burgundy palette.

Source: `../tools/source_atlas.png` (four quadrants). Runtime assets:
`plaster.png`, `wallpaper.png`, `walnut.png`, `carpet.png`, each 128×128.
Reproduce the crop/downsample with:

```sh
godot --headless --path game -s res://features/world_builder/tools/import_textures.gd
```

Prompt:

> Create a production GAME TEXTURE ATLAS, square 1024x1024. It must be exactly a
> 2-by-2 grid of FOUR equal square texture tiles, each filling precisely one quadrant
> edge to edge, no gutters, no labels, no room rendering, no perspective, no objects.
> Top left: warm ivory aged plaster, soft mottled limestone/beige cloud texture. Top
> right: warm cream and muted gold Victorian damask wallpaper, elegant repeating
> stylized floral pattern, medium contrast. Bottom left: rich dark honey walnut
> timber, fine straight vertical wood grain, no panels or hardware. Bottom right:
> burgundy and antique gold Persian hotel carpet repeating floral-medallion pattern,
> no outside border. Each quadrant independently seamlessly tileable at its own
> edges. Flat evenly lit albedo only, no cast shadows, no highlights. Intended for an
> old grand hotel procedural interior matching warm classic panelled rooms and
> hallways, PS1 inspired pixel game with 128px textures: bold readable motifs and
> restrained painterly grain. No text or watermarks.

The source was returned at 1254×1254; `import_textures.gd` extracts its 627×627
quadrants and downsamples them. The tile motifs can reveal repetition at long wall
scales; panel geometry breaks that repetition up. Surface detail, door panels,
frames, columns and lamps are generated mesh geometry, not baked into these maps.
