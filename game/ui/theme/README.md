# UI theme

The Golden Crown look: aged 1960s casino Art Deco.

- `ui_theme.tres`: menus and panels. Aged ivory panels with a brass border, oxblood
  primary buttons with ivory text, parchment `SecondaryButton`s, walnut body text,
  oxblood `HeadingLabel`, letter-spaced brass `BrandLabel`, and a muted teal focus frame
  for the selected option (keyboard / controller). Flat style boxes, no textures.
- `hud_theme.tres`: gameplay HUD. Translucent walnut `HudPlate`s with a thin brass
  border, `HudSlot` / `HudSlotActive` (oxblood) cells, `HudBar` (oxblood HP fill),
  `HudTitle` (ivory caps), `HudDetail` (brass) and `HudAccent` (teal).

Fonts are the bundled Barlow (condensed caps with extra letter spacing) and Inter; no
serif face ships with the game yet.

`ui/hud_layout.gd` (`HudLayout`) places the weapon panel, wallet and HP bar for wide,
narrow and touch screens, keeps them inside safe margins and scales them up on small
stretched canvases. Tests: `tests/unit/test_hud_layout.gd`.
