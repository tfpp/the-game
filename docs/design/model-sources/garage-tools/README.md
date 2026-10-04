# Operations workshop equipment

Original native indexed equipment kit, metres, Y up, front +Z, floor-centred
pivots. `build.gd` owns seven meshes: workbench 952 triangles, tool chest 268,
compressor 396, wheel rack 504, floor jack 212, mechanic's creeper 148 and floor
bay markings 48; total 2,528. One shared material and existing approved 128px
`workshop_lift.png` atlas. No new texture, animation, interactions or simulated
workshop mechanics. Fixed furnishings stream with the existing room.

The workbench has a continuous steel top and welded frame, two drawer banks,
a connected backboard, hanging open-ended spanners, screwdrivers, a mounted
vise and socket tray. The chest has drawers, a rubber top, connected handle
and four casters. The compressor has an eight-sided tank, motor, feet, wheels,
handle and connected octagonal rubber hose. Tire rings are continuous annular
meshes on a welded rack. The floor jack has a saddle, hydraulic arm, attached
handle and wheels. The creeper has a padded bed/headrest on its caster frame.

Explicit charts mirror the six approved lift regions. `uv-template.png` records
the reused layout; `../workshop-lift/` owns the exact UV paint prompt and retained
ImageGen response. Enamel, steel, charcoal and rubber use matching painted regions.
The existing lift control-button chart is not used for this kit. Repeated forms
share UVs and hidden faces reuse the same regions. Native geometry rebuilding
preserves all approved painting.

```sh
# From repository root, Godot 4.7 after import:
godot --headless --path game -s ../docs/design/model-sources/garage-tools/build.gd
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- \
  /tmp/workshop-lift-review
```

Review actual garage overview, bench, wall equipment and compressor in Godot
Compatibility. See `docs/design/previews/workshop-lift/`. Placement removes the
old crate/barrel and moves the service cabinet to a wall storage position; it
preserves the mezzanine, planning boards, spawn square, walking exit, van controls
and route-map approach. Floor paint is decorative mesh, not structural geometry;
existing GridMaps continue owning room floors, walls, stairs and mezzanine.
`test_layout.gd` checks service standing areas and the controls-to-bench route,
indexed winding/normals/UVs, triangle budget and the shared texture limit.
