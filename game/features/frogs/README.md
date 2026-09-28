# Frogs

Six server-spawned frogs explore the level. Each spawn carries a fixed skin color,
size, hop distance, height, duration, and idle interval to every peer, including
late joiners. The model uses low-poly meshes, separate skin materials, spotted
backs, webbed feet, and animated hind legs. The server synchronizes position,
facing, hop phase, and alive state; clients only smooth and animate these values.

## Movement

`frog.gd` owns the behavior and collision body. Players within 5 meters start an
escape; frogs calm down after players leave a 7-meter radius. Escapes have longer,
faster hops and shorter pauses. Players more than 2.5 meters above or below a frog
do not startle it.

`frog_navigation.gd` steers each hop against live layer-1 world collisions. It tries
forward and progressively wider turns, with shorter hops when needed. Five ground
probes reject unsupported landings, narrow ledges, steep slopes, rises over 0.65
meters, and drops over 1 meter. Sphere sweeps along the arc reject walls and low
ceilings. A CharacterBody3D stops a hop if an obstacle moves into its path, then
settles onto the floor before trying again. Frogs do not block player movement.

This is local obstacle avoidance, not destination pathfinding through a maze.
Frogs wander without a spawn-radius leash; when completely trapped they wait and
retry. The existing penguin follows a fixed circle and there is no shared level
navigation system, so this helper belongs to the existing frogs feature.

## Hits and respawns

Any weapon can hit a frog. The server handles a single fatal hit, broadcasts the
same flash, shockwave, and flying model pieces as the penguin, and respawns the
frog at its original location after four seconds. Its color, size and hop profile
stay unchanged. Dead frogs stop moving and have no active collision shape.
Late joiners receive the alive state without replaying an old explosion.

Frogs use physics layer 2, included in weapon hitscans but excluded from player
movement. Shared cosmetic effects live in `features/animal_effects/`; debris
retains each frog's materials and clears itself after the animation.

## Verification

Run `harness/verify.sh` from the repository root. Focused GUT tests live in
`tests/features/frogs/` and cover hop math, individual profiles, safe landings,
walls, ceilings, steps, escape behavior, live obstruction, and spawn appearance.
