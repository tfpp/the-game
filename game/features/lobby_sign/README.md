# Lobby sign

A tall burgundy-and-gold banner in the Golden Crown's south lobby that greets
players with 你好 — "hello" in Mandarin — plus a small `HELLO · NI HAO` caption.
It hangs on the south lobby wall at (10, 2.25, 34), facing north into the lobby:
east of the south exit corridor (the 5 m gap at x -2.5…2.5), between the coat
check axis and the jump lounge, and clear of the sofas, the hotel door and the
sconces.

## Why a texture instead of a Label3D

Godot's default theme font covers 1009 characters (Latin, Greek, Cyrillic) and
no CJK, so a `Label3D` would render 你好 as tofu boxes. No CJK font ships with
the game, and a full one is far too large for the ≤128×128 world-texture budget
and the web export. The characters are therefore painted into a 64×128
albedo texture (53 px per metre on the 1.2×2.4 m face) from GNU Unifont 17.0.04
glyph bitmaps, following the repo's deterministic authoring pattern:
`tools/build_texture.gd` is the source of truth and prints an ASCII preview,
and `docs/design/model-sources/lobby-sign/` records the hex excerpt,
provenance and the 8× authoring preview.

Rebuild after changing the recipe:

```sh
godot --headless -s res://features/lobby_sign/tools/build_texture.gd
godot --headless --import
```

## Scene layout

- `Sign` at the south wall's inner face, rotated to face readers in the lobby.
  The backing starts 5 mm in front of the wall, like the annex easter-egg
  plaques.
- `Plaque` is a walnut `BoxMesh` using `features/casino_hub/materials/wood.tres`
  (the same shared material the annex plaques reference).
- `Face` is a `QuadMesh` with `materials/face.tres`: unshaded for night
  readability, nearest-mipmap filtering, no repeat.
- `Caption` is a `Label3D` in the lobby's label style (gold on dark outline).

Static per-peer scenery: no scripts, colliders, lights, timers or network
messages. Every peer — server, clients, late joiners and offline play — loads
the same immutable scene before networking starts, and there is no player state
to persist or clean up.

Tested by `tests/features/lobby_sign/test_lobby_sign.gd`, including wall
mounting, reading clearance, the south corridor mouth, the baked texture
against the Unifont reference, and the static budget.
