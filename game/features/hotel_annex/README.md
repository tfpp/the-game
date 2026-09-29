# Hotel wing

Use the **HOTEL WING** door in the casino's south lobby (between the lounge and
parking garage entrances). Inside, use the **CASINO** door to return. These use
the normal Use control: E, controller B/Circle, or the mobile Use button.

The hotel is a separate area at `(0, 0, -1400)`. The lobby entrance is always
present; the hotel mesh, collision and lightmaps stream in only for its visitor.
Doors and arrival markers remain present on every peer, using the shared
`RoomDoor` server range validation and owner teleport. Entry loads collision
before sending the request. The hotel inherits the game's sky/day-night cycle.

The wing is a four-storey hotel (`atrium_hotel.gd`) around a 20 × 20 m central
atrium with a fountain and a glass skylight. Galleries with brass railings ring the
atrium on every upper floor. Switchback ramps along the south wall (x -4 to 4)
climb one storey each. The west and east wings hold three rooms per floor: the ground
floor keeps the old lounge names (Reading Room, West Salon, Gallery, Grand Lounge,
Conservatory, East Salon) and upper floors have numbered guest rooms with beds.
Storeys are 4 m apart, so floors sit at y = 0, 4, 8 and 12 and the roof is at 16.

## Authoring

The building is made of boxes built when the streamed room loads, the same way on
every peer, so there is no bake step. Edit the constants at the top of
`atrium_hotel.gd` (footprint, atrium, ramp lanes, wing walls) and keep the casino
door at x = 8.75 on the north wall (z = 0) aligned with `Return` and `Arrival` in
`feature.tscn`. Lighting is twelve shadowless omni lights (atrium and both wings on
each floor), loaded only for visitors. Structural colliders join `radar_geometry` so
the radar draws every floor.

To rebuild the casino-side entrance mesh, run from the repository root:

```sh
godot --headless --path game -s res://features/hotel_annex/tools/build_entrance.gd
```

The entrance is a baked mesh with recessed panels, turned brass hardware and
mitred limestone trim. Hidden `RoomDoor` CSG nodes only supply interaction/RPC
endpoints; the visible doorway and its collision come from the baked mesh.

Validation: GUT `test_hotel_annex.gd`; run `python3 game/tests/features/hotel_annex/network_test.py`
for a real server, visiting client and late-joining observer. Run
`godot --path game res://tests/features/hotel_annex/probe.tscn` for full-game
arrival clearance, round-trip and screenshots in `/tmp/hotel-*.png`.
