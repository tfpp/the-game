# Two-post workshop lift

Original native model, metres, Y up, +Z faces the bonnet. Floor-centred pivot;
carriages and all four arms share a vertical translation. Four rubber pads at
x ±0.64, z ±1.25 have tops at y 0.36, exactly contacting the van ladder rails.
The maximum 1.95m rise leaves pedestrian clearance beneath the chassis and keeps
the roof below the cross tie and garage ceiling. Post centres x ±1.9, z −0.7.

`build.gd` owns both indexed meshes: 168 triangles in the stationary posts and
168 in the moving arms, 336 total. One shared rough material, nearest mipmaps,
128×128 atlas, six padded reusable charts. Broad enamel, arm steel, charcoal
hardware, control buttons, rubber guides and hazard stripes receive separate UV
regions. Hidden surfaces reuse those regions. Geometry uses continuous joined
arms and carriages; no physics solver or new per-wheel simulation is added.

The exact exported `uv-template.png` was painted with ImageGen using the retained
`paint-prompt.txt`; `paint-source.png` is the original larger response. The native
builder downsamples to 128px and extrudes each chart edge into 2px gutters. No
ordinary geometry rebuild repaints the texture.

```sh
# From repository root, using Godot 4.7 after import:
godot --headless --path game -s ../docs/design/model-sources/workshop-lift/build.gd
# Explicit texture rebuild from retained source:
godot --headless --path game -s ../docs/design/model-sources/workshop-lift/build.gd -- \
  "$PWD/docs/design/model-sources/workshop-lift/paint-source.png"
# Native rendered garage review, requires an X display:
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture.tscn -- \
  /tmp/workshop-lift-review
```

Rendered raised, oblique front and rear underbody views were reviewed in the actual
operations garage lighting. The pads meet the chassis, axles reach the hubs and the
engine, gearbox, shaft and rear differential meet. See `docs/design/previews/workshop-lift/`.

`workshop_lift.tscn` keeps collision and interaction independent of streamed visuals.
Server-owned target/obstruction state and continuous height use NetworkedInteraction.
Raise/stop/lower are shared; lowering refuses or stops for a player entering the bay.
Travel is blocked until fully lowered and a pending trip locks lift controls. The
operator must stand back outside the bay to lower. Session changes preserve height.
`test_workshop_lift.gd` covers authenticated requests, late join, actual collision
clearance, support contact, descent obstruction and travel interlocks.
