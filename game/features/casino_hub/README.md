# The Gilded Lily

A windowless, faded 1964 casino. `world/room.tscn` instances `interior.tscn` and
retains the stable `Room/Spawn` path and all five original annex entrances. This
folder intentionally has no `feature.tscn`: the architecture is part of the room,
not a second copy loaded by the feature loader. All geometry is editable CSG.

- Gaming floor: x -15…15, z -12…12, surface y -1.5. Eight independently networked
  slots and the original roulette table. Two 6m-wide, 1:4 ramps connect the floor
  to the continuous promenade at y 0; brass rails mark the remaining edges.
- West petting parlor: x -34…-18, z -21…21. All six frogs, their pond, and the
  penguin; benches, low paddock rails, tiled floor and plastic plants.
- East harbor room: x 18…34, z -21…21. The original ferry travels its full 30m
  route along x 26, from z -15 to 15. Both end landings clear its 9m hull.
  Solid shallow flooring prevents players from falling into the basin.
- South lobby: spawn at (0, 1.2, 23); weapons, banana and ball at security,
  all six clothing pickups at coat check. The gun vending machine and its trash
  can stand beside security. Trampolines in the southeast lounge;
  crates, ramp/platform and a shorter surf ramp in southwest recreation.
- North promenade: both gnome trains; the Kaaba remains in its northwest gallery.
  All three coin pickups remain available. Original annex rooms and routes are
  retained, with covered ceilings and matching finishes.

Procedural carpet, wallpaper and tile shaders use world coordinates, so patterns
keep a consistent scale across CSG surfaces. Tarnished brass, velvet, ceiling
stains, peeling-paper patches, chandeliers and sconces provide the period decor.
No external image assets or new gameplay/network scripts are required.

`tests/features/casino_hub/test_casino_layout.gd` checks the baked CSG collision:
ramps join both elevations, side doors stay open, the entire ferry hull route has
clearance, landings have floors, and the main rooms have solid ceilings.
