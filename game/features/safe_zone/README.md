# Safe zone

The Golden Crown is safe, as the lore and gameplay documents require. Inside a
safe zone:

- `Combat.apply_damage` ignores damage between two different players when either
  the victim or the attacker stands inside (guns, projectiles, splash, punches,
  kicks). Self-inflicted damage such as `/suicide` still applies.
- `Combat.apply_enemy_damage` rejects hostile NPC damage to a protected victim,
  without awarding player kill credit outside safe rooms.
- Held weapons (`holdables/hand.gd`) and gun-machine guns (`gun_machine/gun_rig.gd`)
  refuse to fire on the server: no shot, sound, cooldown or ammo is spent.
- Thrown props, eating, punching and kicking killable toys keep working. The
  shooting gallery (x 306, z -306) and the slums are outside every zone.

`feature.tscn` holds `SafeZone` boxes (`safe_zone.gd`); the root is at the origin,
so each `bounds` is a world AABB:

| Zone | Covers |
| --- | --- |
| GoldenCrown | casino hub, annex wings, south lobby, shops; y ≥ -3 so the B1–B5 garage below stays a combat zone |
| OperationsGarage | operations garage at z -3000, including upstairs office; matches its StreamedRoom bounds |
| PawnShop | roadside pawn/gun shop interior at z -4000; excludes exterior scenery |
| Lounge, WineCellar | the room-door rooms at z -600 |
| HotelWing, Atrium | the hotel annex at z -1400 / -1500 |

The server checks the player's current position (`SafeZone.covers_peer`), so there
is no replicated state, and late joiners, respawns and offline play need nothing
extra. Garage enemies use the hostile-NPC damage entry point, so an attack cannot
follow a returning player into a safe room. Add a box here when a new shared safe
preparation room is built.

Held and generated weapons smoothly lower over 0.2 seconds in safe rooms and raise
again on leaving. This cosmetic pose preserves the authoritative shot origin and
does not change the grip of non-weapon items.

Tests: `tests/features/safe_zone/test_safe_zone.gd`.
