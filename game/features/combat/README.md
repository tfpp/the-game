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
- Reaching zero health heals back to full and teleports the player to a fixed point
  near the room's spawn (`player.server_teleport`, the same RPC `core/game/game.gd`
  uses for the world's kill-plane respawn) and broadcasts `_announce_death` so every
  peer's `combat_hud.gd` can react — the victim sees a "You died" flash.
- `combat_hud.gd` also shows the local player's own HP as a UI Pack - Space
  Expansion bar in the bottom-right corner, the one corner `game/ui/hud.gd`'s corner layout leaves free.

## Adding a new source of damage

Call `apply_damage` on the `combat` group's node from server-only code, same as
`hand.gd` does. No changes are needed here.
