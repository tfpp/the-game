# Socket street district

A standalone, walkable street district using the garage's existing
`ProceduralSocketAttachment`, `ProceduralSocketProfile` and canonical
`shell_mesh.gd` builder. No shared socket or garage code is changed.

```sh
godot --path game res://features/street_district/preview.tscn
```

WASD/mouse, Space jump, Esc release, click to resume. The preview uses the real
player controller. `district.tscn` is the reusable layout without a player or
world environment. The live feature adds a streamed district and a two-way
teleporter on the dev room east wall. No enemies or loot are added.

The casino's **STREET CASINO** portal sits against the north wall at
`(7, 1.1, -19.7)`, with its return landing at `(7, 1, -17.8)` on the GridMap floor.

The fixed graph contains nine junctions, twelve street segments, four alleys and
four interior rooms: 29 modules and 36 socket joins. Only the first junction is
positioned directly. Subsequent modules attach through the garage's alignment API;
loop closures check their existing pose before attaching. Roads use 12×3 m opening
profiles to include flush sidewalks; alleys and rooms use the garage's exact W03
3×3 m profile. Unjoined exits retain owned collision caps and fence/barrier/cone
closures. Interior caps remain ordinary walls. Opening a socket removes both cap
presentation and structural collision. One indexed structural collision mesh spans
all joined floors. Pavement is flush for clean traversal.

Twenty-eight building instances surround four city blocks. A corner shop and a
workshop have real 3 m facade openings and fitted wall collision, each containing
a front and back room. All room corners and ceilings stay within their actual
6×14.2 m building envelopes. Other buildings are closed scenery. The central
route through each interior and alley is kept clear of furnishings. Buildings
have no upper-floor access; doors pictured on closed buildings are decorative.

Fifty street prefabs and twelve repeatable surfaces live in `street_props`.
Ten authored building meshes each have a separate 128×128 diffuse atlas. Small
street props use 32/64 px as appropriate; no runtime texture exceeds 128 px.
Ground uses world triplanar mapping; models use explicit padded UV1. Opaque glass
and broad worn paint preserve the CS 1.6 style. Static lighting and the overcast
sky are preview presentation, not new shared gameplay state.

Tests cover graph reachability, exact joins, cap ownership and blocked exits,
standing player clearance and floor support at every join, W03 garage
compatibility, room envelope limits, and actual controller traversal through all
alleys and both buildings in both directions.

Capture renders or export a portable visual GLB (which does not carry sockets or
collision; use the native kit for those):

```sh
godot --path game --rendering-method gl_compatibility \
  res://features/street_district/tools/capture.tscn -- /absolute/output/folder
godot --headless --path game res://features/street_district/tools/export_visual.tscn -- /absolute/output/folder
```

Native mesh rebuilds preserve existing artwork:

```sh
godot --headless --path game -s res://features/street_props/tools/import_props.gd
godot --headless --path game -s res://features/street_district/tools/import_buildings.gd
```

OBJ sources and enlarged UV guides are outside `game/`, under
`docs/design/model-sources/street-props` and `street-buildings`.

Placement convention: imported Blender -Y front becomes Godot +Z. Building
frontages, meters and seating face their approach routes using this axis.
Street lamp arms are authored along +X and rotate separately to overhang the
road. Regression coverage checks lamp and seating directions as well as clearance.

## In-game access

Enter **DEV ROOM** in the casino north promenade, then use **STREET DISTRICT**
on the east wall (E / controller Use / touch Use). The district loads before
travel. Use **RETURN TO DEV ROOM** beside the street arrival to come back.
Press P and search **Street District** for GPS directions to the door.
The static district streams locally; both authenticated portal endpoints and
arrival markers remain present on every peer for multiplayer and late joins.

The east block includes a gold-trimmed **GOLDEN CROWN CASINO** marquee and canopy.
Its entrance teleports to the main casino north promenade. Use **STREET CASINO**
beside the DEV ROOM booth to return directly to this facade.
Six searchable dumpsters sit beside alley mouths and service streets, and six
cars park along the curbs. These reuse the existing loot tables, animated dumpster
lids and searchable car boots. They stay outside streamed geometry so every peer
retains the same interaction paths, rolled contents and active search presence.
The standalone walking preview includes the props; casino travel uses the live game.

The casino marquee is a reusable modeled sign at `props/casino_marquee.tscn`:
raised gold letters, metal panel and frame, 46 low-poly bulbs, alternating
chase lights and a pulsing red accent. It owns one generated 64×64 atlas,
authored after explicit UV geometry. Animation is cosmetic and local.

Socket attachment calls must execute outside `assert()`: Godot release exports
remove assertion expressions, including any function calls inside them. Debug-only
layout checks cannot verify browser placement. After importing the project, run
`GODOT_RELEASE=/path/to/linux_release.x86_64 bash tests/features/street_district/release_test.sh`
from `game/`. This regression runs with assertions disabled and checks all joins,
nine separate junction positions, and floor collision across the district.

## Developer access

Since issue #438 this entrance is a development door: it stays hidden and locked until `sv_cheats 1` (see [dev access](../dev_access/README.md)).
