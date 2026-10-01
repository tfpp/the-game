CASINO LOUNGE PROPS II — 1960s–1980s / PSX–GoldSrc aesthetic

Four actual indexed low-poly meshes with painted native-resolution UV atlases.
Walnut pedestal cocktail table: 68 triangles / 64×64 PNG / 1.045 m tall
Burgundy vinyl pedestal bar stool: 134 triangles / 32×32 PNG / .752 m seat
Brass wall clock: 48 triangles / 32×32 PNG / about .28 m wide
Martini glass: 68 triangles / 16×16 PNG / .15 m tall

Table and stool are continuous lathed bodies rather than stacked primitive
meshes. Stool has a six-sided triangular-section foot ring and three slim
supports fitted to the flat surfaces of its hexagonal stem and ring. The
clock's two hands are actual flat geometry, independent of the flat dial
painting. Glass has a continuous foot, stem and hollow conical bowl, with an
opaque pale grey-green glass approximation suitable for this texture budget.

GLB files each contain one indexed mesh, one material and an embedded opaque
PNG, with nearest filtering. OBJ files reference accompanying MTL and PNGs.
Units: metres; Y up; clock face points +Z, with its origin at dial centre.
These are visual assets; GoldSrc MDL compilation is not included.

Open casino-props-02-preview.html in a WebGL-capable browser for orbit, model
selection, wireframe, atlas inspection and downloads. This self-contained
viewer has no external dependencies. JS syntax was checked. Browser interaction
was not tested here. CPU previews show the actual exported meshes and textures.
The clock is positioned above the furniture only for the collection preview;
its standalone mesh is centred at its local origin.

Native material files are table-64.png, stool-32.png, clock-32.png, glass-16.png.
Large -edit.png and -guide.png files are UV painting/inspection guides, not
engine textures. Gutters have deterministic nearest chart-edge colour padding.
UV boundaries use half-texel insets. Broad material variation is painted with
ImageGen; no 3D object rendering is used in the UV atlases.

Python dependencies: NumPy and Pillow.
python3 build_props.py rebuilds the meshes, preserving the existing PNGs.
To repaint, supply --table-texture, --stool-texture, --clock-texture and
--glass-texture with new source paintings; resizing and padding are automatic.
python3 build_preview.py embeds current exports in the HTML.
python3 render_preview.py renders the scene and individual inspection views.
python3 validate_assets.py verifies mesh, normals, winding, UVs, edge padding,
native resolutions, GLB structure and embedded image bytes.

texture-prompts.json records the four ImageGen edit prompts.
asset-generation-prompt.txt records the reinforced modelling/UV rules.
validation.json records checks on the four final exports.
