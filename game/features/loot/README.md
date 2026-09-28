# Loot containers

A reusable searchable-container system (no `feature.tscn`; it's a library other
features place). First used by `features/parking_garage/` on its wrecked cars.

- `loot_table.gd` (`LootTable`): a data-driven `.tres` with `empty_chance`,
  `min_items`/`max_items` and weighted `item_ids`/`weights` from `ItemCatalog`.
  `roll(rng)` returns a fresh list of item ids.
- `loot_container.tscn` (`LootContainer`): an `interactables` entry. Instance it
  anywhere (as a child of a car, dumpster, locker...), set `loot_table` and `noun`.
  The first Use ("Search wrecked car") makes the server roll the table and put
  the items into the searcher's inventory via `PlayerInventory.collect`. Items that
  don't fit stay inside for anyone to take with Use later.

## Multiplayer

`net_searched` and `net_contents` are server-owned and replicated by `Sync`
(authority 1, including to late joiners). Clients only send `request_search`; the
server checks the sender's range and resolves claims one at a time, so a container
is rolled exactly once and each item can only be claimed once.

## Resetting

A searched container stays searched. Server code calls `reset()` on one container
or `LootContainer.reset_all(get_tree())` for all of them (e.g. when slum travel
starts a new visit); the next search rolls new loot. `regenerate()` rolls
immediately instead.

Placeholder valuables (`stolen_wallet`, `watch`, `jewelry`, `electronics`, `scrap`,
`cash_bundle`) live in `features/holdables/items/` as ordinary `PROP` items; cash
bundles are inventory items, not wallet money, for now.

Tests: `tests/features/loot/`.
