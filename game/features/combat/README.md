# Combat

Health and kills for the weapons in `features/holdables`. Everyone starts (and
respawns) at 100 HP.

## How it works

- `combat.gd` is the server-authoritative source of truth: peer-keyed `health` and
  `kills` dictionaries. `HealthSpawner` creates one `CombatHealthState` per peer;
  its NetworkedEntity snapshot is visible only to the owner and their current
  group. Joining a group receives current HP; leaving revokes the old snapshot.
  Kill totals remain public for the existing leaderboard.
- A kill (`kills_for(peer_id)`) is awarded to whoever's damage brought a *different*
  peer's health to zero; self-damage (e.g. rocket splash) never counts. `features/
  leaderboard` reads `kills_for` for its Esc-menu "Kills" tab.
- Weapons deal damage by calling `apply_damage(target_peer, amount, attacker_peer)`
  on whichever node is in the `combat` group, the same cross-feature pattern
  `features/slot_machine` uses to reach `features/money`'s wallet. See
  `features/holdables/hand.gd`'s `_fire`, which hitscans from the shooter and looks
  the hit `Player`'s peer up.
- Reaching zero health heals back to full and sends `player_died` to the group at the
  death location, preserving slum loot drops and other death listeners. The victim
  sees a full-screen **u died gg** overlay for two seconds, then the server teleports
  them to the feature-owned `player_spawn` marker (the Crown, `crown_spawn`), or the
  legacy casino fallback when no marker exists, with `player.server_teleport` and sends
  `player_respawned(peer_id)`. Further damage to that victim is ignored during the
  delay, preventing duplicate deaths/kills. Pending respawns are server-only and
  cancelled on disconnect/session reset; no death history is replayed to late joiners.
- The overlay blocks gameplay through `modal_ui` without releasing mouse capture,
  so browser respawns don't need a pointer-lock gesture. It works automatically on
  keyboard, controller and touch, including offline play; no button is required.
  Existing menus/focus pauses are not forcibly closed or resumed. `/suicide` (or
  `/sucide`) in chat uses this same death lifecycle, including in offline previews.
  World fall recovery remains an instant rescue, not a combat death. Existing
  combat death penalties and kill credit are unchanged.
- `combat_hud.gd` also shows the local player's own HP as a UI Pack - Space
  Expansion bar in the bottom-right corner, the one corner `game/ui/hud.gd`'s corner layout leaves free.

`is_respawning(peer_id)` exposes the server countdown without modifying health or
owning another death timer. The operations van uses it to reject travel during the
death screen. Its optional `player_spawn` marker uses the same existing ±3m jitter
as initial joins and fall recovery; marker ownership remains with `starter_room`.

## Safe zones

Damage between two different players is ignored while either stands in a
`SafeZone` (`features/safe_zone`), so the Golden Crown stays peaceful.
Damage is also rejected between different excursion groups, including damage from
a hosting player. Hostile NPCs call `apply_enemy_damage`, which checks the victim's
safe zone while preserving the no-player-kill-credit rule. Deliberate self-damage
continues to use `apply_damage` so `/suicide` remains available.

## Adding a new source of damage

Call `apply_damage` on the `combat` group's node from server-only code, same as
`hand.gd` does. No changes are needed here.
