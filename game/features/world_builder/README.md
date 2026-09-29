# Procedural world authoring

Describe rooms and connections in JSON, then bake an ordinary Godot scene with
textured meshes, static collision and named placement markers. The `hotel` theme
uses profiled architectural meshes: eight-sided columns, curved bases and capitals,
mitred mouldings, recessed panel doors, turned handles, window joinery, ceiling
coffers and curved brass light fittings.

There is no `feature.tscn` in this library. Instance the saved result from the feature
that owns the area. The casino-specific asset tools and gnome tunnel script do not
provide the room graph, blueprint validation or architecture compiler needed here.

## Build and inspect

Run from the repository root with Godot 4.7:

```sh
godot --headless --path game --import

# Ready-made hotel example: tall lounge, lower hallway, gallery, doors and windows.
godot --path game res://features/world_builder/preview.tscn -- \
  res://features/world_builder/examples/hotel.scn

# Rebuild after editing its JSON blueprint.
godot --headless --path game -s res://features/world_builder/build.gd -- \
  res://features/world_builder/examples/hotel.json \
  res://features/world_builder/examples/hotel.scn --force
```

Hold right mouse to look, WASD to fly, Q/E to descend/ascend, Shift for speed.
Escape releases the pointer. The preview includes the existing Kenney clouded daylight sky
through the clear window glazing. Change `sky_panorama` and `sky_rotation_degrees`
on the preview root in the Godot inspector to choose another view. Generated room
modules inherit the environment of their parent world, including the main game’s
day/night sky; they do not add a competing `WorldEnvironment`.

Open the saved scene in Godot to inspect mesh surfaces
and collision. `examples/annex.json` and `annex.tscn` retain the simpler prototype
material theme for testing raw layout.

Output can be an absolute path or `res://` path. `.tscn` is text; `.scn` uses compressed
binary storage, recommended for detailed geometry. Replacing existing files requires `--force`; unchanged cached bakes can be reused without it.
The destination directory must exist. Invalid input exits with status 1 before
building or changing the output.

## Compile baked lighting

For static lighting, include `--bake` in the same build command. Godot is the only
required authoring tool:

```sh
godot --headless --path game -s res://features/world_builder/build.gd -- \
  res://features/hotel_annex/hotel.json \
  res://features/hotel_annex/hotel.scn --bake --force
```

The command generates geometry and UV2 atlases, starts an isolated Godot editor
worker, runs native `LightmapGI`, and saves the finished scene after validating
and importing the lightmaps. Output must be a `res://` path ending in `.scn`.
Keep the scene and its adjacent `<scene>_lightmaps/` directory in version control,
including `.lmbake`, `.exr`, `.exr.import` and the `bake.json` cache receipt. Ordinary game builds and exports
use these saved assets; they do not run a bake or need a graphics device.
Without `--bake`, generation produces geometry and real-time lamps for quick iteration.

The compiler hashes the compiled layout, generator/baker code, materials, textures,
import settings and Godot version. If these match the receipt and every saved output
still matches its recorded hash, it skips geometry generation, imports and baking.
The cache also works on workers without graphics support. Missing or edited outputs
invalidate the receipt. `--force` allows replacement but still uses a valid cache;
add `--rebake` alongside `--bake --force` to force a fresh lighting pass.

Baking requires a graphics-capable Godot editor installation. The command's parent
process is headless, but its temporary editor worker uses the Mobile renderer and
an available GPU. Linux workers need a working graphical session (`DISPLAY` or
`WAYLAND_DISPLAY`). A remote build machine can run the same command with this setup;
a browser or a dummy-renderer headless server cannot perform the native bake.
This adapter is verified with Godot 4.7.2 and invokes its editor **Bake Lightmaps**
action because baking is not exposed as a GDScript method. It reports a failure if
that action is unavailable. Worker failures retain the previous scene and print
the temporary project/log location. Successful builds remove temporary files and
replace obsolete generated lightmaps.

The pass uses high quality, three bounces, 2× supersampling and soft lamp sources.
Walls use 16 cm lighting texels; columns use 2.5 cm texels. Native HDR lightmap arrays
are stored uncompressed for Compatibility/WebGL use. Surface textures retain their
128×128 nearest-filtered appearance. Godot also saves light probes for dynamic objects.

Static lamps are removed from the runtime scene. Its shader uses Godot's UV2 lighting,
allows moving flashlights to add illumination, and ignores the outdoor directional
sun. The visible sky follows the game's day/night cycle; its contribution to interior
lighting is fixed by the bake. Recompile after changing geometry or lamps.

See Godot's [LightmapGI documentation](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_lightmap_gi.html).

## Blueprint

```json
{
  "version": 1,
  "seed": 42,
  "cell_size": 1.0,
  "height": 4.8,
  "hall_height": 3.6,
  "hall_width": 5,
  "ceiling": true,
  "style": {
    "theme": "hotel",
    "panel_spacing": 2.8,
    "wainscot_height": 1.1,
    "pillar_width": 0.4,
    "pillar_depth": 0.2,
    "trim_depth": 0.12,
    "windows": false,
    "lights": true
  },
  "rooms": [
    {
      "id": "Lounge",
      "size": [12, 10],
      "height": 5.2,
      "at": [0, 0],
      "pillars": [[2, 2], [10, 2]],
      "openings": [
        {"id": "TallWindow", "kind": "window", "side": "west",
         "offset": 2, "width": 1.5, "height": 2.9, "sill": 1.3},
        {"id": "GardenDoor", "kind": "door", "side": "north",
         "offset": 8, "width": 1.5, "height": 2.7, "open": true}
      ]
    },
    {"id": "Gallery", "size": [10, 8], "at": [0, 26], "height": 4.2}
  ],
  "connections": [["Lounge", "Gallery"]]
}
```

### Layout and heights

- `version: 1` and `rooms` are required. Seed defaults to 1, cell size to 1 metre,
  default height to 3.5 metres, hallway width to 3 cells, ceilings to true.
- Room `size` and `at` are integer **cells** on the X/Z plane. Floor elevation is Y=0.
  Cell size is 0.75–8 metres. Rooms have 7–32 cells per axis, with 1–64 rooms total.
- `height`, room `height`, and `hall_height` are **metres**, each 2.5–8. Room and hallway
  heights inherit the global height unless overridden. Ceilings and wall profiles
  follow those heights; vertical infill closes the step above a lower passage.
- Omit `at` on all rooms for automatic placement in separated 48-cell slots with
  seeded offsets. Provide it on every room for precise placement, with coordinates
  between -256 and 256. Rooms cannot overlap or touch before halls are carved.
- Room IDs are unique identifiers starting with a letter, then letters, numbers or
  underscores; maximum 48 characters.
- Omit `connections` to link consecutive rooms. An explicit list supports up to 128
  undirected links. Every room must be reachable. Links carve straight or seeded
  L-shaped corridors between centers; crossings become junctions. A route may pass
  through another room. Hallway width is 3, 5 or 7 cells.
- `ceiling: false` omits roofs, ceiling coffers and hanging lights.
- Identical input and compiler/engine version produce identical geometry. Godot may
  assign different internal scene IDs when saving. Keep blueprints and baked scenes
  together in version control.

### Architectural settings

The default theme is `hotel`. `prototype` retains the simple textured shell and
rejects pillars/openings, which require the hotel's joinery generator.

| Setting | Default | Range / behaviour |
| --- | --- | --- |
| `panel_spacing` | 2.4 m | 1.5–6; controls wall bays and engaged columns |
| `wainscot_height` | 1.1 m | 0.5–1.5; timber panels and chair rail |
| `pillar_width` | 0.34 m | 0.2–0.6; wall column diameter; freestanding shafts use 1.5× |
| `pillar_depth` | 0.20 m | 0.1–0.3; projection of engaged columns |
| `trim_depth` | 0.12 m | 0.04–0.2; scales cornice profiles |
| `windows` | false | Automatically space windows along exposed room and hallway walls |
| `window_spacing` | 3 m | 2–8; increased when necessary to fit frames |
| `window_width` | 1.3 m | 0.6–3 |
| `window_height` | 2.2 m | 0.6–5; automatic windows shorten to fit a low ceiling |
| `window_sill` | 1.25 m | 0.5–2 |
| `lights` | true | Procedural sconces/pendants and up to 48 authoring lights; baked scenes remove them |

All these dimensions are metres. Automatic wall columns and panels avoid opening
frames. Free columns use room `pillars: [[x,z], ...]`, measured in metres from that
room's `at` origin. Up to 16 columns per room; placement must leave clearance to
walls, other columns and the center routes connecting rooms.

### Doors and windows

Each room accepts up to 32 `openings`. `id`, `kind`, `side` and `offset` are required.

- Sides: `west` / `east` are the room's minimum/maximum X; `north` / `south` its
  minimum/maximum Z. Offsets always increase from the minimum coordinate along that
  wall, regardless of which way the wall faces.
- `offset`, `width`, `height`, `sill` are metres. Offset locates the opening's first
  edge, not its center. Defaults are width 1.4, height 2.2, window sill 1.2.
- Door sills are zero. Doors require at least 1 m width and 2.1 m height. `open: true`
  bakes the hinged leaf at 90 degrees **outside** the room; false (the default) bakes
  a closed leaf. Leaves include bevels, four recessed panels, hinges and brass knobs.
- Window holes contain fixed glazing, a moulded surround, reveals, sill and mullions.
  Glass is translucent and collides with players. An exterior view depends on the
  surrounding world; the tool does not paint a landscape on the glass.
- Openings must leave 0.35 m at room corners and below the ceiling. Frame overlap,
  unknown fields, duplicate IDs and openings placed across hallway joins are rejected.
  Automatic windows avoid authored openings and shorten to fit available height.
- Door state is an authoring setting. Runtime use/locking/replication belongs to the
  owning gameplay feature. An open exterior doorway needs a floor/destination in that
  feature before players use it.

## Meshes and integration

`profiles.gd` sweeps cross sections and joins mitred edge loops, revolves curved
eight-sided column profiles, and sweeps tubes along curved light arms. `joinery.gd`
builds door stiles/rails around recessed fields and turns the hardware. These are
actual vertex surfaces in `ArrayMesh` resources; the saved architecture contains no
CSG, BoxMesh decoration or generator scripts. Rugs and glass use flat surfaces.

Visual detail is grouped by material and spatial sector. Broad floor/ceiling tiles
merge. Structure uses triangle collision; columns and doors have conservative
simple colliders to keep fine mouldings from snagging movement. Decorative cornices,
light fittings and panel beads do not collide. Four 128×128 texture maps use nearest
mipmap sampling. The two-room hotel example has about 72,000 triangles, below the
80,000-triangle regression budget. Large layouts still need target-device profiling.

1. Store the blueprint and generated scene in the feature that owns the area.
2. Instance the baked scene below that feature's `feature.tscn` and position its root.
3. Place gameplay content relative to `Rooms/Lounge` etc. Room markers sit at floor
   level and carry `floor_rect` (cells) and `height` (metres) metadata.
4. `Openings/Lounge_GardenDoor` etc. identify authored openings; their local forward
   direction faces into the room. Automated windows have `AutoWindowN` names.
5. Keep gameplay nodes in the parent scene so rebuilding does not overwrite them.

Baked structural colliders carry the persistent `radar_geometry` group. The desktop
radar reads their floor and wall triangles automatically, including halls and
openings, with the placed scene's transform. Rebuild older scenes to enable this.

For a playable example, `features/hotel_annex/` connects its saved hotel to the
casino through shared streamed rooms and teleport doors. Its geometry loads only
for visiting players; interaction endpoints stay present on every peer.

Every peer uses the same baked scene, including late joiners. There is no random
runtime generation. The tool currently builds flat, axis-aligned, single-storey
interiors. It does not place around existing world obstacles, generate stairs,
furniture, navigation meshes or interactive door scripts. Outer walls are interior
shells; compose a separate facade if the building will be seen from outside.

## Verification

```sh
godot --headless --path game -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/world_builder -ginclude_subdirs=false
harness/verify.sh
```

Tests cover repeatability, input validation, room/hall ceiling heights, wall step
closure, hole and fixed-glass collision, open/closed doors, column collision and
clearance, small rooms, automatic windows, save/reload, texture size, profiled mesh
normals and geometry budgets. Preview captures should include the room, hallway,
door joinery and column profiles after changes.

Pillars use eight sides around the shaft, base and capital; wall columns use four
exposed sides. Sconces and pendants also use at most eight sides around each fitting.
Their vertical profiles and curved arms remain modelled geometry.
