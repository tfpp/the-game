# Saved garage level tiles

`static.tscn` is the private garage's structural GridMap. Its MeshLibrary contains
five authored level tiles at four-metre vertical spacing. Each tile preserves
the existing shell triangles, normals, painted triplanar materials and collision.
The open shaft, ramps, stairs, side rooms and pump route retain their footprints.

The native offline baker partitions existing triangles by level and remaps used
vertices without simplifying or replacing geometry. Saved collision retains
backface support. Runtime actors remain outside this static scene: lift/door
controls, vehicle stashes, enemies and seeded supply crates keep stable paths.

Rebuild with project autoloads available:

```sh
godot --headless --path game res://features/zone_instances/garage_gridmap/bake.tscn
```

Private instances skip the procedural shell rebuild and load the saved GridMap.
`test_garage_gridmap.gd` compares collision vertices and render triangle counts
against the authored source, checks floor support and the sky-open shaft, and
ensures no spawners or synchronizers appear in the static scene.

The structural visuals load through `StreamedRoom`; the dedicated server uses
`collision.tscn`, whose MeshLibrary contains shapes without render meshes.
Unloading client content leaves server collision and actor paths intact.
The regression suite checks floor support after visual content unloads.
Actual main-game arrival, return and enemy-distance captures have been reviewed.
The real player controller also climbs and descends all four saved ramps and all
four stairways, checking their endpoint elevations. The saved-map checks pass
four tests / 61 assertions, including collision persistence after visual unload.

Each of B1–B4 also has a two-metre jump/drop opening at z=20–22, alternating west
and east. The matching ceiling is cut below it and the next floor has a solid,
reserved landing: a drop skips exactly one storey. Four-sided slab edges preserve
the half-metre concrete thickness. Seeded set pieces reserve both the opening
and landing, and standing plaques identify the shortcut. These are part of the
saved structural tiles. Actual controller checks jump every gap and drop onto
every landing; normal ramps/stairs and combat-pressure checks remain green.

B1 has no standing water on its aprons; B2–B5 have 2/3/4/5 irregular puddles with
increasing footprints. Each wet floor adds one batched material surface, with a
subdued blue-grey water material. Water has no collision, scripts or added lights,
and the saved server collision remains 4,740 triangles. Close actual main captures
review all five depths. Saved-map checks verify increasing water area, batching
and unchanged physical floor height alongside all route checks (six tests / 108
assertions).
