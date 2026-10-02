# Uploaded casino prop bundle

Source: user-supplied `casino-codex-bundle.zip`. All 180 supplied file checksums
were verified before integration. The author did not include a separate license;
retain this provenance and do not relabel these files as Kenney/CC0 assets.

This folder preserves the original indexed mesh data, painted PNGs, UV references,
GLB/OBJ/MTL exports, painting prompts and offline HTML viewers. Original root
instructions are retained as `original-agent-notes.txt`, `CODEX_PROMPT.txt` and
`original-readme.md` for reference. They are historical source material, not
repository agent instructions. Follow [the adopted generation standard](../../prop-generation.md).

The original Python build/export/validation scripts are deliberately omitted;
NumPy/Pillow are not project dependencies. The authoritative editable source for
these imported props is each batch's `meshes.json` plus its painted PNGs. Native
rebuilds use Godot's indexed mesh arrays, preserve normals and UVs, and reverse
triangle winding from glTF's CCW to Godot's clockwise front. Original GLBs and the
archived viewers still show the original texture allocation and are not runtime
exports. `file-checksums.json` is the original upload inventory, including omitted
files and the renamed source notes; it is not a checksum list of this directory.

## Rebuild

From the repository root:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s res://features/casino_props/tools/import_bundle.gd
godot --headless --path game --editor --import
```

The importer creates native `.res` meshes, `.tres` materials, collision prefabs
and `bundle_showcase.tscn` in the existing `casino_props` feature. It creates missing
runtime PNGs from the supplied paintings; existing runtime PNGs are reused rather
than overwritten. Delete only a deliberately replaced runtime PNG before a new
painting conversion, then rebuild and inspect it. Source textures remain intact.

The chair/couch atlas and galvanised bin painting are resampled from 256px to 128px
for the repository's hard runtime limit. All other allocations remain unchanged:
16px cigar/glass, 32px small props, 64px cabinet/table and 128px brass bin.
`runtime-manifest.json` records the actual native counts, sizes and source paths.
Imported PNGs use mipmaps; materials use nearest mipmap filtering and clamp edges.
The cigar keeps its 16px isolated emission mask. The clock remains static.

Open `game/features/casino_props/bundle_showcase.tscn` to inspect all 15 prefabs.
The native casino furnishings scene uses selected props in the lounge and bar.
The galvanised bin is retained only in the review kit: the upload marks its
handles as rejected references. Never copy those handles into new designs.

These are static scenery; no new pickup, smoking, drinking, seating or clock
animation mechanics are implied. Reusable colliders describe broad placement
bounds rather than hollow cavities; tabletop decorations disable their colliders
in the placement scene. New placements must preserve door and movement clearance.

Original browser viewers use bundled data with no CDN. Their textures and renders
remain useful source references, but review the imported native models in Godot
before accepting runtime work. Recorded source validation results describe the
upload, not checks performed by this importer or an interactive browser session.

## Integration review

- Verified all 180 original SHA-256 entries before copying the upload.
- Validated all 15 native indexed meshes (1,282 triangles total), clockwise
  winding, finite data, UV bounds, unit normals, native texture sizes and mipmaps.
- Reviewed the [native contact sheet](../../previews/casino-codex-bundle/native-contact-sheet.png),
  [casino lounge](../../previews/casino-codex-bundle/native-lounge.png) and
  [bar](../../previews/casino-codex-bundle/native-bar.png) in Godot's compatibility
  renderer using Mesa software rendering. These captures show runtime materials.
- Checked all ten archived HTML/template scripts with `node --check`. Exercised
  the five finished viewers in Chromium using their self-contained HTML: model
  selection, wireframe, painting toggle, reset, orbit/zoom, atlas dialog and GLB
  downloads. Browser checks use the original source atlases, not the native
  128px conversions.
- Kept NPC routes clear after the casino placement review. Imported objects
  remain static, with no networking or interaction state added.
