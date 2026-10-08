# Inventory and clothing

Press **I**, the controller **View/Back** button, or **Esc → Activities → Inventory**.
The screen uses the project's Kenney panel and button assets. It shows a live
character preview, equipment and an eight-slot backpack. The top-right coin and
balance read the existing wallet and never occupy a slot. Select an item to equip,
store or drop it. The screen pauses gameplay input while open.

Players start barefoot in white underwear, with no equipment or backpack items.
Use the existing **E / B / Circle / USE** interaction to collect items. Pickups
fill the matching empty equipment slot first (hand, shirt or pants), then use the
backpack. Equipping a backpack item swaps it with the current item in that slot,
even when the bag is full. Eating and throwing affect only the held item.

Searching a car or dumpster opens its shared stash beside your backpack. Drag
an item to an empty slot, or tap it to fill the next empty slot. Other players
see items disappear as they are claimed.

Backpack and stash icons render the actual item view from `ItemCatalog`, including
procedural clothing. `ModelIconRenderer` automatically frames mesh bounds in a
private transparent 128×128 viewport. Each item renders once, then shares a cached
texture across controls; the viewport stops updating between jobs. The cache is
limited to 128 textures and headless servers allocate no rendering viewport.
`ItemDefinition.icon_view_direction` controls the viewing angle. Valuable icons have a rarity-colored border, leaving the actual model colors
intact. Stash entries, backpack tooltips and the selected item's description show
the rarity name and pawn price; tap/select an item on touch or controller to read
it without needing hover. The money balance keeps its separate coin symbol. [`loot-models.md`](../../../docs/design/loot-models.md)
includes actual inventory screenshots and a capture command.

Shirts and pants have fixed colors. Find other colors to change your outfit;
there are no dye controls. Two clothing pickups sit near spawn, two to the west,
and two to the east. Clothes keep their color through swaps, drops and pickups.
White underwear reappears when pants are removed; it cannot be stored or dropped.

## Weapon skin collection

Choose **Prawn skin collection** in this screen, or **Esc → Activities → Prawn skins**.
Rusty Hogg's pawn shop owns this separate account cosmetic collection and its atomic
wallet transactions; it does not consume backpack slots or alter these ordinary
inventory documents. Buy crates beside the pawn-shop gun wall, then open, equip,
unequip or exchange extra skin copies through that collection panel.
See [prawn crates](../pawn_shop/README.md#prawn-skin-crates) for odds, persistence
and temporary offline behavior. Classic guns and ammunition still use the normal
inventory. Closing Inventory to open the collection transfers modal input control
without resuming gameplay underneath it.

`ModelIconRenderer.request_model(key, factory, direction)` allows cosmetic
preview factories to share the same bounded render-once viewport/cache as
`request_item` and `request_scene`. Keys receive the `model:` namespace,
so skinned previews cannot replace ordinary item icons. The factory must return
a fresh Node3D; all framing, headless guards and cleanup remain in the renderer.

## Multiplayer

`PlayerInventory` is a child of the existing server-spawned `Hand`. Its inventory
and clothing are synchronized from authority 1, including to late joiners.
Clients request slot operations; they cannot supply new item IDs or target peers.
The server checks sender ownership, slot bounds, bag capacity and pickup distance.
Repeated pickup/drop requests cannot duplicate items. The avatar and held arms
read replicated clothing, so other players see equipment changes too.

Classic ammunition packs automatically collect into the backpack and consume a slot.
The held matching gun draws one round per shot; partial pack IDs preserve the exact
remaining count through storage, drops and persistence. See
[ammunition prices and controls](../gun_machine/README.md#classic-ammunition).

Inventory survives an in-session combat respawn. World pickups follow the existing
one-use pickup system.

Run `harness/verify.sh` from the repo root. Feature tests cover capacity, swaps, consumption, fixed
colors, invalid and foreign requests, drops, pickups and underwear visuals.

Cigarettes and bottled beer from the bar shop use the ordinary hand/backpack slots.
During their three-second use animation, inventory mutations are temporarily denied
so a reserved consumable cannot be stowed, swapped or dropped. New pickups can still
fill free backpack slots. Both items have distinct inventory silhouettes.
Each lasts three uses; partially used items retain their remaining count through
storage, swaps and drops, and display it in their item names.

## Persistence

Signed-in players' held item, shirt, pants, backpack and keys are stored in the
accounts API's SQLite database (`inventories` table, one JSON document per account),
so they survive disconnects, server restarts and redeploys. `inventory_persistence.gd`
runs on the game server only:

- When a Hand spawns for a signed-in account, `PlayerInventory.loading` blocks
  pickups and slot requests while the saved snapshot loads. `restore()` merges it:
  unknown IDs, clothing in the wrong slot and non-key "keys" are skipped; an item
  whose slot is already taken moves to a free backpack slot or drops at the player.
- Changes are saved at most once a second and once more when the Hand leaves
  (disconnect). A server crash can lose up to a second of changes. Each account
  has one request in flight at a time, so saves land in order, and a reconnect's
  load waits for the previous session's final save.
- If the load fails after three tries, the session stays playable but is not saved,
  so an API outage can never overwrite stored items with an empty inventory.
- Offline and dev-auth players have no account ID and keep the in-memory inventory.

The endpoint is `POST /api/game/inventory` with actions `load` and `save`, signed
like the money endpoint (`X-Game-Signature`) but over `game-inventory-v1\n` plus
the body, so wallet signatures can't be replayed. Documents are limited to 8 KiB.
Deploy the API first; its migration adds the table automatically.

## Garbage can

A dented green-and-brass trash can stands at the east end of the lobby wardrobe
counter (17.3, 0, 17). Use it (**E / B / Circle / USE**) while carrying something
to open a confirmation. **Throw away** (click, tap or controller A) clears your
held item and every backpack item; **Cancel** or Esc closes it. Worn clothes and
keys stay. The server re-checks range and ownership through `NetworkedInteraction`
and notes the count in your chat log.

## Hats

The equipment column has a fourth **HAT** slot (`PlayerInventory.hat`, slot -4,
replicated like shirt and pants). Hat IDs are `hat:<color>` clothing; the color is
the band, the crown is always black silk (`top_hat.gd`). The only hat in the world
is the pawn shop's `ClothingCatalog.TOP_HAT` ("Top hat", $10,000). `BlockPlayerModel`
wears it on the human head bone, or on the frog, bird or penguin head pivot, so
everyone sees it; it is hidden with the rest of your body in first person.

The operations van rear stash extends the saved inventory document with a
server-only `van_stash` array, capped at 24 known non-key item IDs. It is never
included in Hand replication. `InventoryPersistence.commit_inventory` serializes
an entire carried/stashed transfer through the existing account save queue and
waits for durable acknowledgement; uncertain HTTP results are read back before
unlocking. Stash transfer UI and range/door/lift checks belong to starter_room.
Offline first stash use activates atomic `user://offline-inventory.json` snapshots
of carried and stored items, followed by the normal save interval and final Hand
exit write. Dev-auth guests retain session inventory and cannot access saved stash.

## Undressing (#538)

`PlayerInventory.stow_equipment(slots)` is a server-only helper that empties the given
equipment slots (-1 hand, -2 shirt, -3 pants, -4 hat) into free backpack slots and
drops anything that does not fit at the player through the normal holdables drop.
It refuses while loading or mid-sip, and never touches keys. `features/booze` uses it
when a drinker blacks out, leaving them in the white underwear.
