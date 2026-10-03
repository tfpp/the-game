# Safe zone

The Golden Crown is safe, as the lore and gameplay documents require. Inside a
safe zone:

- `Combat.apply_damage` ignores damage between two different players when either
  the victim or the attacker stands inside (guns, projectiles, splash, punches,
  kicks). Self-inflicted damage such as `/suicide` still applies.
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
extra. Garage enemies pass the victim as attacker; they live in the slums and
never reach a zone. Add a box here when a new shared safe preparation room is built.

Not yet done: a lowered-weapon pose or on-screen hint when a shot is refused.

Tests: `tests/features/safe_zone/test_safe_zone.gd`.
