# R44 five-car model — authoring handoff

The train follows Casino Royale's faceted construction, dull surfaces and coarse
painted detail. It combines an R44-inspired silver exterior, fictional 1980s tags,
a furnished period-inspired passenger cabin and sliding boarding doors.

## Editable sources

- `build.gd`: native indexed mesh/UV builder, shared materials and five-car assembly.
- `cabin.gd`: MeshLibrary/GridMap cabin, seats, pockets, physical leaves and six clips.
- `r44_five_car_set.blend`: editable Blender 5.2.2 snapshot of the final GLB, packed
  images and door actions. Scrub frames 1–30 for the active closing animation.
  Saved at frame 1, doors open. Blender edits do not automatically round-trip into
  the deterministic GDScript builder.
- `uv_template.png`, `interior_uv_template.png`, `checker.png`: exact painting guides.
  Eight stacked charts per material atlas, two-pixel gutters and explicit UV1.
- `painted_atlas_source.png`, `graffiti_source.png`, `interior_source.png`: original
  ImageGen outputs, kept outside runtime assets. Matching `*-prompt.txt` files
  retain the exact prompts. Signage uses the existing repository pixel font.
- `manifest.json`: generated component/UV inventory (combined cabin surfaces and
  repeated GridMap cells are assembled by `cabin.gd`).
- `validate.gd`: vertex/index, area, winding, normal, UV, texture, dimension and
  animation audit for native and round-tripped GLB geometry.
- `preview.gd`: renders the actual GLB, including interior, open and half-open views.

Runtime resources live in `game/assets/metro/` and `game/features/metro/`.
The native scene shares resources and retains collision. Portable GLBs flatten
GridMaps and pack textures/animation. Whole train: 40,322 triangles, six materials,
3.15 × 3.66 × 114.3 m. Four runtime atlases have a maximum dimension of 128px.
Binary texture resources include mipmaps; PNGs retain portable artwork.

## Rebuild and review

From repository root, with Godot 4.7 on PATH:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/r44-metro/build.gd
godot --headless --path game --editor --import
godot --headless --path game -s ../docs/design/model-sources/r44-metro/validate.gd
godot --path game --audio-driver Dummy --rendering-method gl_compatibility \
  -s ../docs/design/model-sources/r44-metro/preview.gd
godot --path game res://features/metro/preview.tscn
```

Normal builds preserve approved runtime metal/interior atlases. For fresh metal,
pass an absolute source PNG after `--`; to repaint the interior, replace its source
and remove the generated runtime interior PNG before rebuilding. Graffiti reuses
its authoring source. `--template` and `--interior-template` emit painting guides.
These mesh-first textures were generated against the exact exported charts.

Renders go to ignored local `docs/design/previews/r44-metro/`. Blender was updated
through the normal glTF import UI with Pack Images enabled. Open and closed
animation poses were visually checked there. The viewport near clip is 0.5 m to
avoid depth flicker when reviewing the full 114 m train.

## References

Exterior: [Michael Hodurski, R44 5408, April 8 2008](https://www.nycsubway.org/perl/show?106567).
Interior: [R44 333 interior, 1973](https://www.nycsubway.org/perl/show?5709).
[Background and dimensions](https://en.wikipedia.org/wiki/R44_%28New_York_City_Subway_car%29)
informed the 75-foot scale and four paired doors per side. References were viewed
for shape only; no photo or third-party model is included. Game visual reference:
`docs/design/concept-art/elevator-parking-garage.png`. Meshes, signage and tags were
created for this asset. The formation and mixed-era appearance are game adaptations.

## Validation

Native and GLB audits agree on 40,322 triangles, six materials and bounds. The GLB
retains six animations, including 80 tracks in `open_all`. All twelve Godot views
were rendered, with the cabin and door poses inspected. Five dedicated GUT tests
cover every entrance open/closed, left/right selection on the reversed car,
continuous floors, aisle clearance, seats and actual animated collision movement
using the game's 0.4064 m radius / 1.8288 m tall player capsule. The existing player
controller also walks through a formerly closed entrance after it opens.

Full repository verification uses `harness/verify.sh`. On macOS the existing
packaging check needs GNU sed on PATH; no repository check scripts were changed.
See the feature README for controls, collision and deferred metro integration.

Final `harness/verify.sh` run passed: format/lint, import, release notes, all 2,226
GUT tests, offline and two-client multiplayer smoke, and both Go services' checks.
An earlier run hit the existing gun-menu chat join-notice timing test; the final
full rerun passed it without changes to that feature.
