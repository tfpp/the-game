# Roulette table

One table stands at `(-9.1, -1.25, -5.5)`, with the wheel at its west end and a dealer
(`casino_patrons/stationary_dealer.tscn`) behind it. Approach the players' (south) long
side, look at the betting layout within 3.5 metres, then press **E**, **Circle / B**, or
mobile **USE**. Menus and chat suppress interaction.

## Rounds

- Up to three players sit at fixed seats along the south side (`RouletteTable.SEATS`).
  Sitting teleports you there facing the layout; the first player to sit at an idle
  table opens a **20-second** betting round (`betting_seconds`). Others may join
  while seats and betting remain.
- Seated players spectate from their seat (`roulette_seat_view.gd`): they keep their
  own first-person view and can look around, but cannot walk. A panel shows the clock
  and their stake. **C** / controller **Y** / the Place bets button (rebindable as
  `roulette_bets`) opens the betting view; **Jump** or Leave table stands up.
- The betting view (`roulette_betting_screen.gd`) is an overhead camera over the
  layout with a rack of chips ($1, $5, $50, $100, $500, $1K, $5K, $25K). Click (tap /
  controller A) to place the selected chip on the spot under the cursor; right-click
  (X) removes a spot, and Undo (D-pad down) / Clear edit your bets. Any combination is
  allowed as long as the total stays within your wallet balance. Esc, C or B/Y returns
  to the seat view.
- Each seat has a colour (1 gold, 2 teal, 3 plum), shown as a swatch on your screens
  and as a rim under each of your stacks. When players share a spot their stacks
  shrink a little and spread out inside the box: side by side for two, a triangle for
  three, in seat order so each leans toward its owner. Hovering a shared spot lists
  everyone's bets there ("You $6.00 · Bob $55.00 · Cara $102.00").
- Leaving before the spin cancels your bets for free; once betting closes, a player
  with chips on the table stays until the ball lands. Players without bets may always
  stand up.
- When the clock runs out the bets lock and the wheel spins (3 s). In the betting
  view the camera pans over the wheel to watch the ball; from the seat you watch it
  yourself. With no bets the round simply
  ends. After the ball lands, losing chips are swept, the camera pans back to the
  layout, a gold marker shows the winning pocket and each player's bets settle; five
  seconds later every seat is released: seat-view players simply walk away, while a betting view left open keeps
  the result up until you continue or play again.
- A seated player who disconnects or ends up away from their seat (respawn, elevator)
  loses it. Unlocked bets are dropped; locked bets still settle against the account
  captured when betting closed.

Odds follow the American column of [Barboianu's roulette model](https://probability.infarom.ro/roulette.html)
(`roulette_bets.gd`). Each spin is an independent, uniform draw of the 38 pockets, so a
bet covering n pockets wins with probability n/38 and pays 36/n − 1 to 1: straight
35:1, split 17:1, street (and the 0-1-2 / 00-2-3 trios) 11:1, corner 8:1, six line 5:1,
columns and dozens 2:1, red/black/odd/even/high/low 1:1. Every one of these has the
same expected return of −2/38 (−5.26%). The page's tables leave out the American
five-number top line (0-00-1-2-3): its formula payout, 36/5 − 1 = 6.2, is not a whole
number, so it pays the standard casino 6:1 here, winning 5/38 (13.15%, 6.6 : 1) with an
expected return of −3/38 (−7.89%), the one worse bet on the layout. Hovering a spot shows its payout, e.g. "Split 17 / 20 — pays 17:1",
plus what your chips there would win if you have any, e.g. "your $6.00 wins $102.00"
(winnings on top of the returned stake). Slot machine luck buffs do not apply.

## Money

The server settles each player's round in one call,
`PlayerMoney.settle_roulette(peer, account, id, wager, payout)`: it deducts the total
wager and credits the payout (winnings plus returned stakes) atomically. Online this is
the accounts API's `roulette` action; offline and dev-auth tables use the temporary
wallets. If the wallet can no longer cover the wager the whole bet is void (no charge,
no win). Nothing moves before the ball lands, so cancelled bets cost nothing. Net wins
are announced in the chat money log; losses and void bets get a chat notice.

## Networking

`NetworkedEntity` (`networked_interaction.gd`) carries every request: `use` (sit),
`bet {spot, cents}`, `remove {spot}`, `undo`, `clear` and `leave`. The server resolves
the sender, then checks seat, phase, spot key, chip value, the 60-placement cap and
balance. Seats, names, bets, results and the wheel snapshot are one replicated `state`
dictionary; the countdown is `net_seconds_left`, so ticking seconds do not resend the
bets. Late joiners receive both on spawn. Every peer animates the wheel locally and does
not learn the winning pocket until the spin ends.

Edge cases:

- **Rate limit.** Every accepted bet edit resends the table state to all peers, so each
  player gets their own allowance for bet/remove/undo/clear: bursts of 10, refilling 8
  per second. Refused edits don't affect other players; leaving is never limited. (The
  component's built-in cooldown is shared by all players, so it isn't used here.)
- **Lost settlement replies.** If the accounts API doesn't answer, the result shows
  "settling" and the server retries the same operation ID with backoff (0.5 s up to
  10 s) until it does, instead of calling the bet void when it may already have been
  applied. Only an explicit rejection voids a bet.
- **Balance below the bets.** Bets are checked against the balance when placed. When
  betting closes, if the balance has since dropped, the newest chips that no longer fit
  go back (with a chat notice) and the rest still play. The API still rejects the whole
  settlement if the balance falls further during the spin.
- **Seat collisions.** Sitting down moves any standing (unseated) player within 0.7 m of
  that seat 1 m back from the table first.
- **Refused seats.** A refused request to sit shows why in chat: the table is full, or
  the wheel is spinning (wait for the next round).

## Layout

- `feature.tscn` places the table in the world.
- `table.tscn` is the reusable entity: collision, dealer, networking and view.
- `roulette_table.gd` owns seats, round phases, bet validation and settlement.
- `roulette_bets.gd` defines every bet spot, its pockets and payout, and maps texture
  pixels of the painted layout to table space for clicks and chip placement.
- `roulette_wheel.gd` draws the pocket, names it ("00"), maps red/black/green and
  lists the pocket order around the wheel.
- `roulette_table_view.gd` shows the table model, chips (`assets/casino_chips/`) and
  labels, animates the rotor and ball, and opens the local betting screen.
- `roulette_seat_view.gd` is the local seated spectator mode and bet-view key.
- `roulette_betting_screen.gd` is the local overview camera, chip rack and controls.
- `roulette_ui_theme.gd` skins both screens with the Golden Crown table furniture in
  `assets/roulette/ui/` (mahogany-and-felt panel, velvet plaque, cream-and-brass
  buttons, brass pointer over the selected chip); see its `GENERATED_ASSETS.md`.
- `tools/bake_chip_icons.gd` rebuilds the round chip icons from the chip textures.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another table, instance `table.tscn` under `feature.tscn` with a unique node
name and position; keep the south side clear for the seats and the north side for the
dealer. All peers must load the same scene; each instance runs its own rounds.

## Tests

GUT covers bet spots, hit-testing and payouts (`test_roulette_bets.gd`) and round flow,
validation, settlement and the betting screen (`test_roulette_rounds.gd`).
`python3 game/tests/features/roulette/network_check.py` runs a real server, two seated
bettors and a late joiner. `godot --path game res://tests/features/roulette/visual_probe.tscn`
saves screenshots of a full round to `/tmp/roulette/`.
