# The Gilded Lily

A faded 1964 casino. `world/room.tscn` instances `interior.tscn` and
retains the stable `Room/Spawn` path and all five original annex entrances. This
folder intentionally has no `feature.tscn`: the architecture is part of the room,
not a second copy loaded by the feature loader. Architecture and collision are editable CSG; detailed props are reusable glTF meshes.

- Gaming floor: x -15…15, z -12…12, surface y -1.5. Eight independently networked
  slots and the original roulette table. Two 6m-wide, 1:4 ramps connect the floor
  to the continuous promenade at y 0; brass rails mark the remaining edges.
- West petting parlor: x -34…-18, z -21…21. All six frogs, their pond, and the
  penguin; benches, low paddock rails, tiled floor and plastic plants.
- East harbor room: x 18…34, z -21…21. The original ferry travels its full 30m
  route along x 26, from z -15 to 15. Both end landings clear its 9m hull.
  Solid shallow flooring prevents players from falling into the basin.
- Skylights: two glazed openings in the gaming floor's coffered ceiling (x -12…-7 and
  3…8, z -9…9), either side of the chandeliers, show the day skybox set in
  `world/room.tscn`. The glass has collision. The room's lighting ignores the sky
  (fixed ambient color, no sky reflections) so the interior keeps its warm look.
- South lobby: spawn at (0, 1.2, 23); weapons, banana and ball at security,
  all six clothing pickups at coat check. The gun vending machine and its trash
  can stand beside security. Trampolines in the southeast lounge;
  crates, ramp/platform and a shorter surf ramp in southwest recreation.
- North promenade: both gnome trains; the Kaaba remains in its northwest gallery.
  All three coin pickups remain available. Original annex rooms and routes are
  retained, with covered ceilings and matching finishes.

Generated carpet, wallpaper and walnut base-color textures use world-space
triplanar mapping so patterns keep a consistent scale across the architecture.
Physical materials combine micro-normal and roughness textures with separate
metal, enamel and fabric finishes. A local reflection probe gives metal props
indoor reflections and a constant warm ambient fill so night-time startup does
not capture a nearly black room. The outdoor day/night cycle still changes. Textures use mipmaps and lossy import compression for export.

Five original glTF models replace the basic cabinet, stools, benches, planters
and chandeliers. Each model merges parts by material to limit draw calls and
shares the level's finishes through `model_materials.gd`. Existing bench
colliders, passages and machine collision/interaction stay in place. Rebuild:

```sh
blender --background --python game/features/casino_hub/tools/build_models.py
```

Artwork prompts and provenance: `textures/GENERATED_ASSETS.md`. The PNGs are
base-color artwork; micro-normal/roughness detail is procedural, not measured
from real surfaces. `tests/features/casino_hub/polish_probe.tscn` captures the
actual room and verifies reel settling during a win.

`tests/features/casino_hub/test_casino_layout.gd` checks the baked CSG collision:
ramps join both elevations, side doors stay open, the entire ferry hull route has
clearance, landings have floors, and the main rooms have solid ceilings.
