# Crouch

Press **C** (controller: right-stick click) to toggle crouching. Rebind it under
**Esc → Settings → Controls → Movement → Crouch (toggle)**. Touch controls have no
crouch button.

While crouched you move at 34% speed, your view lowers to 46 units above your feet and
the eye offset also composes with `PlayerHeight.eye_scale(player)` for ID/body
heights (including Sor); your collision capsule shrinks to 72% of its height (its bottom stays at your feet), so
you fit under low obstacles. You can't stand up while something is overhead. Crouching
while seated in a booth is ignored. Jumping works while crouched.

## Networking

Movement is client-authoritative, so the owning client applies its own speed, eye
height and capsule immediately. It then asks the server through `NetworkedEntity`
(`crouch` action, payload `{"crouched": bool}`). The server stores the flag in the
replicated `crouched` dictionary (peer → true), so everyone sees the pose and late
joiners get the current state. Only a peer with a spawned player can crouch; the
identity comes from the transport. Disconnects and session resets clear entries, and a
new local player (join or respawn) starts standing.

Other features read the state through the `crouching` group:
`is_crouching(peer)` (your own peer returns the local prediction).

- `features/player_models` switches the skinned rig to the crouch and crouch-walk
  poses (`BlockPlayerMotion.crouch_pose()`) and shrinks the collision capsule.
- `features/garage_enemies` notices crouched players at half its aggro radius
  (`GarageEnemyTiers.notice_radius()`). Enemies still see you up close, and crouching
  doesn't shake an enemy that is already chasing you.

Speed changes are ratios (`max_speed *= SPEED_SCALE`), so they compose with the gnome
tunnel speed boost.

Tests: `tests/features/crouch/`. `tests/features/crouch/crouch_probe.tscn` renders a
side-view contact sheet (`-- --avatar-capture=/tmp/crouch.png`).
