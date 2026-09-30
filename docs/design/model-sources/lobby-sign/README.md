# Lobby sign: 你好 texture sources

The south lobby's Mandarin greeting sign paints its characters into a runtime
texture instead of a `Label3D`, because the engine's default font covers only
1009 characters (Latin, Greek, Cyrillic and symbols) and has no CJK glyphs, while
a full CJK font is far too large for the ≤128×128 world-texture budget and the
web export.

## Glyph source

`unifont_glyphs.hex` holds the two Plane 0 glyph rows the sign needs, copied
verbatim from GNU Unifont 17.0.04's hex sources:

- download: `https://unifoundry.com/pub/unifont/unifont-17.0.04/font-builds/unifont-17.0.04.hex.gz`
- full file: `unifont-17.0.04.hex`, MD5 `df9c1b49b5e1618b013a8ebaa4eacb4e`
- glyphs: U+4F60 (你, "nǐ") and U+597D (好, "hǎo")

Unifont is dual-licensed under the SIL Open Font License 1.1 and the GNU GPL 2+
with the GNU font embedding exception, both of which permit using glyph shapes
in other works. `game/features/lobby_sign/tools/build_texture.gd` embeds the
same two hex rows and is the source of truth for the shipped texture; this
excerpt keeps the exact reference next to the design.

## Baking

`features/lobby_sign/tools/build_texture.gd` composites the sign albedo
deterministically (no AI generation and no random seed):

- 64×128 `FORMAT_RGB8` image, one UV island covering the whole 1.2×2.4 m face
  (53 pixels per metre).
- Deep burgundy field with hand-tuned paint noise and a soft warm falloff, gold
  inset border frame.
- Each 16×16 Unifont glyph is scaled 3× to a 48×48 cell: 你 at y 8…55, 好 at
  y 73…120, leaving 8 px top/bottom margins and a 16 px gap.

Run from `game/`:

```sh
godot --headless -s res://features/lobby_sign/tools/build_texture.gd
godot --headless --import
```

The tool prints an ASCII preview of the baked texture, writes the runtime
`game/assets/lobby_sign/textures/hello_albedo.png` and an 8× authoring preview
`preview-8x.png` in this directory. Tests compare the shipped PNG against the
tool's output pixel for pixel.
