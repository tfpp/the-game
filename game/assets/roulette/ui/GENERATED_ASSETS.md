# Roulette UI artwork

`panel.png`, `plaque.png`, `button.png` and `chip_pointer.png` are original project artwork
generated with the built-in ImageGen tool, September 2026, for the roulette betting and
seat screens (`features/roulette/roulette_ui_theme.gd`).

Each source (about 1250–2170 px wide) was cropped to its solid pixels (alpha ≥ 0.5),
downscaled with Lanczos, and given hard alpha edges: panel 128×128, plaque 192×36,
button 144×34, chip pointer 24×17. They are drawn as nine-slices with nearest filtering
(margins: panel 12, plaque 10, button 8 pixels). Button hover/pressed/disabled states
are tints of the one button texture.

`chip_<dollars>_icon.png` are not generated: `features/roulette/tools/bake_chip_icons.gd`
cuts the round face out of each `assets/casino_chips/textures/chip_<dollars>_albedo.png`
with a transparent circular mask, so the rack matches the 3D chips.

## Shared style prompt

Retro low-poly 1990s 3D game UI asset, low-resolution pixel-art texture look with
visible chunky pixels and broad blocks of colour, 1960s faded-luxury casino style (The
Golden Crown casino). Palette: dark mahogany wood, aged dull brass/gold (not
mirror-polished), deep casino-green felt, burgundy velvet, cream/ivory. Flat front-on
orthographic view, perfectly symmetric, no perspective, no text, no logos, no drop
shadow outside the object, simple slight wear and grime.

## panel

A single square UI window panel frame designed for 9-slice scaling: a uniform border of
dark mahogany wood about 10% of the width on every side, with a thin aged-brass inlay
line inside the wood and small brass corner studs, surrounding a large flat plain
dark-green felt centre with only very subtle low-frequency texture (the centre must be
uniform so it can stretch). Fill the whole image edge to edge.

## plaque

A single wide horizontal header plaque/nameplate for a UI title bar designed for 9-slice
scaling: burgundy velvet flat centre, framed by an aged brass rim with a thin dark
outline and small brass rivets at the four corners. Uniform plain centre so it can
stretch horizontally. Isolated on transparent background.

## button

A single rectangular UI button plate designed for 9-slice scaling, roughly 3:1 aspect
ratio: flat cream/ivory enamel centre with a uniform aged-brass bevelled border and a
thin dark outline, slight raised look. Centre must be plain and uniform. Isolated on
transparent background.

## chip_pointer

Replaced an earlier brass selection ring. Chosen over a warm lamplight pool and a velvet
cushion tile generated at the same time.

A small brass casino dealer's win marker used as a UI selection pointer: a short
downward-pointing faceted brass chevron/arrowhead with a cream enamel inlay, chunky and
readable at small size. Isolated on transparent background.
