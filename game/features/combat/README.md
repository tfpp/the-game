# Combat

Health and kills for the weapons in `features/holdables`. Everyone starts (and
respawns) at 100 HP.

## How it works

- `combat.gd` is the server-authoritative source of truth: peer-keyed `health` and
  `kills` dictionaries, replicated to every peer like `features/smeckles`' balances.
  Nothing else in this feature spawns per player — it just tracks numbers per
  connected peer.
- A kill (`kills_for(peer_id)`) is awarded to whoever's damage brought a *different*
  peer's health to zero; self-damage (e.g. rocket splash) never counts. `features/
  leaderboard` reads `kills_for` for its Esc-menu "Kills" tab.
- Weapons deal damage by calling `apply_damage(target_peer, amount, attacker_peer)`
  on whichever node is in the `combat` group, the same cross-feature pattern
  `features/slot_machine` uses to reach `features/money`'s wallet. See
  `features/holdables/hand.gd`'s `_fire`, which hitscans from the shooter and looks
  the hit `Player`'s peer up.
- Reaching zero health heals back to full and broadcasts `player_died` at the
  death location, preserving slum loot drops and other death listeners. The victim
  sees a full-screen **u died gg** overlay for two seconds, then the server teleports
  them to the feature-owned `player_spawn` marker (the operations garage), or the
  legacy casino fallback when no marker exists, with `player.server_teleport` and broadcasts
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

## Adding a new source of damage

Call `apply_damage` on the `combat` group's node from server-only code, same as
`hand.gd` does. No changes are needed here.
