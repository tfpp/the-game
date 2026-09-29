# Food court

A casino wing east of the south corridor, reached on foot: leave the gaming floor
through the south door, walk down the corridor and turn left (east) through the
doorway marked **FOOD COURT** at (3, 0, 40). No teleports or streamed rooms.

- Hall: x 3.5…33, z 35…51, floor y 0, ceiling at y 5.5. The north wall is the casino's
  south outer wall; the west wall is the annex corridor (`features/annex`, which owns
  the `FoodCourtDoorway` cut). Four `wall_sconces` light it at night.
- İstanbul Kebab (`features/kebab_shop`) stands against the east wall facing west,
  its counter front at x ≈ 29.7, cashier at (29.8, 44.35).
- Eight booths in two rows (z 37.4 and 48.6, x 7.5…22.5) leave a 6.7 m aisle from the
  doorway to the counter. Each booth is a walnut table between two velvet benches with
  two seats each (32 seats). GPS lists **Food Court** and **İstanbul Kebab**.

## Sitting

Walk up to a bench and press Use (E, controller B/Circle, touch USE) on "Sit in the
booth". Press Use again, Jump or move to stand up; you step out at the open end of
the bench. You can look around and eat while seated.

`food_court.gd` owns `net_seats` (occupant peer per seat, 0 = free), replicated by its
`NetworkedEntity` (`networked_interaction.gd`). Clients request `sit {seat}` and
`stand`; the server checks the sender's player, payload, reach (1.8 m) and that the
seat is free. Seats free on stand, disconnect, death (`combat.player_died`), session
reset, or when the seated player ends up more than 3 m away (respawn, kill plane).

Movement stays client-authoritative: the owning client pins its own player to the seat
(physics off, like the ferry helm) and publishes that position. If something else moves
the player, it lets go and asks to stand. `is_seated(peer)` (group `seating`) lets
`BlockPlayerModel` show the seated pose on every peer, including late joiners.

Nothing is persisted. Tests: `tests/features/food_court/`.
