# Sewer kit

Six-metre modules with matching connection ports, concrete maintenance floors,
brick walls, drainage below metal grates, pipework and live service lights.
`modules/` contains reusable straight, corner, T-junction, cross-junction, end
and ladder-access scenes. Port markers sit exactly on the six-metre grid boundary.
Open ports have no walls or pipes across the walking route.

`kit.gd.build_network(cells, shafts)` joins an explicit grid of modules. Adjacent
cells open matching ports; absent neighbors receive end walls. The first argument
controls the entire topology; shaft cells get real roof openings and six-metre ladders.
Repeated module shapes share packed meshes. `district_cells()` defines the hotel map:
three hotel access branches, a cross-district trunk, an alternate loop and a service spur.

The three shaft cells are `(-14,0)`, `(0,0)` and `(14,0)`. The district places the
network at hotel-local `(-16,-6,-7)`. Each shaft lines up with a concrete storage floor.
Use a ladder, then move forward/backward to climb up/down. Exiting restores walking.

Rebuild the district sewer and storage fixtures:

```sh
godot --headless --path game -s res://features/hotel_annex/tools/build_service.gd
```

Rebuild the individual reusable modules with `res://features/room_kits/build.gd`.
No lighting bake is required. Automated tests cover network connectivity, loops,
every port's walking clearance, three shafts and multiplayer owner movement.
