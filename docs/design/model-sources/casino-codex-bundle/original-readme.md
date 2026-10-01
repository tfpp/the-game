# Casino props — Codex handoff

Contains all 15 exported props from this conversation, with the latest cigar thickness and lit-tip revision. No clock animation has been added.

Upload casino-codex-bundle.zip to Codex and ask it to extract the archive, read AGENTS.md and CODEX_PROMPT.txt, then carry out your next request. The prompt is also supplied separately for pasting.

Each batch folder includes GLB, OBJ/MTL, native texture PNGs, mesh data, generation source, exact painting prompts, UV references and an offline HTML preview. Python scripts require NumPy and Pillow. Follow the README in each folder to rebuild; existing textures are reused.

Current rules in CODEX_PROMPT.txt override historical per-batch instructions. Earlier seating uses a shared 256×256 atlas; old bins use 128×128/256×256. These assets are preserved faithfully, rather than silently resized. The old bin handles are historical attempts that should not be copied as approved designs.

| Asset | Triangles | Embedded texture(s) |
|---|---:|---|
| casino-lounge-chair | 116 | 256×256 |
| casino-two-seat-couch | 150 | 256×256 |
| casino-brass-wastepaper-bin | 60 | 128×128 |
| galvanised-rubbish-bin | 160 | 256×256 |
| standing-ashtray-with-cigarette | 104 | 32×32 |
| cigarette | 12 | 32×32 |
| wine-bottle | 44 | 32×32 |
| wine-bucket | 76 | 32×32 |
| walnut-wine-rack-cabinet | 154 | 64×64 |
| walnut-pedestal-cocktail-table | 68 | 64×64 |
| burgundy-pedestal-bar-stool | 134 | 32×32 |
| brass-wall-clock | 48 | 32×32 |
| martini-glass | 68 | 16×16 |
| cigar | 20 | 16×16, 16×16 |
| amber-beer-bottle | 68 | 32×32 |

asset-inventory.json records exact counts, paths, texture dimensions and bounds. file-checksums.json records SHA-256 hashes for the packaged files. High-resolution edit/guide images are reference files, not engine textures.

The HTML viewers are self-contained. Their JavaScript syntax was checked during creation; browser interaction was not tested in this environment. GLB/OBJ assets are interchange files; engine-native GoldSrc compilation is not included.
