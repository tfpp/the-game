# Wall sconces

Brass 1960s wall sconces that keep the annex lit at night. The casino floor already has
chandeliers and its own sconces (`casino_hub/interior.tscn`), but the annex corridors
and rooms had no lights and went black once `features/day_night` lowered the ambient
light. `wall_sconces.gd` builds one sconce (brass back plate, glowing shade, warm
`OmniLight3D`) at each entry of `SPOTS`, facing into the room from the wall's inner face.

Cosmetic and per-peer, with no RPCs or replication. The lamps' brightness follows the
same wall-clock day/night factor `DayNight` uses: dim by day, warm and bright at night.
When adding annex rooms, append their wall faces to `SPOTS`.

Tested by `tests/features/wall_sconces/test_wall_sconces.gd`.
