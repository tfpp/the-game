# Boxing

Bare-knuckle punching for anyone with nothing in hand. **Click** (left mouse or
controller RB, the `primary_action` that fires held weapons) to **jab**; **hold and
release** the click to throw a **power punch**, stronger the longer you hold (full
strength after 1 s). While you wind up, your fists draw back and shake in front of
you; every player sees the fists of whoever throws a punch.

## Kicking

Press **X** to kick; hold and release for a stronger kick, reaching full charge
at **1 second**, just like punching. Change **Kick (hold to power kick)** in
**Esc → Settings → Controls → Items**; the existing binding store persists it.
Kicking works with items or guns in hand. Punches and kicks share a cooldown
(0.3 s quick, 0.6 s charged), reach (2 m), strength and target reactions.
Aim at the target; charged kicks can knock down or shove gallery dummies/patrons,
hurt players through Combat, and hit other killables (including the soccer ball).
Quick kicks use jab rules, so generic `take_hit`-only targets require a charged kick.
There is no new casino safety policy: this retains the shipped punching/combat rules,
which do not yet implement the design documents’ casino-wide safe-zone restriction.

First person shows a matching right leg/foot drawing back and snapping forward;
third person and other players see the avatar’s right leg kick, including penguin
feet. `Boxing.leg_pose(peer)` exposes only server-accepted transient swings;
late joiners start at rest, and target state remains owned/replicated by its feature.
Death, respawn, disconnect and session changes clear pending melee charges/cosmetics.
Menus or focus/device resets cancel local charge instead of releasing a hidden kick.
No gameplay state is persisted. Controller players can assign a button on the
Controls page; no unused standard button is available for a conflict-free default.
Touch-only players have no Kick button (an attached keyboard/controller can use it);
the existing Attack button still punches.

## How it works

- `boxing.gd` (feature root, one node on every peer) sends `request_wind_up` on
  press and `request_punch` on release. Both take an optional `kicking: bool = false`,
  preserving existing punch callers; `punch(peer, held_s, kicking = false)` is a
  server-only direct entry point. Kick RPC releases require a matching accepted
  press, and never accept a duration, target, damage or player identity payload. The server times the hold itself, rejects
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
same pivots. First-person feedback uses the same skinned human asset and finger
bones as held items, matching skin, build and sleeves (including costume sleeve
color). Camera-space shoulder and wrist IK keeps the arms connected during jabs,
power swings and charge draw-back; the non-arm surface is masked out. No extra RPCs
or persistence are needed: accepted swings already broadcast to every peer, and
late joiners start at rest rather than replaying old punches.
