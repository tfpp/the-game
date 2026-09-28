# Holdables

Generic items players can pick up and hold: `pistol` (weapon), `banana` (food) and
`ball` (prop), plus the framework to add more.

## Adding an item

1. Drop a view scene under `items/` — just meshes, no script (see `pistol_view.tscn`,
   `banana_view.tscn`, `ball_view.tscn`). A weapon's view can include a `Marker3D`
   named `Muzzle`; the fire flash appears there if present.
2. Add an `ItemDefinition` `.tres` under `items/` pointing at it, with an `id`,
   `display_name` and `category` (`WEAPON`, `FOOD` or `PROP`; see `item_definition.gd`).
3. List it in `item_catalog.gd`'s `DEFINITIONS`.
4. Place an `ItemPickup` instance somewhere in `feature.tscn` with that `item_id`.

No other code changes are needed — pickup, holding, replication and the primary
action all key off the category.

## How it works

- `item_pickup.gd`: a world pickup. It's an `interactables` entry (see
  `features/interaction`), so E/controller-B hands it to whichever nearby hand is
  empty. Once taken it's gone for good (`net_taken`, replicated).
- `hand.gd`: one player's held item. The holdables feature spawns one `Hand` per
  connected peer (like `core/game/game.gd` spawns one `Player` per peer), since
  `core/player` isn't ours to edit — a `Hand` isn't parented to its `Player`; each
  frame it re-reads that player's transform and follows it near the camera (first
  person, for the local player) or near the body (for everyone else watching a
  puppet). Holding (`net_item_id`) is server-authoritative, like the rest of shared
  state — the one exception in this codebase is player movement.
- The primary action (left click / right shoulder button) asks the server to resolve
  it based on the held item's category:
  - `WEAPON`: fires (a cosmetic muzzle flash for now — there's no damage model yet).
  - `FOOD`: eaten once and gone.
  - `PROP`: thrown. `thrown_item.gd` arcs it from hand to a landing point (a raycast
    finds the floor under the throw), then it becomes a pickup again where it lands,
    so a thrown ball can be picked back up and thrown again.
- `throw_math.gd`: pure arc/aim math, unit-tested the same way
  `features/frogs/frog_hop.gd` keeps its hop math separate from the scene.
