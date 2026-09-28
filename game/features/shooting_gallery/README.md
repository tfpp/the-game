# Shooting gallery

A Doom-style arena of killable humanoid dummies, detached from the main casino
room the way `features/elevator`'s "Back Room No. 1" is — reachable only through
its own entrance, not by walking there.

## How it works

- `portal.tscn` / `teleport_portal.gd`: a red archway, the `interactables` group's
  `can_use`/`interaction_text`/`use()` contract (`features/interaction`). Pressing
  Use calls `player.server_teleport.rpc_id(...)` — the same RPC
  `features/elevator/elevator_cab.gd` and `features/combat/combat.gd` use to move a
  player from server code — straight to `destination`, no boarding animation. One
  instance sits in the main room (`Entrance`, near the map's empty northeast
  interior) and a second sits inside the arena (`Arena/Exit`) pointed back at it.
- `Arena`: a fully enclosed room built entirely from this feature's own
  `CSGBox3D` floor/walls (no `world/` changes), positioned far from the main room
  (`x = 80`) so it can't overlap any existing feature, plus two low cover blocks
  for the "duck behind something" arena feel.
- `shooting_gallery.gd` (root): spawns six `HumanoidTarget` dummies scattered
  around the arena (not lined up in a row) through a `MultiplayerSpawner`, the same
  spawn-data pattern `features/frogs/frogs.gd` uses for its pond — every peer
  builds an identical dummy from the same data instead of syncing a body over the
  network.
- `humanoid_target.gd` / `humanoid_target_model.gd`: a boxy human built from one
  shared unit cube per limb (torso, pelvis, head, two arms, two legs, hands, feet,
  plus a painted bullseye on the chest), the same per-part scale trick
  `features/frogs/frog_model.gd` uses with a sphere. It's in the `killable` group
  with a `take_hit(attacker_peer)` method, the same contract
  `features/penguin/penguin.gd` and `features/frogs/frog.gd` use, so
  `features/holdables/hand.gd`'s hitscan and `features/gun_machine/projectile.gd`'s
  ray query both already know how to kill it — any weapon, one hit, regardless of
  its damage value. It respawns in place `RESPAWN_DELAY_S` after dying, like the
  penguin waddling back.
- `gore_splatter.gd`: an extra blood-burst effect layered on top of the shared
  `features/animal_effects/mesh_explosion.gd` flash/shockwave/limb-debris every
  killable gets — humanoid targets are the one thing in the game meant to be gibbed
  repeatedly, so they get more gore than a frog or the penguin.

## Weapons that can damage NPCs

`features/holdables/hand.gd`'s hitscan already routed non-player `killable` hits to
`take_hit`. `features/gun_machine/projectile.gd` (the AWP-style and gun-o-matic
guns' real projectiles) didn't: its ray query's collision mask excluded layer 2
(where `features/frogs/frog.gd` and this feature's dummies live), and it only ever
checked for a `Player` collider. Both are fixed in `projectile.gd` so every weapon
in the game — hitscan or projectile — can hurt every `killable`, animals included,
not just other players.
