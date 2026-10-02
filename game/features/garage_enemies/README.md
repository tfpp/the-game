# Garage enemies

Every enemy wears the player avatar rig (`enemy_model.gd`, a `PatronModel` from
`features/casino_patrons`), dressed per tier: **ragged brawlers** (`Tier.LURKER`:
torn, patched clothes, walk up and punch), **knifers** (`Tier.STALKER`: dark hoodie,
red bandana, sprint in and slash) and **gunmen** (`Tier.GUNMAN`: tactical gear,
balaclava, pistol; the toughest at 3 hits). The enum keeps its original order for
existing scenes; `GarageEnemyTiers.STRENGTH` / `rank()` order tiers weakest to
strongest. Arms are posed with the rig's own IK (`SkinnedHuman.reach_grip`), and
the rig is only posed for cameras within 45 m.

## Basement garage (B1–B5)

`GarageEnemies/Basement` copies the transform of `features/procedural_rooms`'
`Garage` node, so its children use `CrownGarage` deck coordinates (deck `i` floor at
`y = 4i`, B5 at the bottom). Enemies stand in the front (z < 8) and back (z > 34)
lanes that population rules keep free of set pieces:

| Floor | Enemies |
| --- | --- |
| B1 (elevator arrival) | 2 brawlers, far from the arrival |
| B2 | 3 brawlers |
| B3 | 2 brawlers, 2 knifers |
| B4 | 1 brawler, 2 knifers, 1 gunman |
| B5 | 1 knifer, 3 gunmen |

`net_yaw` is stored in the parent's space (`_parent_direction`) so enemies under
the rotated basement face where they walk.

## Parking garage (P1–P3)

Hostile scavengers that haunt `features/parking_garage/`. `feature.tscn` sits at
world `(0, 0, 600)`, the same origin as the garage's `Garage` node, so every
enemy's position is in garage-local coordinates.

Players arrive on P1 through the employee door and climb, so danger rises with
each floor away from the door (the design's "deeper" direction for this
three-level garage):

| Floor | Enemies | Tier traits (`enemy_tiers.gd`) |
| --- | --- | --- |
| P1 | 3 brawlers | 1 hit, slow walking punch (8 dmg) |
| P2 | 2 brawlers, 2 gunmen | gunman: 3 hits, fires from 16 m (15 dmg), keeps its distance |
| P3 | 2 gunmen, 3 knifers | knifer: 2 hits, runs, knife slash (18 dmg) |

## How it works

- The server simulates each `GarageEnemy` (`garage_enemy.gd`). Every 0.2 s it
  looks for the nearest visible player on its own floor within its aggro radius
  and leash (half the aggro radius for crouched players, see `features/crouch`;
  a target already being chased stays noticed), walks towards them (gunmen stop at half range), raises its arms for
  a short wind-up and then strikes. Melee needs the target still in reach; a
  gunman's shot needs line of sight and misses fast-moving targets more often.
  Enemies never follow players off their floor area, and idle enemies skip
  sensing while nobody is within 30 m.
- Damage goes through `features/combat`'s `apply_damage` with the victim as the
  attacker, so no player gets a kill credit; `features/slum_runs` then drops the
  victim's valuables as for any death.
- Enemies are `killable`: any weapon hit calls `take_hit()`, which also turns
  the enemy on its attacker. After their tier's number of hits they explode
  (`features/animal_effects/`) and respawn at home 25–35 s later.
- `NetworkedEntity` replicates position/yaw continuously and alive/wind-up on
  change, so late joiners see the current state. Wind-up, hurt, attack (tracer
  and sound) and death are broadcast events. A network session change resets
  every enemy.
- Enemies use physics layer 2 like the frogs: weapons hit them but they never
  block player movement.

## Tests

`tests/features/garage_enemies/` covers the tier rules, the server's sensing,
line of sight, wind-up, damage, hits, respawn and session reset, and the
placement of every enemy on real garage floor clear of cars and columns.

Enemy posing also checks the active camera mask against the avatar surface layer.
Entering a garage resumes posing; movement, collisions, AI and replication continue
while the rig is masked. The existing 45 m animation limit remains.
