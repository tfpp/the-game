# Gun machine

A machine that sells a randomly generated gun for $20, and a trash can next to it
that gets rid of your current one. Deliberately independent of `features/holdables`
(which has its own fixed pistol/SMG/shotgun/AWP): a generated gun's stats vary per
instance, so it needs its own holding, firing and projectile system rather than
`holdables`' static `ItemDefinition` catalog.

## How it works

- `gun_generator.gd`: pure, seeded random generation (`GunGenerator.generate(rng)`),
  unit-testable the same way `features/gnomes/gnome_math.gd` keeps its math separate
  from the node that uses it. Every gun rolls an ammo type (`AmmoType`: buckshot,
  rifle, low-caliber, rocket, grenade, plasma) and, within that type's ranges,
  barrel count, fire rate, magazine size, damage, total ammo capacity, projectile
  speed and spread. Barrel count is capped at the rolled magazine size, so a gun can
  always at least be fired once fully loaded. `AMMO_PROFILES` holds each ammo type's
  fixed behavior: pellets per barrel (buckshot sprays several), gravity scale,
  bounces, fuse time and explosion radius.
- `gun_machine.gd` (root, group `gun_machine_root`): server-authoritative, like
  `features/holdables/holdables.gd`. Spawns a `GunRig` per connected peer through a
  `MultiplayerSpawner`, and a `Projectile` through another whenever one fires.
  `purchase(peer)` charges `PRICE_CENTS` off the wallet (`features/money`'s
  `charge()`) and, on success, equips a freshly rolled gun. `discard(peer)` empties a
  rig with no refund.
- `gun_machine_kiosk.gd` / `gun_machine_trash_can.gd`: the two interactables (group
  `interactables`, same `can_use`/`interaction_text`/`use()` contract as
  `features/interaction`), range-checked the simple way `features/coins/coin_pickup.gd`
  is rather than `features/slot_machine`'s full facing/obstruction check.
- `gun_rig.gd` (group `gun_rigs`): one player's currently held generated gun —
  what it is, how much ammo is loaded (magazine + reserve, both spent and refilled
  server-side by `request_fire`/`request_reload`) — and where its visual sits, the
  same "not parented to the Player" tracking `features/holdables/hand.gd` uses since
  `core/player` isn't ours to edit. Unlike `Hand`, a `GunRig`'s remote-peer mount
  follows the player's *full* aim direction (yaw and pitch, from `net_yaw`/`net_pitch`),
  not just a fixed offset, so it visibly points where they're looking; the local
  first-person viewmodel uses the same bottom-right, aimed-at-the-reticle camera
  offset `Hand` does.
- `gun_view.gd`: builds a gun's mesh straight from its rolled stats (barrel count,
  thickness from damage, length from projectile speed, color from ammo type) — there's
  no fixed asset, since every gun is a one-off.
- `projectile.gd` / `projectile.tscn`: a fired round in flight. Server-authoritative
  like `features/holdables/thrown_item.gd` — the server integrates position each
  physics tick (gravity scale from the ammo profile) and publishes `net_position`;
  other peers only smooth toward it. A ray query each tick (mask `1 | 2`, the same
  mask `features/holdables/hand.gd`'s hitscan uses so rounds also reach small
  wildlife and gallery targets on layer 2) checks for a hit: a direct hit on a
  `Player` deals damage through `features/combat` (the same cross-feature
  `apply_damage` pattern `features/holdables/hand.gd` uses); a hit on anything else
  in the `killable` group (frogs, the penguin, `features/shooting_gallery`'s
  targets) calls its `take_hit` instead, since those have no player peer id for
  `apply_damage` to key on. For rockets and grenades, a direct hit also splashes
  everyone else within `explosion_radius` (`ProjectileMath.splash_damage`, falling
  off linearly to 0 at the edge). A world hit either bounces (grenades, losing energy each time —
  `ProjectileMath.bounce`/`should_settle` — until they settle and explode) or ends
  the shot outright (everything else). Grenades also detonate on a fuse regardless
  of what they've hit. Every ammo type is a real projectile, not a hitscan.
- `gun_stats_panel.gd`: a small always-on ammo readout, and — Tab — the full rolled
  stat sheet, the extra UI a randomly generated weapon needs since its specs aren't
  printed on a fixed item.

## Adding to the price or ranges

`GunMachine.PRICE_CENTS` and `GunGenerator.AMMO_PROFILES`' ranges are the only
numbers to tune for balance; nothing else needs to change.
