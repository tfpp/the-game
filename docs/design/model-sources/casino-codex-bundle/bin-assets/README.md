# Casino bin prop study

Two realistic late-1960s to 1980s waste containers with economical PSX / GoldSrc-style geometry. Painted material detail supplies the fine surface features.

## Assets

The open brass wastepaper bin has 60 triangles, an eight-sided tapered body, real inner walls and floor, and a narrow top rim. It is 0.30 m wide and 0.38 m high, with a realistic aged brass texture at 128 x 128 pixels.

The galvanised rubbish bin has 160 triangles, an eight-sided tapered body, a closed lid, two thin bent-wire side handles and a low arched stamped-metal lid handle. It is approximately 0.55 m across the lid (0.584 m including handles) and 0.682 m high. Its realistic zinc mottling, wear, pressed ribs and lid grooves are painted into a 256 x 256 texture rather than modelled as fine geometry.

Both assets have one mesh, one primitive and one material, with an embedded texture in GLB. Cylindrical walls use smooth normals; caps use flat normals; handle sweeps have continuous shading. Units are metres; Y is up. The small offsets above Y=0 are part of the mesh bounds; adjust placement to your floor if needed.

The main wall charts are approximately 127 to 155 pixels per metre around the circumference and 126 to 149 pixels per metre vertically. This keeps the smaller and larger props in a similar density range while scaling the overall atlas size with the model.

## Deliverables

`bin-props-preview.html` is a self-contained offline WebGL viewer. Drag to orbit, scroll to zoom, select either model, toggle wireframe, inspect both atlases or UV guides, and download GLB models or texture PNGs.

Each prop is also supplied as OBJ with a matching MTL and PNG. GLB and OBJ are interchange models, not compiled engine-native GoldSrc MDL files.

The texture PNG names include their final resolutions. The `-uv.png` files are flat UV templates at those same sizes. Higher-resolution `-guide.png` files are annotated reference images, not material textures.

`bin-props-render.png` and `bin-qa-views.png` show the actual meshes with their final textures. `imagegen-prompts.txt` records the exact prompts used with the built-in ImageGen tool.

## Painting workflow

The mesh and UV coordinates were computed in code. ImageGen edited exported flat UV templates, with explicit fixed-layout and no-perspective instructions. Unused atlas margins and gutters are filled with neighbouring material edge colours. The painted images were downsampled to their final 128 x 128 and 256 x 256 sizes and embedded in the models.

Nearest-neighbour filtering is specified in GLB and used in the viewer. UV padding reduces dark edge contamination; arbitrary coarse mipmap levels can still blend separate material regions. Use filtering appropriate to your target game.

## Rebuild

Python 3, NumPy and Pillow are required:

```sh
python build_bins.py
python build_bins.py --brass-texture /path/brass-atlas.png --steel-texture /path/steel-atlas.png
python build_preview.py
python render_preview.py
```

Rebuilding without supplied paintings reuses existing final texture files. If a final texture is absent, the generator uses a flat UV template as a temporary placeholder.

## Verification

Checks cover triangle budgets, finite coordinates, UV bounds, unit normals, nondegenerate triangles, winding, index bounds, binary glTF structure, embedded image bytes and texture dimensions. Front, rear and open-interior rendered views were inspected. Viewer JavaScript passed a syntax check; browser interaction was not run in this environment.

## Handle revision and construction rule

The rubbish bin retains its 160-triangle budget. Side handles are continuous swept bail loops with folded metal mounting tabs seated against the octagonal wall; the lid handle is one arched strap. The body and lid lip connect through an underside annulus, closing the shell. Block-shaped handle assemblies were removed. `asset-generation-prompt.txt` is the updated reusable workflow; its mesh construction section makes physically convincing and visually seamless joins a hard requirement.

## Close-up handle check

Side handles were revised to give the loops fuller curved outlines and physically visible folded mounts. This revision adds 40 triangles, bringing the rubbish bin to 160. The brass bin stays at 60. `side-handle-closeup.png` shows the revised mount and loop in a face-on close-up; material textures remain unchanged.
