# Holdables

Generic items players can pick up and hold: `pistol`, `smg`, `shotgun` and `awp`
(weapons), `banana` (food) and `ball` (prop), plus the framework to add more.

## Adding an item

1. Drop a view scene under `items/` — just meshes, no script (see `pistol_view.tscn`,
   `banana_view.tscn`, `ball_view.tscn`). A weapon's view can include a `Marker3D`
   named `Muzzle`; the fire flash appears there if present. Use -Z as forward.
   Add a `Grip` marker at the primary hand contact and an optional `SupportGrip`
   for the other hand. Their bases define glove orientation. The hand mount
   applies the inverse `Grip` transform; pickups keep the original model pose.
2. Add an `ItemDefinition` `.tres` under `items/` pointing at it, with an `id`,
   `display_name`, `category` (`WEAPON`, `FOOD` or `PROP`) and `weight` (see
   `item_definition.gd`); weapons also set `damage`, `fire_cooldown_s`,
   `pellet_count` and `spread_degrees`. `first_person_offset` places the primary
   grip relative to the camera; allow room for stocks. `ground_clearance` keeps
   dropped meshes above the floor.
3. List it in `item_catalog.gd`'s `DEFINITIONS`.
4. Place an `ItemPickup` instance somewhere in `feature.tscn` with that `item_id`.

No other code changes are needed — pickup, holding, replication and the primary
action all key off the category.

## How it works

- `item_pickup.gd`: a world pickup. It's an `interactables` entry (see
  `features/interaction`), so E/controller-B equips it in an empty matching slot or adds it to
  the backpack. Once taken it's gone for good (`net_taken`, replicated). Picking up or
  equipping a `WEAPON` holsters `features/gun_machine`'s rig if it's out
  (`PlayerInventory.holster_weapon`/`_holster_gun_rig_if_weapon`), so a holdable
  weapon and a generated gun can never both be equipped at once.
- `hand.gd`: one player's held item. The holdables feature spawns one `Hand` per
  connected peer (like `core/game/game.gd` spawns one `Player` per peer), since
  `core/player` isn't ours to edit — a `Hand` isn't parented to its `Player`; each
  frame it follows the camera in first person, or a chest-height grip in front of
  the body in third person and on remote peers. It updates after the player and
  F3 camera, follows yaw and pitch, and avoids a second physics interpolation.
  `held_arms.gd` connects cosmetic sleeves to the shoulders and places gloves at
  each model's grip markers. A banana uses one hand; guns and the ball use two.
  Holding (`net_item_id`) is server-authoritative, like the rest of shared state — the one exception in this codebase is player movement.
- The primary action (left click / right shoulder button) asks the server to resolve
  it based on the held item's category:
  - `WEAPON`: hitscans from the replicated player eye position (independent of
    camera mode or the visual item pose), once per `pellet_count` (a shotgun fires
    several at slightly randomized angles — `spread_degrees`), and deals `damage` to
    whichever `Player` a pellet hits by calling `apply_damage` on
    `features/combat` (see that feature for health and kills). A pellet that hits
    anything else in the `killable` group (e.g. `features/penguin`) instead calls
    `take_hit` on it, so non-player targets can handle being shot on their own
    terms. `fire_cooldown_s` caps the rate of fire, so an SMG just needs a short
    cooldown to feel automatic even though every shot is still its own click.
  - `FOOD`: eaten once and gone.
  - `PROP`: thrown.
  - Any held item can also be dropped with G / left shoulder button
    (`request_drop_item`), regardless of category. The inventory can also store
    the held item or swap it with another item in the backpack.
- `thrown_item.gd`: arcs an item from hand to a landing point (a raycast finds the
  floor under the throw — see `_toss` in `hand.gd`, used by both a PROP's throw and a
  plain drop), then bounces it a few times, lower and fewer bounces the heavier the
  item's `weight`, before it settles as a pickup again where it lands. A dropped
  pistol just thuds — weapons are heavy enough not to bounce.
- `throw_math.gd`: pure arc/aim/bounce math, unit-tested the same way
  `features/frogs/frog_hop.gd` keeps its hop math separate from the scene.

The `kebab` FOOD item is supplied by `features/kebab_shop` through the same
`PlayerInventory.collect` interface. Its detailed view lives with that shop;
consumption, drops, grip positioning and replication use the ordinary food path.
