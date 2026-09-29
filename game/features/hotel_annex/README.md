# Hotel wing

Use the **HOTEL WING** door in the casino's south lobby (between the lounge and
parking garage entrances). Inside, use the **CASINO** door to return. These use
the normal Use control: E, controller B/Circle, or the mobile Use button.

The hotel is a separate area at `(0, 0, -1400)`. The lobby entrance is always
present; the hotel mesh, collision and lightmaps stream in only for its visitor.
Doors and arrival markers remain present on every peer, using the shared
`RoomDoor` server range validation and owner teleport. Entry loads collision
before sending the request. The hotel inherits the game's sky/day-night cycle.

The wing contains six rooms linked by five corridors: Grand Lounge, Gallery,
West Salon, Reading Room, East Salon and Conservatory. Heights range from 3.4 m
to 6 m, with lower connecting halls, branching routes and authored windows/pillars.
Static soft shadows and bounced light are compiled into UV2 lightmaps. There are
no runtime point lights in the saved wing; player flashlights remain additive.

## Authoring

Edit `hotel.json` to change room sizes, heights, windows, pillars or connections.
Keep the GrandLounge north door at offset 8 aligned with the return trigger and
arrival marker in `feature.tscn`. That closed door is the teleport; the other
closed doors are decorative. Geometry has no runtime generator or network nodes.

From the repository root:

```sh
godot --headless --path game -s res://features/world_builder/build.gd -- \
  res://features/hotel_annex/hotel.json res://features/hotel_annex/hotel.scn --bake --force
godot --headless --path game -s res://features/hotel_annex/tools/build_entrance.gd
```

The entrance is a baked mesh with recessed panels, turned brass hardware and
mitred limestone trim. Hidden `RoomDoor` CSG nodes only supply interaction/RPC
endpoints; the visible doorway and its collision come from the baked mesh.

Validation: GUT `test_hotel_annex.gd`; run `python3 game/tests/features/hotel_annex/network_test.py`
for a real server, visiting client and late-joining observer. Run
`godot --path game res://tests/features/hotel_annex/probe.tscn` for full-game
arrival clearance, round-trip and screenshots in `/tmp/hotel-*.png`.

See the [world builder](../world_builder/README.md#compile-baked-lighting) for bake
requirements and quality settings. The compiler uses native Godot LightmapGI;
Godot is the only required authoring tool.
