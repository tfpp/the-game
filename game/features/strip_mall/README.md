# Crown Strip Mall

The three dedicated food shops now share a small outdoor shopping plaza:
**Poke Bowls**, **İstanbul Kebab** and **Wendy's**, alongside a Polish **Żabka**
convenience-store display. The casino's bars stay put.

From the Crown's south promenade, walk down the south corridor and use the
unsigned door on your left at (1.8, 1.25, 25):
**E / controller B or Circle / touch USE**. GPS lists Strip Mall, Food Court,
İstanbul Kebab, Poke Bowls, Wendy's and Żabka. The return kiosk stands just behind the
arrival point and takes you back to the same casino corridor. No new keys,
prices or orders are added. Alternatively, use the operations garage van and
choose **5 · Strip Mall** for the same arrival and existing driving transition.
The garage computer automatically offers the usual arrival survey for this route.

## Ownership and streaming

This feature owns a distinct shared `StreamedRoom`, its static tiled
architecture/decor, a live frog display and two existing `hotel_portal.gd` endpoints. The server
validates the sender, empty request, range and destination through
`NetworkedInteraction`; `RoomDoor` preloads the destination before an
owner-only teleport. Offline uses that same server path. Simultaneous arrivals
serialize through the inherited half-second door cooldown; retry Use if busy.
There is no mutable shop transaction state. The frog colony uses the existing
server spawner and synchronized movement/alive state; see the habitat notes below.

`food_court` and `kebab_shop` still load independently at their unchanged
network paths. They retain all ordering, wallet, inventory, seated pose and
service replication; they are **not** children of streamed Content. Their roots
are translated by (0,0,-5000), preserving local seating and customer-side
coordinates. Loading/unloading the plaza never duplicates shop state or seats.
Authenticated money/inventory retain their existing lifetimes. Respawns still
start in the Crown; food seating releases when the player moves away.

The former casino food-wing shell is retained empty, avoiding an unrelated
casino rebuild. It no longer contains food vendors or a Food Court GPS endpoint.
The mall is not an excursion/private instance; all visitors share the same shops.

## Layout and gridset

Room origin (0,0,-5000); all coordinates below are local:

- Paving x 1.5…33.5, z 17.5…46.5, exact floor top y=0.
- Parking x -8.5…1.5, with striped bays and two static delivery vans.
- Arrival (4,1,28), return door (2.3,1.25,28).
- Dining booths retain centres x 7.5/12.5/17.5/22.5, z 22.4/33.6.
- Three storefront bays along the east edge, separated at z 18/25/32/39.
  Shop roofs have underside y=4; sloping canvas awnings extend into the plaza.
- Poke (30,0,22.5), kebab (30.2,0,28), Wendy's (30,0,35), all facing west.
  Walk along x=26 to avoid the canopy posts at x=27.
- Brick-based metal site fences guard the edges. Distant tenements are scenery.
  Nothing behind the fence is a second playable area.
- Fourth bay: Żabka at z 39…46, facing west beside Wendy's. Paving and site fences
  extend to z 46.5; the original three shops, seating and arrival are unchanged.
  Walk south along x=26, then into the open bay at z=43.5. GPS lists **Żabka**.

`structure.tscn` stores editable GridMaps, not a runtime layout generator.
The feature-owned MeshLibrary uses the casino's 1 × .25 × 1 m grid convention
(with centering disabled), eight-cell batches, separate partition grids and
simple layer-1 collision. Tile IDs:
0 paving, 1 asphalt, 2 brick wall, 3 roof, 4 canvas awning, 5 opaque shop window,
6 canopy post, 7 planted trough, 8 parking stripe, 9 site fence.
Five shadowless lights load only with the room. No per-frame mall code or new
shadow lights are added.

Rebuild approved meshes and saved cells from the repository root:

```sh
godot --headless --path game -s res://features/strip_mall/tools/build_assets.gd
godot --headless --path game -s res://features/strip_mall/tools/build_layout.gd
```

Preserve hand edits in the offline recipe before rebuilding. Mesh/paint budgets,
exact UV template, generated painting and prompt are in
`docs/design/model-sources/strip-mall/`. Native builders are used because no
Blockbench tool connection is available.

Tests: `tests/features/strip_mall/`, original food-court/kebab ordering and seat
suites, GPS and the casino layout suite. For actual main-game rendered review:

```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/strip_mall/capture.tscn -- /tmp/strip-mall
```

The existing Wendy's probe now preloads the mall and reviews offline ordering
and held burgers in both camera modes. Neither render probe is a browser FPS test.

## Żabka and its live display

The fourth bay is an explorable convenience-store landmark, not another food
ordering system: the counter explicitly says DISPLAY ONLY. White modeled **żabka**
lettering sits on the green canopy fascia, facing west into the plaza; Polish
**KAWA - HOT DOG**, **POLSKI SKLEP** and **MAŁE ŻABKI** signs accompany the coffee
cup, stocked bottle shelves and frog display. No purchases, new keys or inventory
items are added. Keyboard, controller and touch visitors use the existing travel
controls described above. The sign kit's new Ż/Ł glyphs retain ASCII/fallback behavior.

`zabka_decor.tscn` reuses the existing prop-grain texture, native BoxMesh furniture
and imported bottle/coffee-cup assets. There are seven furniture meshes (84 triangles),
plus the existing sign kit, nine shared bottle instances and one cup. Native primitive
UVs reuse approved artwork; no new texture/atlas or external logo image is shipped.
The fascia bottom is 3.15 m, clear of standing players. `zabka_sign.gd` subclasses
SignBoard only to supply green backing/frame material; its letters remain the shared atlas.

`frog_display.tscn` stays outside streamed Content at (31.25,0,41.5). Its six-box,
3 × 2.5 m glass habitat has a floor top at 0.8 m and a closed lid at 2.3 m, with
layer-1 collision on every peer even when the plaza is unloaded. The contained three
half-size frogs reuse `frogs/feature.tscn`, its server spawner and spawn profiles,
continuous authoritative snapshots, collision-aware hops, explosions and four-second
respawns. No new RPC or alternate animal networking component is introduced: this
extends the existing specialized frog implementation rather than migrating its protocol.
Late joins see current frogs/alive state without old explosions. Room unload/reload
never removes or duplicates the colony; network session changes recreate it using the
existing lifecycle. Player disconnects/respawns leave it alone. Colony state is session
memory and resets on server restart. Only three extra animals and one shadowless,
streamed light are added; no new per-frame shop logic or shadow maps.

Run the real three-peer authority/death/late-join/respawn probe with:

```sh
bash game/tests/features/strip_mall/network_test.sh
```

Reviewed storefront and frog captures are in `docs/design/previews/zabka/`.
