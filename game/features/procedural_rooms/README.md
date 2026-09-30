# Procedural rooms development

This directory contains original developer materials, a socket attachment prototype
and standalone playable examples. `feature.tscn` now adds a shared in-game copy of
the five-floor garage at z=1800. Use the cyan **PROCEDURAL GARAGE** portal inside
the east-side **Teleport Room** (entrance x=34, z=-10), or locate **Teleport Room** in GPS. E / controller
Use / touch Use teleports to B1. Its **RETURN TO CASINO** portal is beside arrival.
The kit uses a fixed seed on every peer; there is no live reroll control, general random
layout solver or automatic map mutation. The proposed complete system is described in
[the plan](../../../docs/design/procedural-rooms.md).

Every proposed room/module owns socket attachments built from shared boundary
profiles. Exact attachment transforms, flush floors/openings, one owned seam and
continuous collision are required. A pairwise join gallery must pass before the
random generator is implemented; see the plan's seamless attachment contract.

## Play the examples

From the repository root:

```sh
godot --path game res://features/procedural_rooms/examples/lab.tscn
```

WASD/mouse to move/look, Space to jump, **E** to open/close a nearby sliding door,
**G** to toggle cyan socket guides, Esc to release the mouse, click to resume.
Press **1** for garage/ramp, **2** for utility/stairs, **3** for pump/sewer and its
sideways room connection, **4** for the separated assembly gallery.
This standalone lab uses the actual game player/controller.
It does not load the casino or provide multiplayer instances.

The examples comprise seven rooms and four connectors with eight physical joins.
Each module has real attachment nodes and builds its shell around the shared 3×3 m
opening profile. The assembler solves mating transforms, removes both caps and
rejects mismatched or occupied sockets. All floors meet at the exact same socket
plane; no extra overlapping seam collider is inserted. Structure is emitted from
inward-facing polygons with a canonical shared vertex pool across modules. Face
edges are subdivided at neighboring boundary vertices, and rendering uses indexed
triangles. Wall boxes, hidden wall backs and undersides are not emitted. Materials
use separate indexed batches with the same vertex positions/IDs; collision uses one
structural triangle mesh. Stairs have visible tread/riser faces with a sloped walking
collider. Door leaves, tanks, crates and other props use simple separate solids.

Garage sets include a car silhouette, column and barrier; utility sets include
electrical cabinets and a service bench; pump sets include octagonal tanks and
pipework; storage sets include crate stacks. All preserve the central movement lane.
Cyan W03 frames mark matching 3×3 m profiles; one sliding door attaches at the join.
Doors use `NetworkedInteraction` for authority/range/cooldown and initial-state
replication. Occupied openings reject closing and reopen if someone enters mid-close.

The gallery deliberately separates garage, door, hall and pump modules to explain
assembly. It is a display, not a connected traversal route; its caps are removed
for inspection. The normal examples retain exact snapped physical connections.
Sewer water and pipes are cosmetic. Animated moving elevators,
general layout solving/backtracking, saving resolved layouts
and chunk streaming remain future work.

Capture actual Godot renders (requires a display; not `--headless`):

```sh
godot --path game res://features/procedural_rooms/tools/capture_examples.tscn -- \
  "$PWD/docs/design/previews/socket-examples"
```

Screenshots: [overview](../../../docs/design/previews/socket-examples/overview.png),
[ramp](../../../docs/design/previews/socket-examples/ramp.png),
[stairs](../../../docs/design/previews/socket-examples/stairs.png),
[sewer](../../../docs/design/previews/socket-examples/sewer.png),
[side attachment](../../../docs/design/previews/socket-examples/side-attachment.png).
Also see the [assembly guide](../../../docs/design/previews/socket-examples/assembly-guide.png),
[garage set](../../../docs/design/previews/socket-examples/garage-set.png),
[utility set](../../../docs/design/previews/socket-examples/utility-set.png),
[pump set](../../../docs/design/previews/socket-examples/pump-set.png), and
[closed](../../../docs/design/previews/socket-examples/door-closed.png)/
[open door](../../../docs/design/previews/socket-examples/door-open.png).
Overview hides roofs to show assembly; first-person captures use complete shells.

Run the focused tests:

```sh
godot --headless --path game -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/procedural_rooms -ginclude_subdirs=false
```

Tests check eight joins, yaw rotations, mismatch/reuse rejection, capsule sweeps at
the centre and edges, floor support, and actual-player ramp/stair traversal both ways.
They also check shared indexed vertices, duplicate faces, edge T-junctions, set-piece
clearance, door collision in both states and closing/range validation. The separate
`tools/probe_door_replication.tscn` accepts `server PORT` or `client PORT` after `--`;
starting the client after the server checks late-join state and rejects client mutation.

Textures: `res://assets/procedural_rooms/dev_textures/`.
Drag `materials/*.tres` onto greybox meshes in Godot. The ten surface materials use
world-space triplanar mapping; the route and elevator signs use normal mesh UVs.
The pack is independent of the existing hotel/room compiler.

Regenerate PNGs, materials and the contact sheet from the repository root:

```sh
godot --headless --path game -s res://features/procedural_rooms/tools/build_dev_textures.gd
godot --headless --path game --import
```

The generator overwrites its own twelve textures/materials and preview.
Import sidecars retain mipmap settings. See the asset README for measurement units.

## Connected garage world

Open `examples/world_level.tscn`, or run:

```sh
godot --path game res://features/procedural_rooms/examples/world_level.tscn
```

Start on B1 facing the elevator cab. Explore the five-floor garage around the
central open shaft. West passages are ramps; east passages are stairs. Both connect
B1 through B5 without teleporting. B5 leads through the sewer to the pump station.
E operates nearby sliding doors or the elevator control. The lift cycles B1 → B5 →
B4 → B3 → B2 → B1, using validated server-to-player floor transfers. This is a
functional prototype lift with instant travel, not an animated moving platform.
The standalone scene remains available. The normal game uses `playable_world.gd`
to build the same kit without spawning a preview player, changing controls or
overriding the casino environment. The portal provides a shared test area;
encounters, loot and private excursion instances remain future integration work.

The scene exposes `layout_seed` and `floor_population` in the Godot inspector.
Population entries are ordered bottom (B5) to top (B1). Create/duplicate a
`ProceduralPopulationRule`, then set:

- `allowed_sets`: garage, storage, utility, pump; omitted/unknown types cannot spawn.
- `weights`: relative chance of each allowed set; zero disables it.
- `density`: chance to fill a valid slot; zero leaves all slots empty.
- `slots`: local centres of permitted 8×8 m set-piece zones.
- `allowed_yaws`: permitted quarter-turn rotations.
- `placement_bounds` and `forbidden_volumes`: permitted region and reserved lanes.

Placement rejects zones outside the bounds, zones touching reserved interiors, and
zones overlapping another set. Default rules protect the atrium, outer walking lanes,
elevator exits, and ramp/stair entrances. Structural geometry and socket transforms
stay fixed. Lower floors favour service/storage/pump sets; upper floors favour cars.
**R** generates another population in the offline preview; identical seeds and rules
reproduce identical plans. R never rebuilds the structural shell. Objects are static
set-piece groups for now; individual object sockets and loot spawning are future work.

Captures are in `docs/design/previews/world-level/`. Recreate them with:

```sh
godot --path game res://features/procedural_rooms/tools/capture_world.tscn -- \
  "$PWD/docs/design/previews/world-level"
```

The existing `ElevatorCab` owns timed, fixed-size casino cabs with older specialized
networking and CSG geometry. This prototype uses the existing `NetworkedInteraction`
and `Player.server_teleport` services for validated transport, with a 3 m indexed
cab shell matching the new kit. It does not duplicate shared movement or account
state. The elevator transport itself has no new replicated state; sliding doors
retain their tested replicated open state.

Compare `world-level/garage-seed-a.png` and `garage-seed-b.png`: the same deck and
walking lanes contain different seeded sets and orientations. The world tests check
all 47 joins, capsule clearance, floor support, the real controller leaving the cab,
and range-validated transfer through all five stops. Population tests check
repeatability, variation, permitted types, density, bounds, overlaps and rotations.

The preview now starts on B1 facing the elevator entrance at the front of the deck.
Follow the large warm-lit ELEVATOR sign, walk into the cab, then press E near the
control panel. The floor uses coarse concrete with subtle measurement lines; a
collidable asphalt plane surrounds the structure. A procedural overcast sky is
visible through the central shaft. The exterior screenshot shows the interior shell
from outside, so its one-sided walls read as a cutaway.

## UV model authoring

See [the model workflow](../../../docs/design/model-workflow.md). The reusable service
cabinet now has explicit UV1 islands and a generated 128×128 albedo, replacing its
primitive developer-textured version in utility sets. Open
`model_tools/preview_model.tscn` to rotate it and toggle checker/painted views.
Model/world textures have a hard 128px maximum; large generation drafts and guides
live under `docs/design/model-sources/`, outside the runtime asset tree.

The [reusable prop kit](props/README.md) adds barrel, crate and car prefabs, including
fitted collision, explicit polygon UVs and 128px generated albedos. Garage, storage
and pump sets now instantiate these scenes. Open `model_tools/preview_props.tscn`
for the actual model gallery and UV checker controls.
