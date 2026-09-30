# Penguin couple

Two decorative penguins waddle slow circles in the west petting parlor
(`features/casino_hub`), beside the frogs and their pond.

- `penguin.tscn` is one reusable penguin: an `AnimatableBody3D` in the `killable`
  and `penguins` groups, server-authoritative like the rest of shared state. The
  server advances the patrol angle and replicates `net_position`/`net_yaw`/
  `net_alive`; clients only smooth toward them. The patrol math is pure static
  functions in `penguin_waddle.gd` so it's unit-testable.
- `feature.tscn` instances it twice: the original `Penguin` at (-26, 0.4, 8) and
  his `Wife` at (-23.8, 0.4, 12.3) (clear of the bench row along x -21),
  smaller, with a pink bow and blush. Exports:
  `display_name` (used by `features/gps` for its Animals label), `is_wife` (shows
  the bow) and `start_angle` (patrol phase). The wife starts half a lap out of
  phase, so the two circles — same radius, same speed — bring the couple
  beak-to-beak and apart again instead of holding a constant distance.
- Reactions are cosmetic and computed independently on every peer from replicated
  state, so they need no RPCs: a nearby player wearing the "penguin" body model
  gets a flipper wave and excited hops, and so does either penguin while its
  spouse is within `PenguinWaddle.COUPLE_RADIUS`.
- Any weapon kills either penguin (`take_hit` via the hitscan in
  `features/holdables/hand.gd`): one hit, an explosion on every peer, and a
  respawn at home a few seconds later, back at `start_angle` so the couple's
  phase relationship survives death.

Tests live in `tests/features/penguin/`: `test_penguin.gd` (kill/respawn and the
player reaction), `test_penguin_waddle.gd` (patrol math), `test_penguin_wife.gd`
(the wife and the couple reaction) and `test_penguin_placement.gd` (both patrol
circles against the real parlor collision).

Note for tests: an `AnimatableBody3D`'s transform set is unreliable outside the
physics step in headless runs, so tests freeze physics and assert on the
replicated plain vars (`net_position`, `net_yaw`, `net_alive`) instead of the
body transform.
