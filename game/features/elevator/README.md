# Elevator

A real elevator near the trampolines in the casino's south lobby (x 30, z 29),
plus one destination room ("Back Room No. 1") built far from the rest of the
map so it's only reachable by riding the elevator.

Both ends are the same `elevator_cab.tscn`, each pointed at the other through its
`destination` export. Pressing the call button (the Use interaction) on either
side opens that cab's doors; after a short boarding window the doors close with
a ding, and everyone who was standing inside is teleported into the other cab —
in the exact same arrangement relative to each other and the cab, however the
two cabs happen to be rotated — whose doors then open to reveal them. `elevator_cab.gd`
runs the server-authoritative door/boarding state machine; `elevator_math.gd` is the
pure position and timing math, unit-tested in `tests/features/elevator/`.

Only one other room exists in this PR; `BackRoom` is meant as a boilerplate — a
plain floor/walls/ceiling box — for whoever adds the next one.
