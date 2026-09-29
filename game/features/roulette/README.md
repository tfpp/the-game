# Roulette table

One table stands at `(-9.1, -1.5, -5.5)`, with the wheel at its west end and a dealer
(`casino_patrons/stationary_dealer.tscn`) behind it. Approach the players' (south) long
side, look at the betting layout within 3.5 metres, then press **E**, **Circle / B**, or
mobile **USE**. Menus and chat suppress interaction.

## Rounds

- Up to three players sit at fixed seats along the south side (`RouletteTable.SEATS`).
  Sitting teleports you there facing the layout; the first player to sit at an idle
  table opens a **one-minute** betting round (`betting_seconds`). Others may join
  while seats and betting remain.
- Seated players get the betting screen (`roulette_betting_screen.gd`): an overhead
  camera over the layout and a rack of chips ($1, $5, $50, $100, $500, $1K, $5K, $25K).
  Click (tap / controller A) to place the selected chip on the spot under the cursor;
  right-click (X) removes a spot, and Undo / Clear edit your bets. Any combination is
  allowed as long as the total stays within your wallet balance.
- The screen is modal, so seated players cannot move. Leaving before the spin cancels
  your bets for free; once betting closes, a player with chips on the table stays until
  the ball lands. Players without bets may always stand up.
- When the clock runs out the bets lock and the wheel spins (3 s). With no bets the
  round simply ends. After the ball lands, losing chips are swept, a gold marker shows
  the winning pocket and each player's bets settle; five seconds later every seat is
  released. The result stays on the local screen until you continue or play again.
- A seated player who disconnects or ends up away from their seat (respawn, elevator)
  loses it. Unlocked bets are dropped; locked bets still settle against the account
  captured when betting closed.

Bets and payouts are American roulette (`roulette_bets.gd`): straight 35:1, split 17:1,
street and the 0-1-2 / 00-2-3 trios 11:1, corner 8:1, top line (0-00-1-2-3) 6:1, six
line 5:1, columns and dozens 2:1, red/black/odd/even/high/low 1:1. Each spin is an
independent, uniformly random pocket; luck buffs for the slot machine do not apply.

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
- `roulette_betting_screen.gd` is the local overview camera, chip rack and controls.
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
