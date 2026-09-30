# Parking garage

The playable P1–P3 structure is now `garage.tscn`, instanced at the unchanged
`Garage` path and world origin by `feature.tscn`; it has no casino entrance
anymore. The garage root is a `RenderZone` on reserved visual layer 19.
Only its scene and in-zone players/enemies/effects are rendered while the local
camera is inside, and it is excluded outside. Geometry, searchable boots,
collision and networking remain present on all peers; this is render isolation,
not a separate game session or memory streaming. See
[room visibility](../room_visibility/README.md) for the camera-mask contract.
The newer B1–B5 garage has its own scene under `features/procedural_rooms/`.


A dark, three-story concrete parking structure outside The Golden Crown. The
casino no longer has a door into it: the old staff-door teleport was removed
(issue #317) and the scene is kept only until its cleanup (see
`docs/code-cleanup.md`). `Garage` sits at world `(0, 0, 600)`, far from the rest
of the map. The door just inside P1 returns you to the Golden Crown at
`slum_runs/CasinoArrival`, like the alley.

Each of the three levels (P1–P3) shares the same 36×28m footprint — columns,
abandoned cars and low ceilings break every floor into short sightlines
instead of one open room — but differs in density and decay:

- **P1** (ground): the most cars, some flooding and puddles, mostly working
  lights with a couple of struggling fixtures.
- **P2**: the densest parking and the worst lighting — several dead or
  flickering tubes, built for close-range ambushes.
- **P3** (top): fewer cars, more dead fixtures, the darkest floor.

Two switchback vehicle ramps (P1→P2 along the east end, P2→P3 along the
west end) and an enclosed stairwell in the northwest corner — real stacked
steps, not another ramp — both connect all three levels, so there's always
more than one way up or across. The south face of every floor is open above
a low parapet, framed by a block of dark high-rises outside; that's the only
"outside" glimpse, since a lit sky would leak through anywhere else.

`fluorescent_light.gd` drives each ceiling fixture's failure state (steady,
flickering, struggling, or dead) and its tube hum entirely client-side, the
same way `elevator_cab.gd` animates its doors locally — it's cosmetic, so it
never needs replicated state. `garage_door.gd` is a stripped-down version of
the elevator's teleport, minus the cab and boarding wait: press Use and the
server immediately validates range and moves you to the paired door's
arrival marker. `procedural_audio.gd` synthesizes every ambient sound
(rain-and-wind bed, tube hum, drips, structural creaks) at runtime as raw
PCM, so the feature ships with no new audio assets.

`tests/features/parking_garage/` covers the return door (like
`test_elevator_cab.gd`), the fixture failure states, the synthesized audio
buffers, and the baked collision — floors, both ramps' slopes, and both
stair flights — the same way `test_casino_layout.gd` checks the casino.

`Garage/GarageArrival` carries `features/dev_elevator/slum_arrival_point.gd`,
which registers it for the Golden Crown's shared slum gate.

Nine of the wrecked cars carry a `features/loot/` `LootContainer` named `Loot`
using `car_loot.tres`: walk up and press Use to open the boot and search its
shared stash. Drag valuables into an empty backpack slot or tap to take one.

The checked-in wreck meshes include an outward-facing body, detachable hood,
opening boot lid, cavity and trim. They replace the old box-car CSG shape; a single static
collision shape still blocks players. Each placed car keeps its own paint
color, and damaged variants expose a missing hood.

Hostile enemies live in `features/garage_enemies/`: lurkers on P1, gunmen from
P2 and fast stalkers on P3, getting more dangerous with every floor you climb.
