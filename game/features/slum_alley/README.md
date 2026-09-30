# Rain Alleys

A compact, rain-soaked slum map in an isolated pocket at world z=900. The
crossing streets run between boarded brick blocks and are broken up by four
searchable dumpsters. Puddles, rain streaks, a rain-and-wind bed, and failing
lights make the route back to the Golden Crown visible without making the
whole map safe to cross. A fence and wire ring the playable footprint.

The public Crown gate picks this arrival or the parking garage for each new
shared excursion. The alley return door leads back to the Crown's south lobby.
Its searchable dumpsters use `alley_loot.tres`; their contents reset when the
next excursion begins. `tests/features/slum_runs/` covers travel, shared
destination and loot reset behavior.

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
