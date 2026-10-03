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
  The pawn counter remains owned by `slum_runs`, positioned inside the shop.
  The Gun-O-Matic and its trash can now live in the Dev Room instead.
  The former casino doorway is sealed with tiles.
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
  holdables pistol ($1,500), SMG/shotgun ($5,550) and AWP ($15,000) with price tags.
  Use one to buy an empty copy; stock is unlimited. Prices share GunBuyCatalog.
  Buy separate ammo with **!guns → 9. Classic ammunition** or **Esc → Activities →
  Buy guns**; packs feed the held matching gun from the backpack.
- **Top hat stand** in the north-west corner at (-13.6, 0, 21.4): a wood plinth with a
  brass cap holding the tall black silk top hat (`ClothingCatalog.TOP_HAT`) for
  $10,000. It is another `WallGun` instance (`tag_position` lifts its price tag above
  the hat); buying it puts the hat straight on your head via the inventory hat slot.
- The whole shop is a **safe zone** (`features/safe_zone`): no PvP damage or
  firearm use; rejected shots spend no ammo. The street scenery is outside the zone.
  Self-damage commands retain the existing safe-zone exception.

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

## Prawn skin crates

Use the cream-stencilled wooden crate beside the east end of the gun wall
(local **-4, 0, 21.1**) with **E / B or Circle / touch USE**. This interprets
“Prawn Shop” as Rusty's pawn shop, not a new seafood store. **Inspect** shows every
outcome, compatible weapon, rarity colour/name and exact chance **before** the
purchase button. Buy a sealed **Harbour Prawn Pot ($5)** or **Midnight Trawler ($10)**,
then open it at no extra cost. No keys, real-money purchases or trading are involved.

Each crate contains five exclusive skins, one per Common/Uncommon/Rare/Epic/Legendary
tier. Default tier chances are **60% / 25% / 10% / 4% / 1%**, exactly 100%; there is
one skin per tier, so those are also the individual skin odds. The ten original
finishes use muted brine, kelp, reef, bisque, pearl and aged-gold palettes, coarse
curled-prawn stamps and segmented-shell bands on the existing classic models.
The world crate reuses the existing painted wooden crate with a small cream prawn
stencil; no new model or runtime texture is introduced.

Open **Esc → Activities → Prawn skins**, or **Inventory → Prawn skin collection**,
to manage anywhere. These menus work with mouse/touch buttons and controller focus.
Collection previews render the actual painted weapon, through the inventory's
bounded shared `ModelIconRenderer` cache. Select a finish to equip or unequip it
for its compatible pistol, SMG, shotgun or AWP. It applies to every copy you hold,
in first person, F3 and on other players. Dropped/shop guns retain their stock
appearance; a pickup adopts its new holder's loadout. Generated Gun-O-Matic guns
are not compatible. Weapon ownership, backpack slots, ammunition, prices and all
weapon stats remain unchanged.

Opening plays a 2.4-second decelerating cosmetic reel **after** the skin is safely
saved. Closing the menu cannot lose the reward. Duplicates increment a count;
**Exchange ONE duplicate** credits the shared wallet and keeps the last copy,
including an equipped copy. Default exchange values by tier are
**$0.50 / $1 / $2 / $5 / $10**. Empty inventories, insufficient money, loading,
invalid configuration and storage errors have explicit messages. No new key binding.

### Authority, configuration and persistence

`PrawnSkins` in `skin_crates.tscn` is the sole owner of collection rules.
`skin_catalog.gd` is a pure whitelist/mutation catalog: crate counts, skin counts
and one equipped skin ID per compatible weapon. This is an account cosmetic
collection, **not** consumable backpack items; ordinary inventory snapshots and
their delayed saves must not write it.

The scene's exported `odds` contains five integer **basis-point** weights
(10000 = 100%). Set all five, nonnegative, totalling exactly 10000.
`duplicate_cents` contains five positive integer cents values, up to $100,000 each.
Invalid odds/refunds block mutations, rather than silently normalizing misleading
odds. Crate contents, names and prices are trusted constants in `skin_catalog.gd`.
Changes require a matching game build, not a client-supplied configuration.

`NetworkedInteraction` validates the shop-use sender/range/empty payload.
Collection actions use that same `NetworkedEntity` transport, with exactly
`{action, id, revision}`; no peer, price, reward, stats or document is accepted
from a client. Buying rechecks shop range; all actions require a real player and
the current collection revision. The server rolls the skin and reserves one
immutable operation ID/document before asynchronous storage. Per-account locks
block concurrent requests, and stale observed revisions prevent accidental double
clicks from creating new operations.

`PlayerMoney.cosmetics()` serializes with existing wallet operations and calls
the signed money API's `cosmetics_load` / `cosmetics` actions.
The append-only SQLite migration adds `cosmetics` and `cosmetic_transactions`.
A document revision compare-and-swap, wallet debit/credit, collection update and
operation receipt commit in **one database transaction**. Retrying an ID must
repeat the same account, original revision, delta and document; replays return
current state, never an obsolete balance/document. The API trusts only the
HMAC-authenticated game server, which owns gameplay/catalog validation.

Signed-in collections, unopened crates and equipment survive disconnects,
respawns, server restarts and redeploys. API load failure blocks mutations and
never writes an empty collection over stored data. Lost responses retain the exact
pending operation for **Retry saved transaction**; it cannot reroll or recharge.
A reconnect loads current storage and can resolve a still-pending receipt.
A server crash recovers any committed transaction on the next load; an uncommitted
transaction changes neither money nor collection. Disconnect removes public peer
equipment; a pending account transaction still settles to that account. Session
changes ignore stale callbacks. **Offline/dev collections and wallets are
temporary and reset with the session**, matching the existing economy.

Only equipped IDs replicate to everyone, including late joiners. Collection
counts/status/results travel as private owner-only events, never replaying reveals
to late joiners. Cosmetics poll existing Hand views at 5 Hz and update material
instances only when paint/view changes, without touching Hand's firing or stats.
There are no extra lights, spawners or continuously-rendering collection viewports.

Deploy the **API first**, then game/server clients. This feature necessarily changes
the human-reviewed API paths: the old independent charge and delayed inventory save
cannot guarantee an atomic purchase. No new credentials or dependencies are needed.

Tests: `test_skin_catalog.gd`, `test_skin_transactions.gd`,
`test_skin_persistence.gd`, `test_skin_layout_ui.gd` and real ENet
`test_skin_network.gd` in `tests/features/pawn_shop/`. Go cosmetic store/handler
tests cover atomic rollback, retry immutability, concurrent CAS and SQLite reopen.
Original shop travel, purchases, inventory and wallet tests remain supported.
Capture actual Compatibility renders using `skin_capture.tscn` as above;
test-only seed data is confined to the capture script. See
`docs/design/previews/prawn-skins/` for reviewed desktop/phone and world captures.

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
