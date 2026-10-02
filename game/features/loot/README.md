# Loot containers

A reusable searchable-container system (no `feature.tscn`; it's a library other
features place). First used by `features/parking_garage/` on its wrecked cars.

- `loot_table.gd` (`LootTable`): a data-driven `.tres` with `empty_chance`,
  `min_items`/`max_items` and weighted `item_ids`/`weights` from `ItemCatalog`.
  `roll(rng)` returns a fresh list of item ids.
- `loot_container.tscn` (`LootContainer`): an `interactables` entry. Instance it
  anywhere (as a child of a car, dumpster, locker...), set `loot_table` and `noun`.
  The first Use makes the server roll the table and opens the shared stash in the
  inventory screen. Drag an item to an empty backpack slot, or tap it to use the
  next empty slot. Items remain available to other players until claimed.

## Multiplayer

`NetworkedInteraction` owns the server request path and replicates `net_searched`
and `net_contents` through its `Sync` child, including to late joiners. Search
uses its registered Use action. Take uses a registered action with a validated
item index, expected item ID and backpack slot. The server resolves the sender,
checks range and inventory capacity, then transfers one item atomically.

`net_active_searchers` tracks current stash viewers separately from `net_searched`.
Use adds the authenticated player once and releases their previous stash. The
inventory sends a keepalive every 0.75 seconds and an end action on close, switch
or destruction. Server range checks, disconnects, resets and a three-second lease
also clear presence. One viewer leaving never closes another viewer's search.
The replicated count is included in late-join state; scenery can animate from it
without broadcasting animation frames or trusting client-supplied peer IDs.

## Resetting

A searched container stays searched. Server code calls `reset()` on one container
or `LootContainer.reset_all(get_tree())` for all of them (e.g. when slum travel
starts a new visit); the next search rolls new loot. `regenerate()` rolls
immediately instead.

Five tiered valuables (scrap, stolen_wallet, electronics, watch, jewelry) live in
features/holdables/items/ as ordinary PROP items. Their rarity and pawn price
appear in stash entries and icon borders. The existing garage/alley table
weights descend with rarity; floor-scaled tables are future B4 work. Cash bundles
are separate $5 monetary loot, carried until redeemed at the pawn counter rather
than a sixth valuable tier. See the holdables README for the price/color table.
Claims, resets and replication remain unchanged.

Tests: `tests/features/loot/`.
