# Boxing

Bare-knuckle punching for anyone with nothing in hand. **Click** (left mouse or
controller RB, the `primary_action` that fires held weapons) to **jab**; **hold and
release** the click to throw a **power punch**, stronger the longer you hold (full
strength after 1 s). While you wind up, your fists draw back and shake in front of
you; every player sees the fists of whoever throws a punch.

## How it works

- `boxing.gd` (feature root, one node on every peer) sends `request_wind_up` on
  press and `request_punch` on release. The server times the hold itself, rejects
  punches from peers holding an item (`Hand.for_peer`) or an active gun rig
  (`GunRig.for_peer`), and applies a per-peer cooldown (0.3 s jab, 0.6 s power).
- The hit is a 2 m ray from the eye along the aim, falling back to a small sphere at
  the end of reach so a dummy lying at your feet is easy to hit.
- What a punch does depends on the target:
  - anything with `take_punch(attacker_peer, strength, direction)` handles it
    itself; the shooting gallery's dummies (`features/shooting_gallery`) daze,
    ragdoll and get knocked away, and so do the walking casino patrons
    (`features/casino_patrons`);
  - players take `strength × 25` damage through `features/combat`'s `apply_damage`;
  - other `killable`s (frogs, the penguin, the soccer ball) take a `take_hit` from
    power punches only.
- `boxing_math.gd` holds the pure rules: a jab is strength 0.25, a power punch
  0.5–1.0. `boxing_fists.gd` is cosmetic only.
- Nothing is persisted; wind-ups and cooldowns are cleared on disconnect.

Touch players punch with the Attack button (hold and release for power punches).

`Boxing.arm_pose(peer)` exposes only the current accepted cosmetic swing (power
and reach), or an empty dictionary at rest. The player avatar layers the swing
over locomotion, bends both arms and closes its fingers; penguin flippers use the
same pivots. The floating fist feedback is now first-person only. No extra RPCs
or persistence are needed: accepted swings already broadcast to every peer, and
late joiners start at rest rather than replaying old punches.
