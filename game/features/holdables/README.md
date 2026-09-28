# Holdables

Generic items players can pick up and hold: `pistol`, `smg` and `shotgun` (weapons),
`banana` (food) and `ball` (prop), plus the framework to add more.

## Adding an item

1. Drop a view scene under `items/` — just meshes, no script (see `pistol_view.tscn`,
   `banana_view.tscn`, `ball_view.tscn`). A weapon's view can include a `Marker3D`
   named `Muzzle`; the fire flash appears there if present.
2. Add an `ItemDefinition` `.tres` under `items/` pointing at it, with an `id`,
   `display_name`, `category` (`WEAPON`, `FOOD` or `PROP`) and `weight` (see
   `item_definition.gd`); weapons also set `damage`, `fire_cooldown_s`,
   `pellet_count` and `spread_degrees`.
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
  - `WEAPON`: hitscans from the hand, once per `pellet_count` (a shotgun fires
    several at slightly randomized angles — `spread_degrees`), and deals `damage` to
    whichever `Player` a pellet hits by calling `apply_damage` on
    `features/combat` (see that feature for health and kills). `fire_cooldown_s`
    caps the rate of fire, so an SMG just needs a short cooldown to feel automatic
    even though every shot is still its own click.
  - `FOOD`: eaten once and gone.
  - `PROP`: thrown.
  - Any held item can also be dropped with G / left shoulder button
    (`request_drop_item`), regardless of category — the only way to get rid of a
    weapon, since firing never empties the hand.
- `thrown_item.gd`: arcs an item from hand to a landing point (a raycast finds the
  floor under the throw — see `_toss` in `hand.gd`, used by both a PROP's throw and a
  plain drop), then bounces it a few times, lower and fewer bounces the heavier the
  item's `weight`, before it settles as a pickup again where it lands. A dropped
  pistol just thuds — weapons are heavy enough not to bounce.
- `throw_math.gd`: pure arc/aim/bounce math, unit-tested the same way
  `features/frogs/frog_hop.gd` keeps its hop math separate from the scene.
