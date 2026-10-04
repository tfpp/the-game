# Operations workshop review

Native Godot 4.7 Compatibility renders of the actual exported meshes, materials,
collision placement and garage lighting. No browser performance claim is made.

```sh
# From repository root, with an X display:
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- \
  /tmp/workshop-lift-review
```

Reviewed and retained locally (PNG files are ignored by repository policy):
`workshop-overview.png`, `workshop-bench.png`, `workshop-equipment.png`,
`workshop-compressor.png`, `workshop-lift-raised.png`,
`workshop-drivetrain-front.png`, `workshop-drivetrain-rear.png`.
The kit has 2,528 triangles across seven indexed meshes; the lift has 336 across
two. They share one approved 128px ImageGen-painted atlas with nearest mipmaps.
The van has 1,416 triangles across five meshes and its two approved 128px atlases.

Inspected the bench/frame joins, vise mount, connected compressor motor/feet/hose,
tire rings/rack supports, tool chest casters, bay placement, lift/chassis pad
contact, and continuous engine/gearbox/shaft/rear differential/hub connections.
Existing stairs/mezzanine, GridMap shell and planning boards remain usable.
Service standing areas, spawn square and walking routes have capsule tests.
Authoring: `docs/design/model-sources/{garage-tools,workshop-lift,armoured-operations-van}/`.
