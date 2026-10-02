# Signage kit

A small library (no `feature.tscn`) for modeled signs that replace floating
`Label3D` text. Instance `res://features/signage/sign_board.tscn` and set:

| Property | Meaning |
| --- | --- |
| `text` | Sign text; `\n` starts a new line. Lower case is drawn as capitals; unsupported characters draw `?`. |
| `letter_height` | Cap height in metres (default 0.14). The board grows to fit the text plus `padding`. |
| `style` | `BRASS`: oxblood board, brass frame and warm letters (casino). `NEON`: black board, dark frame, glowing `neon_color` letters. |
| `mount` | `FLUSH`, `BRACKET` or `HANGING`, see below. |

The readable face looks along **+Z**, like `Label3D`, so a sign can take a label's
transform. Mounts, in the sign's local space:

- `FLUSH`: the board's back is on the wall plane z = 0; nothing pokes behind it.
- `BRACKET`: a wall plate at z = 0 and an arm along +Z (top at y = 0) carry a
  two-sided blade sign whose text faces ±X.
- `HANGING`: two rods rise to the ceiling point at y = 0; the board is two-sided.

Each sign is a `Backing` box, four frame bars and one `Letters` mesh (plus
`LettersBack` when two-sided). Letters are quads on that mesh, UV-mapped into the
shared 64×64 letter-tile atlas `SignLetterAtlas` (5×7 glyphs in 8×8 cells, painted
once at runtime from patterns in `letter_atlas.gd`, nearest filtering, alpha
scissor). All signs share a few cached materials, so many signs cost few draw
state changes and no extra lights.

Keep `Label3D` only for dynamic text that must change at runtime (names over
heads, live counters). Replacing existing labels is Phase 1 tasks E2–E4
(`docs/phase1.md`); list any kept labels here as they are decided.

Tests: `tests/features/signage/test_sign_board.gd` checks the atlas size and
glyphs, the letter quads, and that every mount has a backing and sits flush on its
wall or ceiling.
