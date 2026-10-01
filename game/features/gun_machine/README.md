# Gun machine

A machine that sells a randomly generated gun for $20, and a trash can next to it
that gets rid of your current one. Both stand in Rusty Hogg's pawn shop
(`features/pawn_shop`), west off the south corridor. Its holding, firing and projectile system is
independent of `features/holdables` (which has its own fixed pistol/SMG/shotgun/AWP):
a generated gun's stats vary per instance, so it can't reuse `holdables`' static
`ItemDefinition` catalog. The two are still mutually exclusive, though — equipping a
gun from either system holsters whatever the other was holding, so only one weapon is
ever in hand. See `gun_rig.gd`'s `holster`/`net_equipped` and
`features/inventory/player_inventory.gd`'s `holster_weapon`.

## How it works

- `gun_generator.gd`: pure, seeded random generation (`GunGenerator.generate(rng)`),
  unit-testable the same way `features/gnomes/gnome_math.gd` keeps its math separate
  from the node that uses it. Every gun rolls an ammo type (`AmmoType`: buckshot,
  rifle, low-caliber, rocket, grenade, plasma) and, within that type's ranges,
  barrel count, fire rate, magazine size, damage, total ammo capacity, projectile
  speed and spread, plus a fire mode (`is_automatic`, `AUTOMATIC_CHANCE` odds,
  independent of ammo type). Barrel count is capped at the rolled magazine size, so a
  gun can always at least be fired once fully loaded. `AMMO_PROFILES` holds each ammo
  type's fixed behavior: pellets per barrel (buckshot sprays several), gravity scale,
  bounces, fuse time, explosion radius and splash force.
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
- `gun_rig.gd` (group `gun_rigs`): one player's currently rolled generated gun —
  what it is, how much ammo is loaded (magazine + reserve, both spent and refilled
  server-side by `request_fire`/`request_reload`) — and where its visual sits, the
  same "not parented to the Player" tracking `features/holdables/hand.gd` uses since
  `core/player` isn't ours to edit. Unlike `Hand`, a `GunRig`'s remote-peer mount
  follows the player's *full* aim direction (yaw and pitch, from `net_yaw`/`net_pitch`),
  not just a fixed offset, so it visibly points where they're looking; the local
  first-person viewmodel uses the same bottom-right, aimed-at-the-reticle camera
  offset `Hand` does. `net_equipped` tracks whether the rolled gun is actually in
  hand (`is_active()`) or holstered in reserve: `holster()` clears it without
  touching `net_stats`, so the gun survives being set aside for a holdable weapon,
  and `request_equip_rig` (bound to 9 and the scroll cycle by
  `features/weapon_hotbar`) brings it back. Firing, reloading and the visual mount
  all check `is_active()`. A semi-automatic gun (`net_stats["is_automatic"]` false)
  fires once per `gun_fire` press, same as before; an automatic one also polls every
  frame (`_maybe_auto_fire`, gated by the pure `should_auto_fire`) and keeps firing
  at its own fire rate for as long as the button stays held.
- `gun_view.gd`: selects the authored double-barrel plasma model or builds a mesh
  from rolled stats (barrel count, thickness from damage, length from projectile
  speed, color from ammo type) for other guns.
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
  everyone within `explosion_radius` — falloff damage (`ProjectileMath.splash_damage`)
  for everyone but the direct-hit target, and a falloff splash force
  (`ProjectileMath.splash_force`) that shoves *everyone*, direct-hit target
  included, away from and slightly above the blast. Since movement is
  client-authoritative and `core/player` isn't ours to edit, that push goes through
  `Player.server_teleport` — the documented way (game/AGENTS.md) to move a player
  from the server — to an offset destination rather than a velocity impulse.
  A world hit either bounces (grenades, losing energy each time —
  `ProjectileMath.bounce`/`should_settle` — until they settle and explode) or ends
  the shot outright (everything else). Grenades also detonate on a fuse regardless
  of what they've hit. An explosive impact plays `explosion_effect.gd`'s bigger
  flash-and-shockwave burst instead of the plain impact flash non-explosive rounds
  get. Every ammo type is a real projectile, not a hitscan.
- `explosion_effect.gd`: the cosmetic flash + growing shockwave sphere + sound cue
  for an explosive projectile going off, sized to its `explosion_radius` — purely
  visual/audio and unnetworked, like `features/animal_effects/mesh_explosion.gd`'s
  death burst; every peer spawns and animates its own copy from the server's event.
- `gun_stats_panel.gd`: a small always-on ammo readout, and — Tab — the full rolled
  stat sheet (including fire mode), the extra UI a randomly generated weapon needs
  since its specs aren't printed on a fixed item.

Generated gun view mounts scale about the player's feet (or camera in first person)
using `PlayerHeight.eye_scale(player)`, so ID-based height and Sor's tiny build do
not leave weapons floating at normal shoulder height. Eye-based shot origins pick
up the same per-player height; stats, damage, ammo and firing authority are unchanged.

## Ray Gun

`GunGenerator.RAY_GUN_CHANCE` (1 in 30, about the Call of Duty Zombies mystery box
odds) makes a purchase hand out the fixed `GunGenerator.ray_gun()` instead of a random
roll: `AmmoType.RAY`, semi-auto green bolts with a small splash, 20-round magazine and
160 rounds total. `GunView` gives it a red body and glowing green rings.

## Adding to the price or ranges

`GunMachine.PRICE_CENTS` and `GunGenerator.AMMO_PROFILES`' ranges are the only
numbers to tune for balance; nothing else needs to change.

## Performance

`gun_fx.gd` (`GunFx`) caches every gun and projectile material and the flash mesh.
Muzzle, impact and explosion flashes are unshaded glow meshes, not `OmniLight3D`s: on
the web's Compatibility renderer each new light or material variant compiled a shader
mid-game, which stuttered on buying and firing (issue #241). Clients call
`GunFx.warm_up()` once a camera exists, drawing each variant for a few frames at load.

## Double-barrel plasma model

Two-barrel plasma rolls (automatic and semi-automatic) use the authored
`double_barrel_plasma.tscn` model. Other rolls retain their procedural meshes and
stat-driven dimensions. This visual replacement does not change rolled stats.
See [asset source and export instructions](../../assets/gun_machine/models/README.md).

`Grip` and `SupportGrip` opt the generated weapon into `HeldItemPose` and
`HeldArms`, shared with catalog weapons. First person uses the camera-relative
mount; third person and remote peers use the body-relative mount and aim pitch.
Human avatars use their own skinned arms; creature bodies use the existing arm
fallback. Skin and sleeve colors follow the player's appearance. Procedural rolls (including
the Ray Gun) get `Grip` under the rear of the body and `SupportGrip` under the
barrels from `GunView.build`, so every generated gun is hand-rigged. Holstering
disables the hand pose.
`Muzzle` remains the cosmetic shot origin, with separate left/right markers for
future barrel-specific effects; authoritative projectile origins remain at the eye.
