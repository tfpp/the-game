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

`tools/build_obj.py` directly authors the low polygon vertex geometry in
`models/`: stamped dumpsters, boarded window banks, fire escapes, streetlamp
posts and fence wire. Run the script with Python 3 after changing the geometry.
The OBJ files and their material palette are checked in, so playing the game
does not need Python or Blender. Existing CSG remains the collision and loot
interaction surface; the meshes are visual only. One combined street mesh keeps
the far district cheap to draw.
