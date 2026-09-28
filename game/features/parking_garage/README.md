# Parking garage

A dark, three-story concrete parking structure outside The Golden Crown. The
casino's south lobby has a plain steel employee door (near the trampolines'
side of the room, at world `(12, 0, 31)`) with a sign reading "STAFF ONLY —
PARKING GARAGE ACCESS". Press **E** to step through; the garage itself is
built far from the rest of the map (`Garage` sits at world `(0, 0, 600)`) so
it's only reachable through that door, the same way `features/elevator/`
keeps its back room isolated. A matching door just inside the garage's P1
level sends you back.

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

`tests/features/parking_garage/` covers the door teleport (like
`test_elevator_cab.gd`), the fixture failure states, the synthesized audio
buffers, and the baked collision — floors, both ramps' slopes, and both
stair flights — the same way `test_casino_layout.gd` checks the casino.

`Garage/GarageArrival` also carries `features/dev_elevator/slum_arrival_point.gd`,
which registers it as a valid landing spot for a randomized slum destination system
(not built yet — see `features/dev_elevator/README.md`). For now the only way to reach
it without walking through the casino is `features/dev_elevator/`'s debug warp pad.

Nine of the wrecked cars carry a `features/loot/` `LootContainer` named `Loot`
using `car_loot.tres`: walk up, press Use to search, and the server rolls
randomized valuables into your inventory.
