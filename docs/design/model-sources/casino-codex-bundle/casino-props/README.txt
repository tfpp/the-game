CASINO LOUNGE PROPS — 1960s–1980s / PSX–GoldSrc aesthetic

Actual indexed low-poly meshes, with realistic painted material atlases.

Standing ashtray with cigarette: 104 triangles / 32×32 PNG
Standalone cigarette: 12 triangles / shared ashtray 32×32 PNG
Wine bottle: 44 triangles / 32×32 PNG
Hollow stainless wine bucket: 76 triangles / 32×32 PNG
Walnut wine rack cabinet, including three bottles: 154 triangles / 64×64 PNG

Open casino-props-preview.html in a WebGL-capable browser to orbit individual
props or the collection, inspect UV guides, toggle wireframe, and download GLBs.
The preview is self-contained and uses no remote resources. JS syntax was
checked; interaction has not been tested in a browser in this environment.
CPU-rendered previews show the exported geometry and the native textures.

GLBs contain one mesh and material per asset, and an embedded opaque texture
with nearest sampling. OBJ files reference the accompanying MTL and PNG.
Units: metres. Y up. Cabinet opening and bottle label face +Z.
This is a visual asset study; GoldSrc MDL conversion is not included.
Vertices at normal/UV seams are duplicated intentionally.

All actual material textures are the native -32.png / -64.png files. The larger
-edit.png and -guide.png images are painting references and UV inspection aids,
not engine textures. Atlas gutters are filled deterministically by nearest
chart-edge colour extrusion, with half-texel-inset UV boundaries.

build_props.py rebuilds geometry/exports, preserving existing final textures.
To repaint, supply --ashtray-texture, --bottle-texture, --bucket-texture and
--cabinet-texture with ImageGen results. The script downsamples and extrudes
padding. Python dependencies: NumPy, Pillow.
build_preview.py embeds the exports in the HTML viewer.
render_preview.py makes the main and close-up CPU previews.
validate_assets.py verifies mesh/UV/normals/winding/texture/GLB properties.

asset-generation-prompt.txt contains the reinforced construction and texture
budget rules. texture-prompts.json records the four flat-atlas painting prompts.
validation.json records export checks.
