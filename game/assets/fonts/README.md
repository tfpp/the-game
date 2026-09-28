# Fonts

All SIL Open Font License 1.1 (each folder's `OFL.txt`), from Google Fonts. Inter, Exo 2
and Orbitron are static weights instanced from the variable fonts with overlaps removed:
`uvx --from fonttools --with skia-pathops fonttools varLib.instancer <font> wght=700
--remove-overlaps --static -o <out>` (Inter: `wght=400 opsz=14`). Barlow is static upstream.

| Font | Role | File |
|---|---|---|
| [Inter](https://rsms.me/inter/) | Body text: the default font (labels, chat, signs), set as `ThemeDB.fallback_font` by `core/game/game.gd` | `inter/Inter-Regular.ttf` |
| [Exo 2](https://fonts.google.com/specimen/Exo+2) | Headings (`HeadingLabel`, release notes, inventory) | `exo2/Exo2-Bold.ttf` |
| [Barlow](https://fonts.google.com/specimen/Barlow) | Buttons, and small HUD details | `barlow/Barlow-SemiBold.ttf`, `barlow/Barlow-Medium.ttf` |
| [Orbitron](https://fonts.google.com/specimen/Orbitron) | HUD readouts (version, players, money, HP) | `orbitron/Orbitron-Bold.ttf` |

Use static, overlap-free weights: Godot draws overlapping contours (as in variable fonts
and Google's generated static instances) with visible seams, like a line through Exo 2's
"M".
