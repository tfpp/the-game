# Food court

The dining plaza in the [Crown Strip Mall](../strip_mall/README.md), reached by
using the **STRIP MALL / FOOD SHOPS** door on the left of the south casino corridor
at (1.8, 1.25, 25). E / controller B or Circle / touch USE travels there; the
return kiosk behind the arrival point leads back to the Crown.

- Feature root (0,0,-5000). All booth/counter coordinates below are local.
  The strip_mall feature supplies saved GridMap paving, storefront bays, roofs,
  awnings and parking. The dining plaza is open air, with floor y=0.
- İstanbul Kebab (`features/kebab_shop`) faces west beside the other counters;
  its cashier's customer-side floor point is globally (28.7,0,-4970.65).
- Eight booths in two rows (z 22.4 and 33.6, x 7.5…22.5) retain their original
  footprints and all 32 seats. Walk along the central aisle, then x=26 to the
  counters. GPS retains **Food Court** and **İstanbul Kebab**, and adds the mall,
  Poke Bowls and Wendy's.
- This feature and its NetworkedEntity stay loaded independently of streamed
  mall Content. Menus, prices, food delivery and seating state are unchanged;
  all distance checks and seat positions continue to use global coordinates.

## Wendy's

The red-and-cream **Wendy's** counter at (30, 0, 35) faces west, south of the
kebab shop. These are local coordinates in the mall. Follow Food Court GPS and the central aisle to the east counters;
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

### Casino furniture

The same owner now registers 25 casino seats: six lounge chairs, two couch
places, five main-floor bar/cocktail stools, nine card-table chairs and three
stools at the upstairs Mariachi Balcony Bar. Use (E / B / Circle / touch USE)
sits or stands; movement or Jump also stands, including queued touch jumps.
While seated, the body stays facing the chair's authored heading and only the
head follows look yaw/pitch. Camera and replicated aim stay independent; the
avatar derives body heading through `seated_yaw(peer)` (NAN when standing), so
other players and late joiners see the same fixed body facing.
Decorative card guests yield their chair while occupied and return afterward.
Staff/dealer positions and Vivienne's quest stool remain reserved.

Placement scenes author `booth_seat.gd` anchors in `casino_seats`, on each
cushion, with local -Z facing forward. `casino_seat = true` selects an authored
`exit_offset` to a clear floor point; `seat_label` customizes the existing prompt.
Optional `guest_path` temporarily hides a decorative guest without changing its
networked alive state. Assets themselves remain reusable static props.

FoodCourt gathers these static anchors once at startup, sorted by full node
path, after the room and earlier features load. It appends them after the original
32 booth indices. Keep anchors outside streamed content and available before
food_court loads; do not insert/remove them during a session. The single
`net_seats` snapshot, validation, `seating/is_seated(peer)`, local pinning,
disconnect/death/teleport and session cleanup cover both areas unchanged.
No duplicated occupancy, new RPC, binding, persistence or avatar query exists.

Regression tests include every casino exit's floor/capsule clearance, balcony
facing/height, competing occupants, decorative guest presentation and pose.
Run `bash tests/features/food_court/network_test.sh` from game/ for a real
WebSocket visitor, late visitor, denied seat theft and replicated stand.
With a display, run `godot --audio-driver Dummy
res://tests/features/food_court/capture.tscn` for native lounge/card/balcony renders
at `/tmp/casino-seat-*.png`.

## Poke bowls

The small **POKE BOWLS** stand at (30, 0, 22.5) faces west, beside the kebab
shop (local mall coordinates). Follow the existing Food Court GPS marker, then continue toward the east
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

The service also supports scene-authored `price_cents`, `menu_title`, `food_label`
and `tip_choices`; `order_total()` computes that instance's total. Defaults retain
the Poke menu and `total_cents()` remains the original static $29 helper. The Strip
Mall's two rival counters reuse this service with a single zero-tip choice and
independent prices. All three sell the existing `poke_bowl`, with the same validated
server payment/delivery implementation and local menu, not parallel shop logic.

The counter is static on every peer. Held/backpack bowls and fallback pickups
use existing server-owned replication, including late joins. Authenticated money
persists normally; bowls have ordinary session inventory/pickup lifetime. No new
persistent state, bindings, lights or NPC simulation. `poke_menu.gd` is local modal
UI with keyboard/controller focus, touch-sized buttons and Esc/Close dismissal.
