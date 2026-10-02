# Pawn shop

Rusty Hogg's gun and pawn shop is a separate street-facing store. From the
operations garage, use the van and choose **Gun Shop · Rusty Hogg's**. The shop's
front door returns directly to the operations garage, with its floor preloaded.
The parked van, public road, pavements and buildings are visible through closed
windows; the exterior is scenery and cannot be entered. GPS routes through the
casino's operations-garage door and then to the van.

- Feature origin: (0, 0, -4000). Local room bounds remain x -16…-2, z 20…30,
  floor y 0, ceiling y 5. The saved grids in `structure.tscn` use the same
  `casino_tiles.tres` MeshLibrary as the casino: tile floors and plaster walls, stucco
  window sills, headers and ceiling tiles. Separate grids preserve corner cells.
- `Room` streams only static architecture, street scenery and four shadowless
  lights from `interior.tscn`. Guns, Rusty, the hat and return endpoint remain
  present on every peer; existing network paths and purchase behavior stay stable.
  The Gun-O-Matic and pawn counter remain owned by their original features,
  positioned inside the new shop. The former casino doorway is sealed with tiles.
- Rebuild only the saved store structure with
  `godot --headless --path game -s res://features/pawn_shop/tools/build_store.gd`.
  Road, props and van are hand-placed editable instances in `street.tscn`, reusing
  existing low-resolution assets. All coordinates below are local to the shop.
- **Pawn counter** (`slum_runs`' `LootFence`, unchanged behavior) stands at
  (-11.5, 0, 24.5) as a low glass display case with jewelry, a telephone,
  ledger and service bell. Three pawn balls hang above it. Rusty Hogg
  (`rusty_hogg.tscn`) stands behind it facing the customer aisle. He is a `StationaryPatron`
  (`features/casino_patrons`): shootable like the salon characters, back in 6 s.
- **Gun wall** on the north wall: `wall_gun.tscn` (`WallGun`) instances hang the
  holdables pistol ($30), SMG ($75), shotgun ($90) and AWP ($150) with price tags.
  Use one to buy an empty copy; stock is unlimited. Prices share GunBuyCatalog.
  Buy separate ammo with **!guns → 9. Classic ammunition** or **Esc → Activities →
  Buy guns**; packs feed the held matching gun from the backpack.
- **Top hat stand** in the north-west corner at (-13.6, 0, 21.4): a wood plinth with a
  brass cap holding the tall black silk top hat (`ClothingCatalog.TOP_HAT`) for
  $10,000. It is another `WallGun` instance (`tag_position` lifts its price tag above
  the hat); buying it puts the hat straight on your head via the inventory hat slot.
- **Gun-O-Matic** and its trash can (`features/gun_machine`) stand by the south wall.

## Buying a gun

`WallGun` uses `NetworkedInteraction`: the server resolves the sender, checks range
and that the inventory has room, then charges `PlayerMoney.charge()` and hands the
gun over with `PlayerInventory.collect()`. One payment per peer can be pending per
gun. If the bag filled or the buyer left while paying, the paid gun drops on the shop
floor as an ordinary thrown item, so money is never taken for nothing. Rusty's reply
(price, "can't afford", etc.) shows as a subtitle to the buyer only. A session reset
ignores unfinished payments. Nothing is persisted beyond the wallet and inventory.

Tests: `tests/features/pawn_shop/`.

## Talking to Rusty

Step beside the counter near Rusty until **Talk to Rusty Hogg** appears, then press
E, controller B/Circle or touch USE. The nearest interaction still wins, so the
front of the pawn counter continues to offer **Pawn a valuable**. Rusty gives one
of twelve lines (the six requested in #397 plus six pawn-shop quips) as a private
subtitle, without repeating his previous line. These are text-only conversation
lines; the gun warning is a quip, not an aiming-triggered reaction.

`rusty_hogg.gd` extends `StationaryPatron`; the inherited component still owns
hitboxes, life replication and six-second respawn. Its separate `Talk`
`NetworkedInteraction` validates sender, empty payload, 2.5 m range and living
state on the server, with a shared 0.5 s cooldown. The server selects the line and
sends a private transient `say` event through the existing subtitles feature.
Late joiners see Rusty's current life state and can talk when he is alive, without
replaying old dialogue. The last line is session-only and resets on session change;
there are no per-player claims, pending payments or disconnect/respawn cleanup.
Existing purchase receipts and loot sales retain their own behavior.

Render the actual game with a display:

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/pawn_shop/capture.tscn -- /tmp/gun-store
```

Layout tests cover merchandise access, enclosed frontage and roof collision; travel
tests cover van preload, garage return, feature load order and GPS routing.

Saved actual Godot Compatibility captures are in
`docs/design/previews/gun-shop/`: arrival, window/van view and garage return.
They verify presentation, not browser performance.

## Secondhand-shop dressing

The glass counter and three metal shelf units follow the mesh-first modeling prompt,
with one shared 64×64 painted atlas. Existing TV, radio, luggage, phone, clock and
furniture models fill the shelves. Modeled signs, price cards, window security bars
and fluorescent fixtures complete the shop. The source, UV guide, paint prompt and
GLB/OBJ exports are in `docs/design/model-sources/pawn-shop/`.

The loot fence accepts an optional cosmetic `storefront_scene`; its authentication,
sales and wallet logic remain the same. Its collider fits the new 2.8×1.15×.8 m case.
The older procedural storefront remains the default for other callers.

Rebuild the editable dressing with:

```sh
godot --headless --path game -s res://features/pawn_shop/tools/build_dressing.gd
```
