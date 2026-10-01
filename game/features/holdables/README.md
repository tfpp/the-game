# Holdables

Generic items players can pick up and hold: `pistol`, `smg`, `shotgun` and `awp`
(weapons), `banana` (food) and `ball` (prop), plus the framework to add more.

Held views, gripping arms and first/third-person offsets compose with the avatar's
`height_scale()`, including ID-based heights and Sor's eight-inch build. Server
throw/drop origins use `PlayerHeight.eye_scale(player)`; damage and throw distance
are unchanged. `HeldItemPose.world_grip()` accepts an optional fourth scale argument
(default `1.0`) and anchors scaling at the nominal hull's feet. World pickups keep
their ordinary size.

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
   Inventory thumbnails render this same view scene. Set `icon_view_direction`
   when a top or side view makes an item more readable; framing is automatic.
3. List it in `item_catalog.gd`'s `DEFINITIONS`.
4. Place an `ItemPickup` instance somewhere in `feature.tscn` with that `item_id`.
   Weapons are not given away: the lobby counter only holds the banana and ball, and
   guns are sold on the pawn shop wall (`features/pawn_shop`).

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
  - `FOOD`: eaten once and gone, restoring its `heal_amount` of health through
    `features/combat`'s `heal()` (kebab and poke bowl: full health; banana: 25).
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

The `poke_bowl` FOOD item is sold by `features/food_court/poke_stand.gd` and uses
that same collection, consumption and drop path, with a two-hand bowl view.

## Cigarettes and bottled beer

Buy these at the salon bartender's **Bar shop** using E / B / Circle / touch USE.
A cigarette costs $2 and a bottled beer costs $5. They collect into an empty hand
or the backpack; equip stored items through Inventory (I / View / Esc → Activities → Inventory).
Left click, right bumper/trigger or touch FIRE starts one three-second puff or sip.
Each cigarette and bottle lasts three separate uses, disappearing after the third.
Partially used items show their remaining puffs/sips in inventory and pickup labels.
The right arm uses the existing skinned rig and grip IK, in first person, F3 and
on remote players. Cigarettes emit eight lightweight smoke particles while used;
beer tilts the bottle to the mouth. Creature heads and the penguin costume use their
own mouth contact positions. There are no new key bindings or dynamic lights.

`consumable_use.gd` is a child of the existing server-spawned Hand, not another
inventory. The primary-action RPC delegates consumables to its NetworkedEntity
validator, which checks sender ownership, an existing player, supported held item,
empty payload and idle state. The item is reserved in the hand while playing;
repeated actions, drops and inventory mutations are denied until that puff/sip ends.
Pickups may still fill free backpack slots. Beer calls `BarCompanion.add_drink`
once on the first sip per bottle; smoking is cosmetic, with no combat/healing bonus.

The catalog recognizes `beer:2`, `beer:1`, `cigarette:2` and `cigarette:1` as
partially consumed versions of the original items, sharing their models and properties.
Completion advances the held ID to the next stage. Existing inventory, stash, drop,
pickup and replication paths carry those IDs unchanged, so transfers cannot refill
an item or mix up two bottles' remaining uses. The shop only sells fresh items.

A single continuously replicated `{item, left}` snapshot includes spawn state, so
late joiners resume the current phase instead of replaying the whole action.
Clients interpolate presentation only. Completion spends one use; combat death
discards the active item as before. Despawning the player discards it, and disconnect/session reset
removes the Hand as usual. Unused items retain normal in-session respawn behavior,
but inventory is not persisted across sessions. Ordinary food remains instant,
and weapons, props and drops keep their existing behavior.

Tests: `tests/features/holdables/test_consumables.gd`, existing holdables/inventory
suites and `tests/features/bar_companion/test_bar_shop.gd`. Run actual purchases,
foreign requests, late joins and disconnects from `game/` with
`tests/features/holdables/consumable_network_test.sh`. Render the actual rig with
`tests/features/holdables/consumable_probe.tscn -- --item=beer --capture=/tmp/beer.png`;
use `--item=cigarette`, `--first-person` or `--body=penguin` for other views.
The two consumable views also define a `Mouth` marker at the bottle lip or cigarette
filter. Playback aligns this contact independently of the hand's `Grip` marker;
cigarettes relax the index/middle finger bones and other items restore their grip.

Scrap Metal and Wallet use painted low-poly meshes with shared UV islands and
128×128 atlases. Their sources, rebuild commands and model icon preview are in
[`docs/design/loot-models.md`](../../../docs/design/loot-models.md).
