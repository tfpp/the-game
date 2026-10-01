# Crown Hotel

Use **CROWN HOTEL / RECEPTION** on the street district's west sidewalk, beside
world-local `(-35, 0, 14)`. The reception return door leads to the same street.
GPS lists the entrance and each floor. The hotel uses the garage’s physical
elevator cab, sliding doors, sounds and authenticated controls. Call it at a
landing, walk inside, aim at a numbered row on the right-wall panel and press
Use. Ten stops span 0–37.8 m; the elevator physically carries riders. Guest
rooms use the existing shared swinging doors.

Ten floors each contain twenty rooms (101–120 through 1001–1020), for 200 real
walk-in bedrooms. The ground floor has reception, a key cubby, guest register,
bell and lounge. Upper floors have themed lounges and service carts. Ten colour
themes and five authored arrangements vary twins/singles, mirrored wall layouts,
desk positions and matching art. Beds anchor to a wall with adjacent bedside
tables; chairs face desks; reading chairs face coffee tables; luggage sits on
racks. Radios/phones/clocks and plants vary without scattering the core furniture. Furnishings
reuse the existing 1960s–1980s hotel models and individual texture atlases.

The building envelope is 19×72×42 m. Floor decks sit 4.2 m apart; rooms have
3.3 m ceilings. Every floor has thirty actual garage socket joins, connecting
its lobby, ten hall segments and twenty bedrooms. Hall joins use W03; guest
openings use a matching 1.2×2.4 m profile with the same socket API and canonical
shell builder. The guest rooms and window openings fit the matching exterior.
Closed end caps and solid invisible window panes prevent falls.

## Rendering and streaming

Only the occupied floor's baked shell, collision, furniture and street view load.
While riding, the nearby landing preloads before its doors open, then releases
when the cab moves away. The narrow shaft and moving cab remain loaded to preserve
continuous platform collision; floor decks and ceilings leave the shaft hollow.
Dedicated servers do not load floor geometry. Guest doors and authenticated
elevator/portal controls keep stable paths on all peers, preserving state and late
joins. Inactive guest-door and landing-call visuals are hidden. During a
teleport hold, an inactive floor's content is hidden while its collision remains
protected until room assignment catches up.

Each floor has about 353 furnishings combined into roughly 114 sector-sized
MultiMeshes rather than individual prop visuals. Sectors cull at 32 m; room-number
plates at 14 m. Five shadow-free lamps provide contrast with local warm ambient.
Mesh and texture resources are shared, and other storeys unload. Baking avoids
running the structural triangulator or assembling hundreds of props on arrival.

Window views are a cheap baked copy of the actual socket street placement,
including its road/sidewalk geometry and 23 surrounding building instances.
Buildings use simplified meshes and 32×32 versions of their existing generated
atlases, batched by building type. There are no live window viewports, secondary
cameras, searches, lights or collision in this proxy. Its vertical offset keeps
the street at ground level as the player changes floors. Private camera ambient
and a 180 m far plane make the view readable; leaving restores the prior settings.
The exterior reuses the painted hotel-facade atlas on newly UV-mapped architecture.
No runtime texture exceeds 128 px.

## Preview and authoring

```sh
godot --path game res://features/street_hotel/preview.tscn
```

WASD/mouse, Space jump, Esc release, click resume. Call and ride the elevator to visit
all ten floors. Standalone preview uses the same physical cab and controls;
street travel uses the live feature arrangement.

Rebuild baked assets using a real renderer (a headless dummy renderer cannot
serialize freshly populated MultiMesh buffers):

```sh
godot --path game --rendering-method gl_compatibility \
  res://features/street_hotel/tools/build_assets.tscn
```

Capture actual views:

```sh
godot --path game --rendering-method gl_compatibility \
  res://features/street_hotel/tools/capture.tscn -- /absolute/output/folder
```

Tests cover 200 numbered doors, all ten lift stops, exact socket joins, building
containment, deterministic variations, preserved instance buffers, render budgets,
proxy size/no collision, supported clear guest routes, window fall protection,
furniture containment/non-overlap, distinct panel aiming, supported thresholds,
GPS and the street/top-floor/return trip with actual player platform physics.
The real-network probe also checks a late rider and persistent guest doors.

Run the assertions-disabled release regression after import:

```sh
GODOT_RELEASE=/path/to/linux_release.x86_64 \
  bash game/tests/features/street_hotel/release_test.sh
```

This exports an isolated copy of the project and verifies a real player rides to
floor ten, its landing loads, and saved furniture retains distinct positions.
