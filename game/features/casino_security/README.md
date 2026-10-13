# Casino security (#547)

Three buff bouncers keep the peace in the Golden Crown's main hall. They stand
watch with their arms crossed: a dark tee with SECURITY across the back, shades,
an earpiece and a gold badge. Cause trouble and the nearest free guard jogs over,
slings you over one shoulder, carries you to the casino's METRO elevator in the
south wall, calls the cab and throws you in. You land on a random metro platform;
any metro elevator brings you back up.

| Post | Where | Faces |
| --- | --- | --- |
| Guard0 | north promenade, beside the excursion elevator and spawn (-4.6, 0, -17.6) | south |
| Guard1 | south promenade, west of the metro elevator (-15.2, 0, 17.8) | north |
| Guard2 | east promenade (19.5, 0, 3.5) | west |

## What counts as trouble

All of it is detected on the server by the feature that already handles the act,
only while the offender stands in the main hall (`SecurityRules.HALL`: the
promenade and gaming pit, x -23.6…23.6, z -19.6…19.6, below the balcony).

| Offence | Caught by |
| --- | --- |
| Brandishing a firearm | trying to shoot a held gun (`holdables/hand.gd`) or a gun-machine gun (`gun_machine/gun_rig.gd`) inside the safe zone; the shot is still refused |
| Assaulting a guest | a punch or kick landing on another player, a roaming patron or a posed casino character (`boxing` `landed` signal); the safe zone still blocks the damage |
| Picking a fight with security | punching or kicking a guard (`CasinoGuard.take_punch`) |
| Spray-painting the Golden Crown | a spray decal placed in a safe zone (`spray` `sprayed` signal) |

Kicking the soccer ball, eating, drinking and throwing props are fine. These
offences are made up for the request ("make up bad stuff"); add another by
listing it in `SecurityRules.OFFENCES` / `CALLOUTS` and calling
`CasinoSecurity.report(self, peer, &"offence")` from server code.

## What happens

1. **Held:** "SECURITY! Stay where you are." Your own client keeps you on the
   spot (you can still look around; server teleports still apply). The guard
   says why, as a subtitle only you see.
2. **Carried:** within grabbing reach (1.5 m, including someone standing on a
   table) the guard lifts you over the right shoulder in one second, belly down,
   head and arms hanging down the back, and walks to the metro doors. Your
   capsule rides the shoulder; first person looks out from your dangling head.
3. **Thrown:** the guard presses the call button, waits up to 2.5 s for the doors
   and heaves you in. You somersault through the doorway; the screen fades.
4. **Landed:** `MetroService.deliver()` loads a random station and drops you in a
   lane beside one of its tracks (`BoozeRules.wake_spot`), facing along the
   platform: "Thrown out for: …". Inventory is untouched; whatever you held is put
   in your backpack before the lift.

Everyone sees the same lift, carry and throw, including late joiners. A fourth
offender waits (up to 20 s) for a guard to come free. A guard that can't reach
someone within 25 s, or whose offender leaves the hall while held, dies,
disconnects or blacks out (booze takes precedence), lets go and walks back. If the
metro can't take you within 30 s you are put down outside its doors.

## Multiplayer and ownership

- `CasinoSecurity` (`casino_security.gd`, group `casino_security`) is the server
  owner of every detention. Its `NetworkedEntity` replicates `detentions`
  (peer → [guard index, offence, phase]) on change and to late joiners; the
  owner-only `say` and broadcast `thud` events are transient. It registers no
  client actions, so clients can't start, change or end a detention.
- `report_misconduct(peer, offence)` (server) validates the offence, the player,
  the hall, respawns and blackouts, and queues/dispatches. The static
  `CasinoSecurity.report(caller, peer, offence)` finds the instance sharing the
  caller's multiplayer.
- `CasinoGuard` (`guard.gd`/`guard.tscn`) is a static, server-walked layer-2
  `AnimatableBody3D` (players pass through, punches land). Its NetworkedEntity
  sends `net_position`/`net_yaw` continuously and `net_state`/`net_carrying` on
  change. `GuardModel` reuses `PatronModel`/`BlockPlayerModel` with bone scales
  for the build; no new meshes, textures, lights or sounds.
- `SecurityGrid` (`security_grid.gd`) is the guards' walkable map: 0.5 m cells
  probed from the hall's real collision on the server (a down ray for the floor,
  a guard-sized cylinder for clearance, players excluded), 96 cells per physics
  tick about a second after loading, then 8-neighbour links. Routes are A* with
  straight-leg smoothing, so guards use the ramps and walk around slots, tables
  and booths. A route takes a few milliseconds and only runs on dispatch.
- Presentation (every peer, after avatars animate) places the carried or thrown
  `Player/Body` from the guard's drawn transform; the offender's `SecurityView`
  pins their client-authoritative capsule there, so `Player/Sync` shows everyone
  the same thing. Guards pose only within 40 m of the camera, at 10 Hz while
  standing watch; dedicated servers skip posing.
- Nothing persists. Disconnects, deaths and session resets clear detentions.

Shared interfaces added for this: `Boxing.landed(attacker_peer, target)`,
`Spray.sprayed(peer_id, point)` (and the `spray` group), and the two
`CasinoSecurity.report` calls in the hand and gun rig refusal paths.

## Checks

GUT: `tests/features/casino_security/` (rules, grid, detention flow, the real
metro throw, hooks into the existing features, presentation, ENet replication and
the live-hall layout). Rendered review (needs a display):

```sh
godot --audio-driver Dummy --rendering-method gl_compatibility --resolution 1100x750 \
  res://tests/features/casino_security/security_visual_probe.tscn -- --offline
```

It runs a real detention and writes `/tmp/security-<moment>.png`.
