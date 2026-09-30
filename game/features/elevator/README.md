# Elevator

The Golden Crown's main way down to the fighting: a painted service elevator built
into the south lobby wall, just west of the main south exit (`CasinoCab`, world
x -9.7, z 32.3, doors facing north toward the gaming floor and spawn). Its partner
(`GarageZone/GarageCab`) is set into the front wall of garage **B1** in the
procedural basement garage (`features/procedural_rooms`), beside the arrival point.
GPS lists it as **Garage Elevator**.

Neither cab moves. Both are the same `elevator_cab.tscn`, each pointed at the other
through its `destination` export. Pressing Use near either cab (E, controller Use,
touch Use) opens that cab's doors; after a short boarding window the doors close with
a ding, and everyone standing inside is teleported into the other cab at the same
time — in the exact same position and facing relative to the cab, however the two
cabs are rotated — whose doors then open to reveal them. Pitch is untouched, so the
view carries straight across. `elevator_cab.gd` runs the server-authoritative
door/boarding state machine (`net_state` is the only replicated property, so late
joiners see the current door state); `elevator_math.gd` is the pure position and
timing math.

The cab reuses the procedural rooms' painted models: `elevator_cab_model.tscn` for
the interior, `elevator_door_model.tscn` for the frame and sliding leaves and
`elevator_button_model.tscn` for the call plate. A CSG wall block (`Shell`) around
it supplies collision and hides the leaves as they slide into the wall; its finish
(`shell_material`), height (`shell_height`) and brass sign (`sign_text`) are set per
instance — casino wallpaper to the 8 m ceiling upstairs, weathered garage wall under
B1's 3.5 m ceiling below.

`GarageZone` is a `RenderZone` (`features/room_visibility`) on the garage's layer 20
with the garage's own transform, so the B1 cab is drawn with the rest of the garage
and hidden from the casino. The physical service lift at the casino's east doorway
and the dev-room garage teleporter still work as before.

Tests in `tests/features/elevator/`: boarding/departure and relative transfer
(`test_elevator_cab.gd`), the math (`test_elevator_math.gd`) and placement against
the real casino and garage collision, doorway blocking and the render zone
(`test_elevator_placement.gd`).
