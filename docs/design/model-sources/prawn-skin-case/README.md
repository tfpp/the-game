# Prawn skin weapon case

A CS2-inspired yellow equipment case for Rusty's skin display: chamfered shell,
separate closed lid, raised lid ribs, two latches, rear hinges and a continuous
U-shaped handle. A painted prawn emblem identifies the shop's cosmetic crates.
Reference: [yellow Spectrum case](https://case.oki.gg/case/spectrum-case).

Authoritative geometry and UV source:
`game/features/pawn_shop/tools/build_skin_case.gd`.
Floor-centred pivot, front +Z, approximately 0.70 × 0.593 × 0.656 m.
172 triangles, one mesh surface, one 128×128 diffuse atlas, no moving parts.
The gameplay collision keeps the original 0.70 m cube.

`uv_template.png`, `uv_manifest.json` and `paint-prompt.txt` retain the exact
painting layout and built-in ImageGen instructions. The generated high-resolution
painting is retained as `paint-source.png`; only its small atlas goes into the game.

Rebuild geometry with Godot:

```sh
godot --headless --path game --script res://features/pawn_shop/tools/build_skin_case.gd
```

Pass the retained `paint-source.png` after `--` to rebake the atlas. A geometry-only
rebuild preserves existing paint. The prop's native scene is `skin_case.tscn`.
