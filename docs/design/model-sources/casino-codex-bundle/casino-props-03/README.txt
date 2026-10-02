CASINO LOUNGE PROPS III — CIGAR AND BEER BOTTLE

Cigar: 20 triangles, six-sided continuous body, 16×16 opaque PNG.
Amber beer bottle: 68 triangles, six-sided body/shoulder/neck/crown-cap profile,
32×32 opaque PNG. Band, labels, glass highlights and cap crimp marks are painted.
Cigar ash end is lit: orange-red coal and a short charred wrapper section.
The GLB includes a 16×16 emission map isolated to that end; the HTML and CPU
previews use the same emission. The ember adds no geometry or animation.

GLB: one indexed mesh and material per asset, embedded texture, nearest filtering.
OBJ files reference the accompanying MTL and native PNG. Y up; metres.
Cigar is .13 m long, .022 m diameter, along X, ash at -X and mouth at +X.
Beer bottle is .264 m tall and .062 m maximum nominal diameter; label faces +Z.

Open casino-props-03-preview.html in a WebGL-capable browser to orbit, inspect
atlases, toggle wireframe and download the exports. Self-contained; no remote
resources. JavaScript syntax checked; browser interaction not tested here.
CPU previews render the actual exported indexed meshes and their native PNGs.
GoldSrc MDL compilation is not included.

Native textures are cigar-16.png and beer-32.png. The larger edit/guide PNGs
are flat painting references and inspection aids, never engine textures.
ImageGen paints the flat material charts. Native resizing and deterministic
nearest chart-edge extrusion prevent dark gutter bleeding. UV boundaries
are inset by half a texel. Vertex duplication at UV/normal seams is intentional.

Python dependencies: NumPy and Pillow.
python3 build_props.py rebuilds geometry while preserving existing textures.
To repaint, use --cigar-texture and --beer-texture with new source paintings;
resizing and edge padding run automatically.
python3 build_preview.py updates the embedded HTML.
python3 render_preview.py creates CPU previews.
python3 validate_assets.py checks vertices, normals, winding, triangle areas,
UVs, native resolutions, padding and GLB image/structure.

texture-prompts.json records the ImageGen edit prompts.
asset-generation-prompt.txt records modelling and UV construction rules.
validation.json records final export checks.
