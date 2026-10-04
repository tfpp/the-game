# Guns

Every gun in the repository and how it is held. "Hand-rigged" guns carry `Grip`
(and usually `SupportGrip`) `Marker3D`s that `HeldArms`
(`game/features/holdables/held_arms.gd`) uses to pose the player's skinned hands and
fingers on the weapon, in first and third person. "Floating" (old style) guns have no grip
markers: `GunRig` hides the arms and the model hovers at the camera or body offset.

## Player guns

| Gun | Owner | Where to get it | Model | Hands |
| --- | --- | --- | --- | --- |
| Pistol | `features/holdables` (`items/pistol.tres`, `pistol_view.tscn`) | Pawn shop wall, loot | UV-mapped M1911-style model; moving slide, barrel, hammer and magazine | Hand-rigged (`Grip` + animated right/support grips) |
| SMG | `features/holdables` (`items/smg.tres`, `smg_view.tscn`) | Pawn shop wall, loot | Authored scene | Hand-rigged (`Grip` + `SupportGrip`) |
| Shotgun | `features/holdables` (`items/shotgun.tres`, `shotgun_view.tscn`) | Pawn shop wall, loot | Authored scene | Hand-rigged (`Grip` + `SupportGrip`) |
| AWP | `features/holdables` (`items/awp.tres`, `awp_view.tscn`) | Pawn shop wall, loot | Authored scene | Hand-rigged (`Grip` + `SupportGrip`) |
| Double-barrel plasma gun | `features/gun_machine` (`double_barrel_plasma.tscn`) | Gun machine roll: plasma ammo, 2 barrels | Authored scene | Hand-rigged (`Grip` + `SupportGrip`) |
| Other generated guns (buckshot, rifle, low-caliber, rocket, grenade, plasma with 1 or 3+ barrels) | `features/gun_machine` (`gun_view.gd` `build()`) | Gun machine roll | Procedural box body + cylinder barrels | Hand-rigged (`Grip` + `SupportGrip` added by `GunView.build`) |
| Ray Gun | `features/gun_machine` (`gun_view.gd`, `_add_ray_gun_details`) | Rare gun machine jackpot (`RAY_GUN_CHANCE`) | Procedural with rings | Hand-rigged (`Grip` + `SupportGrip` added by `GunView.build`) |

## NPC guns

The pistol uses a seven-round magazine and a 1.65-second reload (R / controller X).
Loaded rounds come from existing backpack pistol ammo; the HUD shows loaded / reserve.
Firing animates the slide, barrel and hammer; an empty magazine locks the slide open.
Source profiles, UV template, painting prompts and an editable GLB are under
`docs/design/model-sources/m1911/`.

| Gun | Owner | Hands |
| --- | --- | --- |
| Gunman pistol | `features/garage_enemies/enemy_model.gd` (`_pistol()`) | Attached to the enemy model's right hand each pose; not a player item |

No player gun floats any more. The floating path in `GunRig._mount_transform`
remains only as a fallback for a view without a `Grip`.

## Hand-rigging a new gun

Give the view scene a `Grip` marker where the right hand holds it and, for
two-handed guns, a `SupportGrip` for the left hand. `GunRig.has_hand_grips()` and
`Hand` pick them up automatically; `double_barrel_plasma.tscn` is the gun-machine
example.
