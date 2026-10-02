# Casino marquee authoring

Build the modeled panel, raised lettering and frame with
`features/street_district/tools/build_casino_sign.gd`. The mesh is authored
before the dedicated generated atlas. Explicit UVs use padded quadrants:
upper left dark petrol metal; upper right brass; lower left ivory bulbs;
lower right red enamel. The runtime image is resized to 64x64 with nearest
sampling. Bulb and accent meshes share this sign's own texture.

Texture generation prompt: square 2x2 flat material atlas, GoldSrc coarse
painted style, no letters or scene. Exact equal quadrants: dark petrol-green
aged metal, warm brass with scratches, warm ivory frosted bulb glass, dark
red enamel. Broad low-frequency details readable at 64x64. Lettering is
physical extruded mesh geometry; do not paint letters into the artwork.
