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

### Private elevator excursions

Normal Crown elevator runs use `ZoneInstances` copies of B1–B5. The server creates
one seeded plan per group from `zone_instances/encounter_points.tscn`; point indices
and tiers travel as instance spawn data. Clients reproduce the selected plan and
receive only their instance's enemy state/events. The table below describes the
run population. The older fixed placements and P1–P3 scene have been removed.

| Floor | Run population | Total hits to clear |
| --- | --- | --- |
| B1 | 2 distant brawlers; arrival lane empty | 2 |
| B2 | 3 brawlers | 3 |
| B3 | 2 brawlers, 2 knifers | 6 |
| B4 | 1 brawler, 2 knifers, 1 gunman | 8 |
| B5 | 1 knifer, 5 gunmen | 17 |

Base tiers remain brawler 1 hit/8 damage/0.4 s windup, knifer 2 hits/18 damage/
0.25 s windup, gunman 3 hits/15 damage/0.6 s windup. B5 instance enemies use 1.5x
damage and 0.75x windup: knifers deal 27 with a 0.1875 s windup, gunmen deal 22.5
with a 0.45 s windup. Earlier floors and shared development enemies keep the base
profiles. Hit counts, movement and dodge rules remain unchanged. A seven-round pistol magazine covers the top floor; the lower
floors put a lone pistol user under reload pressure; faster guns and group support
reduce that exposure. The population progression is the Phase 1 difficulty tuning.

The controlled real-map weapon exercise uses seed 73021, active enemy AI, actual
hitscans, firing cooldowns and magazine reloads. B1 clears with two pistol shots,
no reload and 100 HP. B5 requires 17 hits to clear: the exposed pistol run dies
after four enemies, 12 shots, one reload and 4.55 simulated seconds. The M4A4
clears all six in 1.66 seconds, without reloading, and finishes at 100 HP.
Times include scripted reposition settling, not player
travel or aiming time. The fixture auto-aims and places the player six metres from
each encounter; it verifies weapon/reload pressure, not a manual skill assessment.
`tests/features/zone_instances/test_garage_weapon_pressure.gd` preserves this check.
The fixture stops on the actual death event, since Combat resets health during
respawn. B1 remains approachable while B5's five ranged enemies punish exposed
reloads. This verifies a stronger weapon can clear the encounter that defeats the
exposed pistol strategy; it does not claim that skilled movement makes pistol-only
runs impossible.

Each floor has four searchable supply crates with its own independent `LootTable`.
Expected value per crate rises from about $2.44 (B1) to $3.82/$6.02/$16.48/$23.78.
Loot weights shift from scrap/wallets to watches/jewelry. Instances begin with fresh
containers; their RNGs are seeded independently by floor/point. Tests verify
marker floor support, unique enemy positions, reproducible plans, increasing
expected value and fresh loot without resetting other runs.

Private enemies live under `SlumInstance/Map/CrownGarage/Enemies`, using authored
deck coordinates (deck `i` at `y = 4i`, B5 at the bottom). Spawn markers occupy
the front (z < 8) and back (z > 34) lanes reserved from set pieces.

`net_yaw` is stored in the parent's space (`_parent_direction`) so enemies under
the rotated basement face where they walk.

## How it works

- The server simulates each `GarageEnemy` (`garage_enemy.gd`). Every 0.2 s it
  looks for the nearest visible player on its own floor within its aggro radius
  and leash (half the aggro radius for crouched players, see `features/crouch`;
  a target already being chased stays noticed), walks towards them (gunmen stop at half range), raises its arms for
  a short wind-up and then strikes. Melee needs the target still in reach; a
  gunman's shot needs line of sight and misses fast-moving targets more often.
  Enemies never follow players off their floor area, and idle enemies skip
  sensing while nobody is within 30 m.
- Damage goes through `features/combat`'s `apply_enemy_damage`, respecting safe
  zones without player kill credit; `features/slum_runs` then drops the
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

Hostile body materials opt into `minimum_light = 0.3` in the shared human surface
shader. This adds a texture-colored light floor, including a small minimum for
black tactical fabric, so enemy silhouettes remain visible in the dark garage.
The shader's default is zero. Actual private-map captures review brawlers and
gunmen at five and twelve metres; the fill adds no lights or draw calls.
