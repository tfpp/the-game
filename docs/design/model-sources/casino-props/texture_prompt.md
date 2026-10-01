# Texture generation prompt

Used as an image edit with `uv_atlas_sheet_guide.png`. Five calls each substitute
10 catalog entries into `{rows}`. Rows are numbered 1–10, naming each prop and its
TOP LEFT, TOP RIGHT, BOTTOM LEFT and BOTTOM RIGHT strings from `texture_zones.json`.

```text
Paint production diffuse textures into this existing UV atlas guide. The 50 casino meshes have ALREADY been modeled and UV mapped. This guide contains a FIVE COLUMN by TWO ROW grid of ten separate prop atlases, each with FOUR equal quadrants. Preserve the grid and all quadrant positions precisely. Replace placeholder colors and guide outlines entirely with flat painted surface artwork; no gutters or extra borders. Read prop cells left to right across TOP row, then left to right across BOTTOM row. Every prop has its own completely independent atlas, NOT a shared material sheet. Exact quadrant assignments:
{rows}
ART DIRECTION: 1960s–1980s film-noir casino, GoldSrc / Counter-Strike 1.6 low-poly game assets. Muted emerald felt, black bakelite, dark mahogany, oxblood leather, burgundy velvet, ivory paper, tarnished brass. Use broad matte painted tones and minimal readable wear, NOT photorealistic grain, specular glass, detailed scratches, detailed fabric weave, or high frequency texture noise. Crisp low-resolution painted details that survive final 8–64 pixels per quadrant. Flat orthographic surface artwork only: NEVER a perspective object rendering inside a material panel, never a complete object scene, no shadows cast between panels. Large important graphic such as card face, betting layout, slot reels, clock face or label must be contained ENTIRELY in that prop's TOP LEFT quadrant. Pure material panels should be simple repeatable material swatches. Circular dial/wheel/button graphics should be centered front-on circle graphics with no perspective. Do not paint complete handles or stems into material panels: paint their flat material surfaces. No outside titles or labels. Wide landscape output matching the guide aspect ratio 5:2.
```
