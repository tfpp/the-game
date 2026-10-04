# Rain Alleys

A compact, rain-soaked slum map. The authored `alley.tscn` preview sits at z=900;
normal `feature.tscn` contains only its destination registration, so startup does
not load an unused public map. Private copies place the district at their instance
offset through `SlumInstance`. The
crossing streets run between boarded brick blocks and are broken up by four
searchable dumpsters. Puddles, rain streaks, a rain-and-wind bed, and failing
lights make the route back to the Golden Crown visible without making the
whole map safe to cross. A fence and wire ring the playable footprint.

The Crown elevator picks this arrival or the parking garage for each new private
group excursion. Each copy has an arrival/return cab that brings its riders back
to the Crown. Searchable dumpsters use `alley_loot.tres` and reset per instance.
`tests/features/zone_instances/` covers travel and private scene lifetimes.

The developer pad also creates a private copy when the zone service is present,
requires cheats and waits for the owning client to acknowledge readiness. Legacy
shared-map fixtures instantiate `alley.tscn` explicitly. Tests verify registration
contains no geometry/collision and developer transfer cannot enter an unloaded map.

`ground.tscn` paints the original 50-metre floor with 25 ten-metre GridMap tiles.
One cell per octant keeps each baked mesh's local light selection separate in the
Compatibility renderer; a single district-wide floor lost the entrance's light
coverage. Floor height and collision footprint remain unchanged. A steady warm
fixture marks the arrival/return cab. `tests/features/slum_alley/test_ground.gd`
checks the floor footprint, seams, height and baked mesh bounds.

The checked-in low polygon geometry in `res://assets/slum_alley/models/` includes painted dumpsters,
boarded window banks, fire escapes, streetlamp posts and fence wire. The OBJ
files and material palette are editable assets. Dumpsters use a native ArrayMesh
and a fitted box collider, with shared panels, ribbed lids, handles and castors.
Their 128×128 atlas and reusable `dumpster.tscn` use the
[loot model workflow](../../../docs/design/loot-models.md). The four existing
container paths and shared loot behavior remain the same. Other props retain their
existing CSG collision; their meshes are visual only. One combined street mesh keeps
the far district cheap to draw.

The dumpster model has a hollow body and rear-hinged lid. `DumpsterVisual` opens
it in 0.38 seconds while its sibling `Loot` has active searchers, and closes in
0.5 seconds once the final viewer leaves. It eases and reverses smoothly; all peers
read the same server-owned search count. The cover collider remains fixed.

Inspect the live animation (Space starts/stops an actual search request):

```sh
godot --path game res://features/holdables/model_tools/preview_dumpster_search.tscn
```

Pass an output directory after `--` to capture closed/open views and verify closing.
