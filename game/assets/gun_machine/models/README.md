# Double-barrel plasma gun

Original model authored with the Blockbench headless MCP mesh tools for Casino Royale.
`double_barrel_plasma.bbmodel` is the editable source; `double_barrel_plasma.glb`
is the runtime export. The feature scene adds hand and muzzle markers in meters.

## Asset plan and result

- Target: Godot desktop and web Compatibility renderer, including mobile; one
  first-person weapon plus other players' weapons and the machine preview.
- Style: faceted dark armor, exposed twin chambers and recessed violet emitters.
- Balanced geometry budget: under 2,000 triangles. Final source: 44 mesh elements,
  1,520 triangles; exported as one mesh with two material surfaces.
- One embedded 64×64 palette atlas; UVs intentionally collapse into solid swatches.
  There is no patterned texel density to stretch. No normal maps or transparency.
- Opaque rough armor plus unshaded, emissive energy. The energy stays bright in
  Compatibility rendering; a bloom halo requires renderer/environment support.
  The feature scene explicitly preserves emission because GLB export drops it
  from unshaded materials. No dynamic weapon lights are added.
- Rigid weapon: existing skinned player hands reach the two grip markers. No new
  skeleton, firing animation or gameplay balance changes.
- Source units: centimeters, +Y up, -Z forward, primary grip at the origin.
  Keep element transforms unrotated; bake edits into mesh vertices before export.
  Names beginning with `Energy` select the emissive runtime surface.

Re-export after editing the source:

```sh
godot --headless --path game -s res://features/gun_machine/export_plasma.gd
godot --headless --path game --import
```

The exporter uses Godot's native SurfaceTool and GLTFDocument, reverses face winding,
converts centimeters to meters, and combines the static pieces by material. It reads
only this asset, not arbitrary Blockbench models (groups/cube elements aren't supported).

Inspect the runtime model or add `--plasma-hands` to inspect the first-person fit:

```sh
godot --path game res://tests/features/gun_machine/plasma_probe.tscn \
  --resolution 1200x800 -- --plasma-capture=/tmp/plasma.png --plasma-hands
```
