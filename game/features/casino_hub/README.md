# The Golden Crown

## Casino cleanup (#487)

The old comparison casino is no longer loaded: its north-promenade entrance,
remote room, duplicate gambling machines and GPS destination have been removed.
Shared legacy scenes below remain authoring/test references, not live content.
Main-casino overhead signs for the dev booth, operations garage, street casino,
slum gate, mall and service door are gone. The doors keep their existing Use
prompts, positions, validated travel and GPS routes; remote return signs, gaming
displays and decorative artwork are unchanged. Inherited modeled signs are hidden
only on those casino entrance instances, leaving the shared door prefab intact.

The active game uses the saved [casino GridMap](gridmap/README.md), with a **1.25 m**
deep gaming pit, quarter-height retaining walls and six-metre ramps to ground level.
The geometry below describes the retained legacy CSG room used for reference.

A faded 1964 casino. `world/room.tscn` instances `interior.tscn` and
retains the stable `Room/Spawn` path and all five original annex entrances. This
folder intentionally has no `feature.tscn`: the architecture is part of the room,
not a second copy loaded by the feature loader. Collision-bearing architecture remains CSG; static decoration is baked into sector meshes and props are reusable low-polygon glTF meshes.

- Gaming floor: x -15…15, z -12…12, surface y -1.5. Eight independently networked
  slots and the original roulette table. Two 6m-wide, 1:4 ramps connect the floor
  to the continuous promenade at y 0; brass rails mark the remaining edges.
- West petting parlor: x -34…-18, z -21…21. All six frogs, their pond, and the
  penguin couple (`features/penguin`); benches, low paddock rails, tiled floor
  and plastic plants.
- East harbor room: x 18…34, z -21…21. The original ferry travels its full 30m
  route along x 26, from z -15 to 15. Both end landings clear its 9m hull.
  Solid shallow flooring prevents players from falling into the basin.
- Salon: green card tables and decorative adult patrons on the west side, eight
  functional slots in an east-side bank, and a bottle-lined bar at the back.
  A ceiling at y 5.72 covers the former atrium skylights. Original side-room
  ceilings and all existing exit paths remain in place.
- Gallery: floor y 3.2, z -12…-8. A 1.8m-wide staircase at x -12.8 climbs from
  the gaming floor; a smooth 21-degree collision ramp follows its visual treads.
  Railings protect the landing and leave the stair entrance open.
- Spawn: (2, 0.2, 5), in the clear central gaming aisle. The stable `Room/Spawn`
  path is unchanged. Weapons, clothing, recreation areas and the south lobby
  remain reachable via the original south ramp.
- Outer walls: the gnome burrows' doggy-door holes (`features/gnomes`); the Kaaba remains in its northwest gallery.
  All three coin pickups remain available. Original annex rooms and routes are
  retained, with covered ceilings and matching finishes.

Generated burgundy carpet, green wallpaper and walnut artwork is imported at
128×128 with nearest mipmap sampling. Shared matte finishes use authored warm vertex illumination and fixed indoor
texture shading, without reflections, normal maps or roughness maps. The salon
remains readable at night without mobile shadow maps. Outdoor day/night lighting still runs.
Texture surfaces use dominant-axis world mapping, restrained dithering and no
affine warp, so textures stay fixed to surfaces as the camera turns. See `../retro_style/README.md` for the mobile rendering budget.

Five original flat-shaded glTF models replace the cabinet, stools, benches,
planters and chandeliers. Each model uses at most two materials: textured walnut
and a textured palette with vertex tints. Geometry budgets (triangles per model):

| Model | Before | PS1 |
| --- | ---: | ---: |
| Slot cabinet | 13,052 | 844 |
| Stool | 3,328 | 336 |
| Bench | 4,760 | 488 |
| Planter | 2,832 | 464 |
| Chandelier | 20,344 | 1,816 |

`tools/interior_source.tscn` is the editable source. The offline bake combines
171 non-colliding decorative CSG nodes into 63 material/sector meshes in
`res://assets/casino_hub/models/decor_batches.scn`. Sectors retain spatial culling. Colliders, lights,
labels, model instances, and all gameplay nodes retain their names and transforms
in the generated `interior.tscn`. No runtime mesh baking is required.

The model and salon scene assets are checked in. Edit those assets directly. After
editing decoration in `tools/interior_source.tscn`, rebuild the batched scene with:

```sh
godot --headless --path game --import
godot --headless --path game --script res://features/casino_hub/tools/bake_decor.gd
```

Artwork prompts and provenance: `res://assets/casino_hub/textures/GENERATED_ASSETS.md`. Original generated
sources are retained; imported textures are tiny and the old PBR maps are removed.
`tests/features/casino_hub/polish_probe.tscn` captures the actual room and verifies
reel settling during a win.

`tests/features/casino_hub/test_casino_layout.gd` checks the baked CSG collision:
ramps join both elevations, side doors stay open, the entire ferry hull route has
clearance, landings have floors, and the main rooms have solid ceilings.

## Operations garage starter point

The main scene retains its original `Room/Spawn` marker as a fallback. The
`crown_spawn` feature supplies the `player_spawn` marker for joins, fall recovery and
combat respawns, in front of the elevator. The operations garage is reached by door. Its walking exit and van route map
reach the casino; the return doorway is on the north promenade at (-7,1.1,-19.7),
clear of the existing street/dev portals. Casino geometry and other entrances are
unchanged. See `../starter_room/README.md`.

## Reference salon assets

`salon.tscn` is checked in; edit it for layout changes. Its original meshes have adult proportions,
formal clothing, posed hands, readable cards and chip stacks. Card tables remain
scenery: they do not advertise blackjack, add players or award money.
Characters use `casino_patrons/stationary_patron.gd` for synchronized gun deaths
and six-second respawns, on the player avatar rig (`casino_patrons/README.md`). Existing slots
and roulette retain their authoritative interactions and payouts.

The modelled table and its three chairs total 6,230 triangles across three shared
materials (felt, walnut, textured palette). The entire bar,
including 68 bottles, is 5,012 triangles/two materials; gallery architecture is
3,576 triangles/two materials. Stationary patrons replicate only alive state and
a transient death effect.

`test_salon_access.gd` sweeps a standing player capsule through the central aisle,
the front of all eight machines, and up/across the gallery in both directions.
It also checks all 49 sampled positions in the six-metre random spawn area.
Marked collision boxes supply the desktop radar with the new layout, while
roof/storey filtering keeps the gallery ceiling off the map.
Texture and model budgets are covered by the retro-style tests. The visual probe
also captures the furnished tables and a view down from the gallery.

### Model and texture authoring

The table uses continuous curved edge loops for its leather rail, dealer cut-out,
undercut walnut apron and pedestal supports. Chairs have bowed upholstered backs,
rounded cushions and shaped legs. Patrons use fitted torso, cheek/jaw/brow, sleeve,
hand and leg loops, with cloth overlays for collars and lapels. Smooth normals are
limited to these curved pieces; geometry stays sparse and imported LODs remain on.

Visible model surfaces should use textures by default. The palette shader now
samples a shared 128px atlas: skin, woven fabric, leather and worn metal in four
64px tiles. UVs are baked at physical scale before material joining; vertex colour
RGB retains the tint and alpha encodes the atlas tile (the shader stays opaque).
Existing wood and felt maps remain separate. Untextured legacy StandardMaterial3D
surfaces receive a shared 128px grain texture through RetroStyle; existing artwork
and its UV mapping are preserved. This adds no materials to the model draw budget.

## Live GridMap casino

The main game now loads `gridmap/playable.tscn`, wrapping `casino_gridmap.tscn`.
It preserves the 30 × 24 m pit at y -1.5, continuous surrounding floor at y 0 and two
six-metre-wide ramps, using the Blockbench wood wall. The bar and stationary NPCs
are restored; slots and roaming NPCs use their existing feature scenes. The
former food court and pawn shop shells use GridMap rooms off the south corridor.
Their shops have since moved: the food counters and booths now occupy the separate
Crown Strip Mall, reached by its unsigned portal in the south corridor, while
the gun/pawn store uses the operations van. Existing shopping/seating behavior is
unchanged; see `features/strip_mall/README.md` and `features/pawn_shop/README.md`. The old
architecture described above remains in `world/room.tscn` for reference. Press F5
to play, or open `gridmap/preview.tscn` for isolated geometry review. See
[the GridMap guide](gridmap/README.md) for editing, tiles, rebuilding and verification.

Three existing guests at the main bar and north/south card tables now smoke ambient
cigarettes; their transforms and hitboxes are unchanged. See
[`casino_patrons/README.md`](../casino_patrons/README.md#ambient-smoking) for animation,
visibility budgets and the opt-in `SalonGuestModel.smoking` flag.

The live casino now uses a separate decor GridMap for the original framed paintings,
brass sconces and chandeliers. Its warm local light pools, darker ambient fill and
light-responsive casino shaders replace the previous fullbright presentation.
Indoor lighting stays fixed across the day/night clock; only the bar and table
accent lights cast shadows. Editing decor fixture cells also moves their lights.
