# Annex routes

Ten rooms connect to the casino through five entrances. The northwest and west
entrances share a loop; the northeast, east and south wings branch off the hub.

Every standalone CSG floor, wall, ceiling and obstacle has collision enabled.
Each corridor combiner has a Walls child ending with passage subtraction volumes
matching the floor footprints. These remove crossing walls at bends and T junctions
while keeping floors and ceilings intact. The round northwest room also has a clearance cut
where its outer wall otherwise protrudes into the adjoining corridor.

The south corridor's east wall has one more cut, `FoodCourtDoorway` (x 3, z 38…42,
3.2 m high), into the legacy food court wing. This annex is excluded from the
active GridMap casino. Live food counters now occupy `features/strip_mall`, reached
by the south casino FOOD SHOPS portal; the legacy corridor geometry is unchanged.

Keep subtraction volumes after additive geometry in each combiner. New passages
need continuous floors and standing-player clearance in both directions.
`tests/features/annex/test_accessibility.gd` sweeps the full standing capsule
along all routes and checks floor support every half metre. It includes the hub
so the west petting-parlor exit cannot be fenced off again.

## Six little secrets

`easter_eggs.tscn` is static scenery instanced by this annex, not another loaded
feature. Six small wooden joke plaques sit at eye level beneath existing sconces.
Walk close and read them; no Use action, rewards or collection UI is involved.
“Random” means assorted jokes, not positions that change between sessions.

Spoilers / placement (world coordinates, wall face at y=1.55):

| Secret | Location | x, z | Faces |
| --- | --- | --- | --- |
| Employee of the month | Northwest room 1 | -33, -49.5 | +Z |
| Missing texture | Northeast room 3 | 10, -69.5 | +Z |
| Ferry review | East room 5 | 74.5, -10 | -X |
| Emergency frog | East room 6 | 60, -45.5 | +Z |
| Gnome union | West room 9 | -59.5, 32.5 | +X |
| Encoded message | South room 8 | -22.5, 80.5 | -Z |

The backing starts 5mm in front of each wall; lettering sits another 5mm beyond
its face, facing into the room. Labels retain depth testing and are unshaded for
night readability. Six shared BoxMeshes (12 triangles each) and six labels stop
drawing beyond 18m; there are no scripts, colliders, lights, timers, or network
messages. All peers, including late joins and offline play, load the same immutable
scene. There is no player state to persist or clean up on respawn/disconnect.
`test_easter_eggs.gd` checks wall mounting, approach clearance and the static budget.
