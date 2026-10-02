# Crown Strip Mall

The three dedicated food shops now share a small outdoor shopping plaza:
**Poke Bowls**, **İstanbul Kebab** and **Wendy's**. The casino's bars stay put.

From the Crown's south promenade, walk down the south corridor and use the
**STRIP MALL / FOOD SHOPS** door on your left at (1.8, 1.25, 25):
**E / controller B or Circle / touch USE**. GPS lists Strip Mall, Food Court,
İstanbul Kebab, Poke Bowls and Wendy's. The return kiosk stands just behind the
arrival point and takes you back to the same casino corridor. No new keys,
prices, orders, jobs or van routes are added.

## Ownership and streaming

This feature owns only a distinct shared `StreamedRoom`, its static tiled
architecture/decor and two existing `hotel_portal.gd` endpoints. The server
validates the sender, empty request, range and destination through
`NetworkedInteraction`; `RoomDoor` preloads the destination before an
owner-only teleport. Offline uses that same server path. Simultaneous arrivals
serialize through the inherited half-second door cooldown; retry Use if busy.
There is no mutable mall state to persist, replay to late joins or clean up.

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

- Paving x 1.5…33.5, z 17.5…39.5, exact floor top y=0.
- Parking x -8.5…1.5, with striped bays and two static delivery vans.
- Arrival (4,1,28), return door (2.3,1.25,28).
- Dining booths retain centres x 7.5/12.5/17.5/22.5, z 22.4/33.6.
- Three storefront bays along the east edge, separated at z 18/25/32/39.
  Shop roofs have underside y=4; sloping canvas awnings extend into the plaza.
- Poke (30,0,22.5), kebab (30.2,0,28), Wendy's (30,0,35), all facing west.
  Walk along x=26 to avoid the canopy posts at x=27.
- Brick-based metal site fences guard the edges. Distant tenements are scenery.
  Nothing behind the fence is a second playable area.

`structure.tscn` stores editable GridMaps, not a runtime layout generator.
The feature-owned MeshLibrary uses the casino's 1 × .25 × 1 m grid convention
(with centering disabled), eight-cell batches, separate partition grids and
simple layer-1 collision. Tile IDs:
0 paving, 1 asphalt, 2 brick wall, 3 roof, 4 canvas awning, 5 opaque shop window,
6 canopy post, 7 planted trough, 8 parking stripe, 9 site fence.
Four shadowless lights load only with the room. No per-frame mall code or new
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
