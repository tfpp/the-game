# Food court

The food court occupies the former Jump Lounge in the southeast casino corner.
Walk east from the south lobby; no corridor or teleport is needed.

- Court: x 13…34, z 21.2…34, floor y 0. The existing casino supplies the outer
  walls, ceiling and lighting; a tile inset marks the dining area.
- İstanbul Kebab (`features/kebab_shop`) stands against the east wall facing west,
  with its cashier at (29.8, 29.85).
- Eight booths in two rows (z 23 and 32, x 14.5…26.5) retain all 32 seats and
  leave a central aisle to the counters. GPS lists **Food Court** and **İstanbul Kebab**.

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

## Poke bowls

The small **POKE BOWLS** stand at (30, 0, 23) faces west, beside the kebab
shop. Follow the existing Food Court GPS marker, then continue toward the east
counters. Use (E / B / Circle / touch USE) opens a menu with six tip buttons:
15%, 20%, 25%, 30%, 35%, 40%. Each button buys one $29 salmon, rice and avocado
bowl, showing the complete total ($33.35–$40.60). Close without choosing to cancel.
Use primary action (left click / right shoulder / touch FIRE) to eat the equipped
bowl. Like kebabs, it has no extra healing or buff; inventory can store/drop it.
A fresh $20 wallet needs more money before ordering.

`poke_stand.gd` uses NetworkedInteraction for Use and the `order {tip: int}` action.
The server resolves the sender, checks the customer side/range, allowed tip,
inventory capacity and one outstanding payment per buyer. It computes the total
in cents and calls PlayerMoney.charge. Other players can order independently.
The synchronous apply callback starts asynchronous wallet work without yielding.
Successful payment collects the FOOD item through PlayerInventory; if the bag
fills or the buyer disconnects during payment, the normal holdables spawner leaves
one public bowl pickup beside the counter. A respawn keeps normal inventory delivery;
a session reset ignores stale completions. Purchases have a one-second per-peer
cooldown, and menu buttons disable after choosing to avoid accidental repeats.

The counter is static on every peer. Held/backpack bowls and fallback pickups
use existing server-owned replication, including late joins. Authenticated money
persists normally; bowls have ordinary session inventory/pickup lifetime. No new
persistent state, bindings, lights or NPC simulation. `poke_menu.gd` is local modal
UI with keyboard/controller focus, touch-sized buttons and Esc/Close dismissal.
