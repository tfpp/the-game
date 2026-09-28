# Generated casino artwork

Original project artwork generated with the built-in ImageGen tool, September 2026.
The PNGs are base-color artwork, not measured material scans. The PS1 materials use matte vertex lighting without normal maps or metal reflections.
Reel artwork lives in `../../slot_machine/textures/reel_symbols.png`.
Models are original Blender meshes; rebuild with `../tools/build_models.py`.

## Saved artwork

- [Carpet base color](carpet_albedo.png)
- [Wallpaper base color](wallpaper_albedo.png)
- [Walnut base color](walnut_albedo.png)
- [Slot reel symbols](../../slot_machine/textures/reel_symbols.png)

The originals are 1254 by 1254 pixels. Import settings reduce them to 128×128,
generate mipmaps and use lossless compression. Materials sample with nearest
filtering; source artwork stays available at full resolution. The old carpet was replaced
for the reference salon; its earlier artwork remains in Git history. The first
prompts below record the previous generation brief. Current replacements follow.

## carpet

Use case: stylized-concept
Asset type: seamless PBR base-color texture for a realistic 1960s casino carpet in a Godot game, square 1024x1024.
Primary request: Create one perfectly flat, orthographic, edge-to-edge seamless repeating carpet albedo map. Rich muted oxblood and burgundy woven wool ground, elegant small-scale interlocking art-deco fan and lily motifs in antique ochre-gold and restrained deep petrol teal. Fine visible loop-pile textile fibres, subtle uneven wear and tasteful faded dye, luxurious but aged. Many repeat units across the square, around six to eight, balanced restrained pattern that reads cleanly across a large casino floor.
Lighting: completely diffuse and uniform, delightfully detailed material color only, no baked highlights, shadows, perspective, ambient occlusion or vignette.
Constraints: tile seamlessly on all four edges; no border, no text, no objects, no room scene, no watermark. Deliver only the usable texture.

## wallpaper

Use case: stylized-concept
Asset type: seamless PBR base-color texture, square 1024x1024, for a realistic vintage casino wall.
Primary request: A single flat seamless wallpaper texture. Elegant 1960s art-deco damask in desaturated petrol teal, dark blue-green and fine antique champagne-gold linework. Small stylized ginkgo fans and elongated lily leaves form a delicate symmetrical repeating motif, four or five repeats across the image. Tactile finely woven paper, subtle faded pigment and tiny irregularities, mostly calm teal negative space, refined understated luxury. Lighter and more muted than a black wall, no high contrast stripes.
Lighting: uniform neutral diffuse albedo only. Orthographic straight-on material scan, no shadows or baked lighting.
Constraints: fill whole square and tile across all four edges, no border, no text, no objects, no scene, no perspective, no watermark. Only the texture.

## walnut

Use case: stylized-concept
Asset type: seamless PBR base-color texture, square 1024x1024.
Primary request: Photorealistic dark American walnut veneer for a restored 1960s casino's furniture and mechanical slot machine side panels. Beautiful narrow vertical flowing wood grain and subtle cathedral figuring. Rich warm dark chocolate and restrained amber brown, tiny pores, restrained age and fine wear. One continuous sheet, no planks or joins, no knots, no scratches larger than the grain.
Lighting: completely even, neutral diffuse material scan, no baked lighting, no reflections, no shine, no shadows, no vignette.
Constraints: orthographic edge-to-edge usable albedo texture, seamlessly tileable in X and Y, no objects, text, borders or watermark.

## reels

Use case: illustration-story
Asset type: production texture atlas for a 1960s mechanical slot machine reel, square 1024x1024.
Primary request: One cream ivory paper reel strip containing EXACTLY FIVE equally tall horizontal cells stacked vertically, no dividers. Each cell is exactly one fifth of image height. A single centered classic casino icon in each cell, in this precise top-to-bottom order: 1 red numeral "7" outlined in antique gold; 2 black rectangular "BAR" plaque with white letters and fine gold border; 3 five-point golden star; 4 polished golden bell with red detail; 5 faceted emerald green gemstone. Each icon fits fully inside the middle 60 percent of its row height, centered horizontally. Make symbols about 25 percent of total image width, with generous blank cream on the left and right. Classic premium mid-century screenprinted reel artwork, crisp readable shapes with restrained engraved detail and subtle ink imperfections.
Constraints: fully flat frontal print artwork for a texture, not a machine or mockup. Completely uniform ivory background, no shadows cast onto background, no perspective, no borders around image, no extra text or extra icons. The centers are y=10%,30%,50%,70%,90%; identical cell sizes.

## Reference salon — built-in image generation

The following were generated with the built-in ImageGen tool for the supplied
casino reference, then imported at 128×128 with mipmaps. Models are original Blender
geometry, not generated mockups. The reference image itself is not shipped.

### Current carpet (`carpet_albedo.png`)

Use case: stylized-concept. Asset type: seamless game floor base-color texture,
square. The supplied image is STYLE REFERENCE ONLY. Create ONLY a perfectly flat,
orthographic, edge-to-edge tileable worn burgundy casino carpet texture, matching
the red and muted ochre carpet in the reference. One large open diamond/ogee
medallion repeat, with a smaller worn floral rosette at its center and partial
neighboring repeats continuing at the edges. Deep muted oxblood and brick-red
ground, dusty dull mustard-gold motifs, subtle faded woven mottling. Crucial: quiet,
low-contrast, broad simple shapes that will still read when downsampled to 128x128.
Restrained three-tone palette. Photo-derived fabric character from an old
late-1990s casino game, not crisp vector ornament. No teal, no blue, no white, no
rainbow, no dense tiny repeated fans. No room perspective, no objects, no light
falloff, no text, no border, no watermark. Fill the whole square with usable
seamlessly repeating carpet albedo.

### Landscape (`landscape_painting.png`)

Use case: stylized-concept. Asset type: square 128-pixel game artwork source. Create
ONLY an antique, dark Victorian oil landscape painting of a wooded river valley
and distant manor, muted dark umber, olive green, warm ochre and smoky blue gray,
aged cracked canvas texture. Flat straight-on view, artwork fills the whole square,
no frame and no wall, no perspective. Broad painterly shapes and restrained
contrast, strongly readable at 128x128, evocative photo-derived museum painting
from a late-1990s PlayStation casino environment. No people close up, no text, no
watermark. Nearly black shadow masses and a small warm amber sky opening. The
painting will hang in a dim old luxury casino inside a gold frame.

### Felt (`felt_albedo.png`)

Use case: stylized-concept. Asset: seamless square game texture. Create a perfectly
flat edge-to-edge tileable photograph-derived worn emerald green baize felt, like
a late-1990s casino gaming table. Dark muted forest emerald with fine wool fibres,
soft mottled wear, broad subtle patches, no highlights or shadows, no objects, no
cards, no chips, no writing, no gold lines. Must retain material character
downsampled to 128x128 with nearest filtering. Restrained contrast, green only,
completely orthographic. Not a room or table: just the usable fabric albedo.

The returned felt has darkened edges; its material samples the central 56% to
exclude those edges. Geometry supplies the cards, chips and betting arc.

### Ceiling (`ceiling_albedo.png`)

Use case: stylized-concept. A square perfectly seamless game material texture,
ONLY worn warm umber/ochre painted plaster for the ceiling of a Victorian casino,
photograph-derived, low contrast, faded smoky warm brown stippling, very subtle
old stencilled floral medallion traces across the surface. Broad organic mottling
visible at 128x128 texture resolution. Flat even neutral illumination across the
entire image, absolutely no vignette, no edge darkening, no shadows, no border,
no room or perspective. Matte material albedo, no shiny highlights. Muted warm
medium brown and dark tan only, no green or blue, no text. All four edges must
repeat seamlessly.


## Model surface pass — built-in ImageGen

### Shared atlas (`surface_atlas.png`)

Use case: game-material texture atlas. Create one square image divided
mathematically into EXACTLY four equal square quadrants, NO borders or gaps or
text. Every quadrant must have neutral middle-gray coloration, roughly the same
average gray value, grayscale only, and subtle realistic small-scale material
variation. Upper left: smooth human skin surface microtexture, very subtle fine
pores and warm-skin-like organic mottling but GRAYSCALE, no face or body parts.
Upper right: fine tailored wool and cotton weave, restrained woven fibres,
grayscale. Lower left: supple worn leather grain, small soft wrinkles and pores,
grayscale. Lower right: aged satin metal with very fine brushed wear and tiny
subdued scuffs, grayscale. These are four flat orthographic material albedos,
evenly lit, each seamlessly tileable within its own quadrant. No shadows,
highlights, vignettes, objects or logos. Broad enough grain to read after the
whole atlas is reduced to 128x128 (64x64 pixels per quadrant), late-1990s game
surface details. Avoid high contrast noise, large cracks or decorative patterns.
The resulting atlas will be tinted and UV-mapped onto low-polygon game characters
and casino furniture.

### Legacy prop grain (`prop_grain.png`)

Use case: stylized-concept. A square seamless neutral material albedo for small
low-poly PS1 game props. Only a flat uniform middle-gray matte surface with subtle
photo-derived fine stippling, faint wear and very fine fibres. Grayscale only,
average gray 65 percent, low contrast, no objects, no large marks, no shapes,
no text, no lighting gradients, no edge darkening, no vignette. Perfectly seamless
on four edges. Designed to be downsampled to 128x128 and tinted by a game material.
It should add subdued tactile grain to otherwise flat-colored props, never look
like camouflage, checkerboard, gravel or strong noise.

Both sources are preserved at generated resolution and imported at 128×128 with
mipmaps. The atlas samples inside each tile to avoid neighbouring material regions.
