Built-in imagegen edit, using uv_template.png as the exact atlas layout reference.

Paint a square flat diffuse UV texture atlas for a 1990s GoldSrc-style, low-poly service elevator. Preserve every rectangle and the dark neutral gutter exactly. No perspective or rendered object, no labels, no new islands. It will be downsampled to 128x128; use broad painted colour and large readable seams, restrained wear and no tiny noise.

Coordinates are on a 128x128 grid, origin top-left, scaled to the supplied guide:
- WOOD x2 y2 w63 h63: dark reddish walnut panels, three framed vertical panels, subdued brass edges, broad worn finish. Top edge is upright on the cab walls. Warm aged casino elevator, not modern glossy wood.
- FLOOR x2 y69 w48 h48: faded burgundy carpet, simple gold perimeter border and subtle dark central field. Top-down square.
- CEILING x54 y85 w38 h38: warm dark wood ceiling with simple broad panel seams. Lamp is separate geometry, do not paint a fake perspective lamp.
- DOOR x69 y2 w40 h79: upright aged brushed bronze and dull steel sliding door leaf, recessed long panel, dark inset seam and subtle lower scuffing. No caution stripes, development grid, windows or lettering. This painting is shared by both door leaves and both sides.
- CONTROL x96 y85 w21 h15: small steel plate with one raised-looking round brass pushbutton centered. Horizontal rectangle is a rotated island; no text or fake multiple buttons.
- BRASS x2 y121 w4 h4: uniform muted aged brass, minimal broad variation.
- LIGHT x10 y121 w4 h4: warm ivory frosted lamp diffuser, no edges or markings.
- STEEL x18 y121 w4 h4: neutral dark brushed steel, quiet broad shading.
All remaining pixels: uniform dark charcoal matching guide gutters. Replace guide colours completely within the rectangles, preserve the rectangle bounds. No photographic lighting or baked room shadows. Compatible with the established wood/brass elevator concept.
