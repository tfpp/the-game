# Room kits

Three hotel kits and a separate service kit:

| Kit | Structure and fittings |
| --- | --- |
| `classic` | Cream wallpaper, walnut panels, rounded columns, brass frames and bowl pendants |
| `modern` | Pale flat walls, dark square corners, slim window frames and flat ceiling panels |
| `deco` | Green walls, stepped brass crowns and door heads, vertical flutes and tiered lights |
| `concrete` | Plain concrete walls/floor/ceiling, steel door leaves and strip lights; no hotel trim |

Each `.tres` definition owns its palette and profile. `pieces.gd` supplies the actual
corner, frame, wall-detail, light and door geometry. Rooms select `"kit": "concrete"`
or another kit; `style.kit` selects the hotel and corridor default. Wall merging stops
at kit boundaries. Concrete thresholds suppress decorative corner pillars.

The directories `classic/`, `modern/`, `deco/` and `concrete/` contain reusable saved
scenes for floor, ceiling, wall, inside corner, outside corner, doorway and window.
Pieces use four-metre walls and floor tiles with a 3.5-metre ceiling; doorway openings
are 1.8 by 2.6 metres. A corner includes its two wall runs and one shared corner piece.
Replace the straight walls at a corner with that corner scene; do not stack them.
Place an interactive SwingDoor in a doorway with its matching `kit_id`.

Each kit also includes `skylight.scn`: a four-metre ceiling tile with a glazed
two-metre opening, matching frame, sky backdrop and live daylight fill. Generated
rooms use `"skylight": true` for an opening sized to the room. Their central pendant
is omitted so it does not hang across the glazing.

Rebuild the saved pieces from their shared source:

```sh
godot --headless --path game -s res://features/room_kits/build.gd
```

This also exports sewer straight, corner, T, cross, end and access modules. All geometry
uses the existing fast mesh/collision builder and live lights. There is no lighting bake.

The hotel district uses all three kits: the original classic hotel, a modern hotel
84 metres east, and an Art Deco hotel 84 metres west. Each has a concrete storage
room, shared sewer door and ladder. The branching sewer joins all three locations.
