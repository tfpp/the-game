# Wandering Bird

A decorative wandering bird that continuously flies between the active player,
other players, and casino floor NPCs (patrons).

## Behavior and Movement

- Starts by flying to the active player.
- Upon reaching a player or NPC, the bird rests briefly near their shoulder,
  chirping and gently resting its wings.
- When ready to move, it randomly picks its next destination from:
  - other players and all NPCs when currently with a player
  - all players and other NPCs when currently with an NPC
- Flight between targets follows a parabolic arc (`bird_flight.gd`) with banking
  turns, dynamic pitch, and wing flapping.
- If no players or NPCs are active yet, the bird loops between scenic fallback perches
  around the casino floor.
- Server-authoritative: the server calculates target selection and flight kinematics,
  synchronizing position, yaw, pitch, roll, flying state, and alive state via
  `MultiplayerSynchronizer`. Non-authoritative peers smoothly interpolate remote positions
  and render flapping wings.

## Hits and Respawns

- Belongs to the `killable` group like the penguin and frogs. Any weapon can hit it.
- A fatal hit triggers a cosmetic explosion (`MeshExplosion`) and disables collision.
- The bird respawns after four seconds, taking flight toward the active player or
  a target candidate.
