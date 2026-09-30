# Garage enemies

Hostile scavengers that haunt `features/parking_garage/`. `feature.tscn` sits at
world `(0, 0, 600)`, the same origin as the garage's `Garage` node, so every
enemy's position is in garage-local coordinates.

Players arrive on P1 through the employee door and climb, so danger rises with
each floor away from the door (the design's "deeper" direction for this
three-level garage):

| Floor | Enemies | Tier traits (`enemy_tiers.gd`) |
| --- | --- | --- |
| P1 | 3 lurkers | 1 hit, slow melee claw (10 dmg) |
| P2 | 2 lurkers, 2 gunmen | gunman: 2 hits, fires from 14 m (12 dmg), keeps its distance |
| P3 | 2 gunmen, 3 stalkers | stalker: 3 hits, fast melee (20 dmg) |

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
