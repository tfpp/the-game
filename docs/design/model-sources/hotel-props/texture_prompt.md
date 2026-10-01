# Final image-generation instruction

Paint textures into the pre-established UV atlas grid. Meshes and UV maps are
already built; strictly follow their layout. The guide has five columns and two
rows of props. Each prop cell has four equal quadrants. Preserve all positions.
Replace placeholder colours and white outlines with painted flat diffuse material
imagery, edge to edge, no gutters. Read props left to right across the top row,
then across the bottom row. Each prop requires a unique texture atlas.

For each prop, insert its name and four exact quadrant descriptions from
`texture_zones.json`, in `manifest.json` order: top-left, top-right, bottom-left,
bottom-right. The batches are entries 1–10, 11–20, 21–30, 31–40 and 41–50.

All imagery must be flat surface texture UV artwork, with no perspective rendered
props, concept sheet, whole objects or labels outside textures. The main graphic
(clock face, screen, dial or label) must fit entirely in its top-left quadrant.
Surface patterns in other quadrants fill their rectangle. Use a 1960s–1980s hotel
palette and low-resolution Counter Strike 1.6 diffuse texture style, readable wear,
chunky detail that survives downsampling to 16–64 pixels per quadrant, and no extra
grid lines or borders. Output a wide atlas sheet matching the guide's proportions.

Runtime processing only extracts individual atlases and reduces each to its own
manifest resolution. Texture sizes were reviewed on the actual mapped meshes.
