# Backroom chicken book

Find the **STAFF ONLY** service door on the **north-west casino promenade**
at **(-20, 1.25, -19.65)**; GPS → Places → **Backroom Book** routes through it.
Use **E / B / Circle / touch USE** to enter, then use the monitor on the crate.
No new key. The form supports controller focus, touch scrolling and a decimal
number keyboard. Close it to watch the birds; reopen it to check your ticket.
The doorway is deliberately understated, not a new secret quest or key puzzle.

## Play

- Opening an idle book generates two uniquely named roosters, previews their
  strength, speed, stamina, luck, health and decimal **total-return** odds.
  They stand at room-local **(-1.5, 0, -1)** and **(1.5, 0, -1)** facing each other.
- Pick one rooster and **$1–$100**, including cents. The first accepted ticket
  opens one shared **10-second** betting window; later tickets do not extend it.
  One immutable ticket per player per match. A new match cannot overlap the old.
- Charge through the existing wallet immediately. Pending charges hold the start
  of the fight until resolved; rejected charges never enter the fight.
- Every **0.8 seconds**, one server-selected rooster attacks. Stats determine
  attack frequency, health and damage; random attack choice and damage permit
  upsets. Only the chosen attacker lunges/pecks; the defender recoils and loses
  exactly the reported HP. At zero HP that bird falls over, not a gore/death effect.
  The surviving bird wins. No player damage or weapon/animal combat integration.
- A winning ticket credits **floor(wager cents × quoted odds)**. A losing ticket
  remains deducted. The form and private chat show the result and balance;
  the wallet HUD remains the same. Birds disappear after the six-second result
  presentation; using the book again creates the next pair.
- Cancel a ticket in the form, leave the room, disconnect, quit or respawn out
  of the room **before knockout** to receive the original wager back. Merely
  closing the form does not cancel. The other players' match continues; a match
  with no remaining tickets is abandoned. Refunds/payouts wait for the wallet
  service if unavailable; new matches wait until outstanding tickets settle.
  Disconnected temporary wallets are discarded, never credited to a replacement
  player reusing the peer ID.

## Ownership, odds and tuning

`config.gd` is the single Resource containing gameplay tuning (inclusive stat
ranges, stat weights, health/damage, wager limits, house edge, quote sampling,
round/window/result timing and interruption polling). Override the book's
`config` Resource in the scene to tune it. Keep stat/health/damage values positive,
timings positive, house edge in 0..1 and quote sample count positive.
Keep the maximum wager at or below the existing API charge cap ($100); the
maximum quoted return must also fit the existing $100,000 amount-credit cap.

`simulation.gd` is pure: seeded generation, stat power, one-attack round,
Monte Carlo odds and cents payout; no world, network, spawn, wallet or UI calls.
Quotes sample **1,024** independent fights using the actual round rules and a
separate seed derived only from stats (names do not affect odds or consume the
live fight RNG). The default **2% target edge** reduces estimated fair returns.
Probabilities are smoothed/capped to **5–95%** and odds rounded down to two decimal
places. These are estimated odds, not a guarantee of exact long-run house return,
particularly for extreme stat mismatches. A strong favorite can offer a small return.

`book.gd` owns every phase, roster, HP, round result, ticket and immutable money
operation. Its always-present `NetworkedInteraction` component validates sender,
payload schema, match ID, current room/range, duplicate ticket, limits and wallet
balance. Clients cannot choose stats, outcome, peer, damage, odds or payout.
The component replicates one dictionary snapshot, including tickets, quote, attack
and result, to late joiners. No account IDs or journal records are replicated.
Only server code advances rounds. Offline is the same one-peer server path.

The two `ChickenAvatar` nodes are **local cosmetic renderings**, like the existing
horse race display, not independently simulated network creatures. They have no
RPCs, physics or killable state; late joiners reconstruct them from the book.
Thus they don't need a MultiplayerSpawner. Hidden/unloaded rooms do not animate,
and headless servers do not construct avatars. Their floor-centred -Z-forward
native primitives reuse the existing 128px prop-grain texture; no new painted
texture, external model or dependency. Two birds, four shared materials per bird,
716 triangles each. No dynamic shadows.

## Money and interruptions

Reuse `PlayerMoney.adjust_account(peer, captured_account, immutable_id, delta, reason)`:
signed existing **charge** debits and **sell** credits, serialized through the wallet
lock, with idempotent API transactions and temporary-session receipts. No second
balance, balance rollback, account protocol or API deployment change. Existing
charge, credit_reward, roulette, slot, purchase and income interfaces are untouched.

`journal.gd` writes authenticated ticket intents to **user://chicken-bets.cfg**
before any debit. It atomically renames a complete temporary file. Each unfinished
intent defaults to a full refund; knockout fixes the credit to the exact win
return or zero. Restart recovery replays the original debit ID (covering a lost
committed reply), then credits the recorded refund/return with a distinct
64-character SHA-256 ID. Repeated recovery cannot charge/pay twice. Credits
use the captured account even after disconnect, and cannot update a new account's
HUD on a recycled peer. Journal failure refuses a new paid ticket; definitive
credit refusals retain the record rather than silently discarding money.

There is **no game-save/fight-resume interface** on this base: saving settings or
inventory does not interrupt gameplay. Interrupted matches are refunded, not
restored into a later game. Recovery across server restarts needs the server's
`user://` directory preserved; deleting that directory during redeploy loses
recovery records. Temporary/offline wallets and fights reset with their session.
Existing account currency persists in the accounts API.

## Room and checks

The room is a `StreamedRoom` at **(80, 0, -600)**, away from the lounge/cellar.
Its saved GridMaps reuse the casino MeshLibrary: wood floor/perimeter, burgundy
carpet fight area and a tiled ceiling with slab collision. One unshadowed warm
light belongs to streamed Content. Book, presentation, door endpoints, arrival
markers and GPS remain outside Content, at stable peer paths.
Room floor y=0; bounds x=-6..6/z=-5..5. Clear southern spectator aisle connects
the arrival, book and exit; no shared casino geometry or main scene is changed.
The monitor's base meets the crate's 0.7975m top.

Rebuild the editable saved cells with:
`godot --headless --path game -s res://features/chicken_betting/tools/build_room.gd`.

From `game/`:

```sh
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/chicken_betting -gexit
bash tests/features/chicken_betting/network_test.sh
xvfb-run -a godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/chicken_betting/visual_probe.tscn
```

The native probe saves preview/attack/knockout/phone/entrance PNGs under /tmp.
Reviewed captures are in `docs/design/previews/chicken-betting/`.
The WebSocket probe checks two competing bettors, upfront wallet deductions,
duplicate/locked/range rejection, shared knockout/payout and a real late joiner.
