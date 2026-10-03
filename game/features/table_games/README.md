# Crown gaming suites

Use the **GAMING SUITES** door at `(10, 1.25, -18.8)` on the Golden Crown's north
promenade. Three connected chambers host blackjack and Texas Hold'em (west),
pass-line craps (centre), and baccarat and Crown draw poker (east). Each has a GPS
destination. The complete suites are a combat-free SafeZone. The entrance uses the
existing authenticated hotel portal and preloads the streamed GridMap interior.
Return through the Golden Crown door in the centre chamber.

Approach a table, look at it and press E / controller B / touch USE. Buttons support
mouse, touch and standard controller focus navigation. Join costs a $1 stake; poker
requires $5 available to reserve its maximum exposure. The first player opens a
12-second joining window. Players can cancel before dealing. Back to room / Esc
closes the controls; committed hands continue. Reopen using the same table. A
25-second action timeout stands in blackjack, folds in poker, draws unheld cards in
draw poker or rolls the dice. Leaving the table's range or disconnecting triggers
the same automatic action. Results stay for eight seconds before another round.

- **Blackjack:** up to four hands against one dealer. Hit/stand, natural 3:2,
  dealer stands on all 17s. No split/double/insurance rules in this version.
- **Texas Hold'em:** two to four human players, $1 ante, four betting streets,
  $0.50 fixed bets and one raise per street. At most $5 committed per player.
  Check/call, bet/raise and fold; seven-card best-five showdown, ace-low straights,
  full kickers and split pots. Odd cents go in joining order. No side pots/all-ins
  are needed because every player reserves the same maximum stake. No house rake.
- **Baccarat:** Player 1:1, Banker 0.95:1 after commission, Tie 8:1; Player/Banker
  push on ties. Standard natural and player/banker third-card rules.
- **Craps:** shared pass-line stakes and a designated shooter. Come-out 7/11 win,
  2/3/12 lose; otherwise establish a point and roll it before seven. Pays 1:1.
  Proposition bets, odds and don't-pass are not offered.
- **Crown draw poker:** one operator, with other players able to watch. Five-card
  deal, selectable holds, one draw. Its **custom gross** paytable is shown before
  joining: royal 36x, straight flush 25x, four 25x, full house 9x, flush 6x,
  straight 4x, three 3x, two pair 2x, jacks-or-better pair 1x. This is not the
  standard full-pay Jacks or Better schedule.

## Authority and wallets

`CrownGameTable` owns the server deck, hidden hands, decisions and round clock.
Each stable table endpoint uses `NetworkedInteraction.register_use/request_use`
and registered move/leave actions. Identity comes only from the authenticated
transport. Join checks range, facing and geometry obstruction; actions check range,
phase, turn and exact payload types. Unknown actions, forged IDs, invalid hold
masks and another player's turn are refused. Wallet reservations prevent another
table, slot, roulette spin or purchase from spending a committed stake. Income
heartbeats continue during reservations. Betting cancellations release them.

Only the public snapshot is replicated. Poker holes and the draw-poker deal travel
through recipient-only reliable authority events. Spectators and late joiners see
the current board, phase, chip amounts and results without receiving hidden hands.
Seated players reopening a table receive their own hand again. Session changes
clear hands, timers, reservations and old retry callbacks.

Every completed player's wager/payout uses the existing signed atomic, idempotent
`roulette` wallet settlement protocol; no API or engine changes are needed.
Operation IDs and amounts remain unchanged across retries. Tables wait for all
settlements before reopening, including during API outages. The draw-poker
paytable stays within the protocol's existing 36x payout cap.

Poker settles losing wagers before winner payouts. Each account's transaction is
atomic; the complete pot across multiple accounts is not a database transaction.
A server crash during poker settlement can leave a partially settled pot. An
unfinished hand before settlement never debits a wallet. Durable cross-account
pot recovery would require an accounts API escrow/journal extension; this feature
does not alter protected API files. Normal disconnects keep captured account IDs
and settle the round, with temporary wallet balances retained until completion.

## Models and rooms

Five native model assemblies combine reviewed casino-prop meshes with dealer
hardware, dice or cards. Existing authored UVs and painted 16–128px textures are
preserved. Each assembly has two static material surfaces. The reproducible recipe
and source inventory are in `docs/design/model-sources/crown-tables/`.

The streamed interior uses the existing casino MeshLibrary and native GridMaps;
no new CSG room geometry. Gameplay endpoints, colliders, portals, GPS and safety
stay outside the streamed content so all peers have matching RPC paths.

## Verification

From the repository root:

```sh
godot --headless --path game --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/table_games -gexit
godot --headless --path game -s res://tests/features/table_games/network_check.gd
harness/verify.sh
```

The real transport fixture runs a server, two players and a late spectator through
all five games. It checks private poker cards, rejected identity injection and
split-pot conservation. The standalone rendered review uses:

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/table_games/capture.tscn
```

This saves actual Godot room images under `docs/design/previews/crown-games/`.
Requires a graphical display. These captures establish appearance, not performance.

## Seats and table staff

Blackjack, poker and baccarat have four usable chairs each; draw poker has one.
Craps remains a standing table, with an animated croupier. Use a chair to sit for
free and open the table controls; joining a wager still requires **Join / play
again**. **Stand up** releases the chair. After closing the controls, movement or
jump also stands up. Leaving a seat does not cancel an already dealt wager:
existing timeout, fold and settlement rules still apply.

`CrownTableSeating` extends the existing food-court seating implementation. It
reuses server validation, local player pinning, stand-up handling, death,
disconnection, teleports and session reset. Its NetworkedInteraction replicates
seat occupancy on spawn and changes. A peer may occupy only one seating system;
the avatar queries all seating providers for its shared seated pose. Chairs reuse
the reviewed low-poly dealer-chair model and its painted atlas.

Four dealers use the existing connected human rig and tux texture. Eight shared
full-body clips include idle, greeting, shuffle, deal, reveal, collection, payout
and dice handling. Bone-attached cards, decks, chips and dice follow the hands.
Native AnimationPlayer playback owns the pose; no repeated runtime IK or full-body
procedural pass runs after it. The server queues presentation clips in the public
round snapshot and advances their elapsed clock at up to 10 Hz, stopping clock
updates when the queue ends. No card identities are added to animation cues.
Late observers seek into the current motion; clients cannot request dealer cues.
Dealers are cosmetic staff with no damage or gameplay authority.

Dedicated servers do not instantiate dealer rigs. Clients suspend posing beyond
20 metres or when hidden and seek to the current snapshot on return. The clocks
and clip state are per dealer; shared resources are reused. No client performance
benchmark or web playback benchmark is claimed for this extension.

Rebuild the compressed native clips (Godot 4.7, repository root):

```sh
godot --headless --path game res://../docs/design/model-sources/crown-tables/bake_dealer.tscn
```

`tests/features/table_games/test_seats_and_dealer.gd` covers seat claims, cleanup,
shared seated posing and real bone playback. `network_check.gd` uses real server,
two clients and a late spectator to verify chair contention, playing while seated,
private hands and all five games. The graphical `capture.tscn` also captures the
actual dealer motion sequence into `/tmp/crown-dealer-frames` at 12 fps, alongside
room and action stills in `docs/design/previews/crown-games/`.

## Lounge decor

Each streamed chamber has four corner plants, a leather sofa and coffee table,
framed art, a clock and two warm brass sconces. Existing reviewed native prop
scenes and painted atlases are reused. Decor and its collision unload with the
room's Content; the persistent table and seat endpoints remain available to the
server. Furnishings stay along the perimeter, clear of table seating, dealer
stations, connecting doors and the return portal.
