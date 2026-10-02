# Food court

A casino wing east of the south corridor, reached on foot: leave the gaming floor
through the south door, walk down the corridor and turn left (east) through the
doorway marked **FOOD COURT** at (3, 0, 25). No teleports or streamed rooms.

- Hall: x 2…34, z 20…38, floor y 0, ceiling underside y 5. The live casino's
  `features/casino_hub/gridmap/shops.gd` supplies tiled floors and 2 × 5 m wood panels.
  A four-metre doorway at x 2, z 24…28 connects to the south corridor. The
  food-court feature supplies booths, signs and the poke and Wendy's stands; its old CSG room
  shell is replaced by the saved casino GridMaps. Existing warm casino lighting applies.
- İstanbul Kebab (`features/kebab_shop`) stands against the east wall facing west,
  its counter front at x ≈ 29.7, cashier at (29.8, 29.35).
- Eight booths in two rows (z 22.4 and 33.6, x 7.5…22.5) leave a 6.7 m aisle from the
  doorway to the counter. Each booth is a walnut table between two velvet benches with
  two seats each (32 seats). GPS lists **Food Court** and **İstanbul Kebab**.

## Wendy's

The red-and-cream **Wendy's** counter at (30, 0, 35) faces west, south of the
kebab shop. Follow Food Court GPS and the central aisle to the east counters;
Wendy's is on the right. Use **E / B / Circle / touch USE** for one complimentary
cheeseburger. Service is free with a single menu option because the request gave
no prices or menu. Eat with primary action (left click / right shoulder / touch
FIRE) to restore full health, just like current kebabs and poke bowls. An occupied
hand sends the burger to your backpack; a full bag refuses the order.

`wendys_stand.gd` registers Use with NetworkedInteraction and a one-second shared
counter cooldown. The server resolves the customer and rechecks range, the front
side, payload and inventory capacity before synchronous collection. No pending
payments, staff simulation or separate stock/state exist. Simultaneous customers
serialize; session changes reset the component cooldown. Disconnects and respawns
use ordinary inventory semantics. Late joiners load the static counter and receive
existing server-owned hand/backpack snapshots. Signed-in inventory uses its existing
persistence; offline inventory lives for the session.

The native scenes are the editable source: a 3 × 1.3 m counter footprint,
3.03 m sign height, +Z local customer side; the root's -90-degree yaw faces west.
Its simple BoxMesh furniture uses existing walnut, cream and brass materials.
The 28 cm burger has contiguous faceted buns, a square patty and cheese slice
(120 triangles), a one-hand Grip, and no collider in its held view.
Both reuse the approved 128px prop-grain texture with native primitive UVs and
nearest mipmaps; no new artwork, texture generation or dynamic lights.
Tests: `test_wendys_stand.gd` and the food-court capsule/floor layout tests.
Render the real level from `game/` with
`godot --audio-driver Dummy res://tests/features/food_court/wendys_probe.tscn`.
It exercises offline ordering and writes counter, first-person and third-person
captures to `/tmp/wendys-*.png`; a graphical renderer is required.

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

The small **POKE BOWLS** stand at (30, 0, 22.5) faces west, beside the kebab
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
