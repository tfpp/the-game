# Crown Turf Club

Horse betting occupies the **east casino promenade**, at `(23.3, 0, -5)`.
GPS → Places → **Horse Betting** leads to its terminal. Look at the small monitor
below the large display and use **E / B / Circle / touch USE**. Choose a horse and
$1, $5 or $10, then **Place ticket**. Close the form to watch the wall display;
use the terminal again to read all tickets and results. Standard UI focus supports
controllers; the scrollable form scales to physical phone pixels, like Inventory.
There is no new key, seat lock or player teleport.

## Rules and authority

- Four horses, each with an independent identically distributed finish time and
  a **25%** chance to win. The total winning return is **4× stake**, including the
  original stake (3:1 profit). No slot luck/charisma bonuses apply.
- The first **accepted ticket**, not opening the form, starts exactly **15 seconds**
  of betting. Later tickets never restart the clock. Each player gets one immutable
  ticket per round. No cancellations or edits.
- Betting closes before the server samples finish times. A 12-second pixel race
  shows four galloping horse/jockey silhouettes, lane numbers, finish lines and
  changing positions. The winner is the first to cross. The result stays at least
  eight seconds; unresolved wallet settlements keep the round closed until resolved.
  The previous result remains visible while idle until the next ticket opens a race.
- `HorseBetting` is the sole owner of phases/tickets/simulation/settlements.
  `NetworkedInteraction` resolves senders and replicates the dictionary snapshot,
  whole-second countdown and 10 Hz progress. Late joiners receive all three fields.
  Client requests contain only horse, allowed stake and observed round, never peer,
  winner or payout; server checks presence, range, aim, ray visibility, phase,
  duplicate ticket and current wallet balance again. Spoofed/stale requests fail.
  `ticket_round()` targets the upcoming round while idle, so simultaneous first
  tickets agree on one round without restarting its clock.
- Payment uses **PlayerMoney.settle_roulette()**, the existing atomic, server-only
  wager/return API, not a second wallet. Wagers are charged at the result, just like
  roulette. Spending the balance elsewhere can void a ticket without charge or
  prize. UI explicitly explains this; no reservation balance was introduced.
  Lost replies retry the same random operation ID with 0.5–10-second backoff.
  Account settlement survives disconnect within the server session. Temporary
  wallets never settle into a replacement player with the same peer ID.
- Walking away/respawning does not cancel a ticket. Disconnect before lock removes
  it, but never extends the clock. Locked account tickets still settle. Network
  session changes reset the race and invalidate pending callbacks. Race history is
  server memory and resets on restart/redeploy; committed account money retains
  the wallet's existing persistence. Offline play uses the same server path.

## Presentation and integration

Reuse the casino-props security monitor's existing mesh/material for the 6 m wall
broadcast and small terminal, and the street-props wooden crate as its 0.7975 m
pedestal. Terminal base meets pedestal top; the broadcast clears the terminal.
The screen uses a **128×128** SubViewport (nearest filtered), with world Label3Ds
for readable text. No new model/painted texture, dynamic lights, interior geometry,
shared scene wiring or protected paths. Only nearby clients redraw the broadcast
(40 m, 10 Hz); a dedicated server never renders it. The GPS marker belongs to this
feature, using the existing destination contract. The lounge at z 6–10, east wall
fixtures, central ramps, pit rails and original activities remain untouched.

## Checks

```sh
cd game
# GUT rule, wallet, lifecycle, layout and UI tests:
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/horse_betting -gexit
# Real server, two bettors and a mid-race late joiner (existing temporary dev auth):
bash tests/features/horse_betting/network_test.sh
# Native renderer: saves /tmp/horse-display.png and /tmp/horse-phone.png:
xvfb-run -a godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/horse_betting/visual_probe.tscn
```

The network probe checks range rejection, duplicate requests, two simultaneous
bettors, locked tickets, the replicated race/winner, actual wallet payouts on both
clients and a late joiner's current tickets/motion. It doesn't require an API or
introduce new tools; authenticated persistent wagers retain the already tested
wallet/API contract.
