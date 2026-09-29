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

## Resetting

A searched container stays searched. Server code calls `reset()` on one container
or `LootContainer.reset_all(get_tree())` for all of them (e.g. when slum travel
starts a new visit); the next search rolls new loot. `regenerate()` rolls
immediately instead.

Placeholder valuables (`stolen_wallet`, `watch`, `jewelry`, `electronics`, `scrap`,
`cash_bundle`) live in `features/holdables/items/` as ordinary `PROP` items; cash
bundles are inventory items, not wallet money, for now.

Tests: `tests/features/loot/`.
