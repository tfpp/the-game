# Player money

Accounts start with **$20 once** and roll a **random prize each minute connected**.
A prize starts at a uniform **$1–$9**; each independent **1-in-20** promotion multiplies
it by ten and tries again. Thus 95% of prizes stay at $1–$9, while billion-dollar
and larger jackpots remain possible (about 0.000000000195% for at least $1 billion
before the model adjustment). The request's example odds are interpreted as
illustrative, not an exact required probability. There is no gameplay prize ceiling:
only the existing signed 64-bit cents representation stops promotions; additions
saturate at its maximum rather than overflowing. API balance parsing preserves the
integer cents token rather than rounding huge balances through JSON floats. The girl model retains its 15%
reduction, weighted by time when switching models within a minute.
Amounts are
integer cents in the accounts API's existing SQLite database, keyed by immutable
account ID. Renaming, disconnecting, and restarting do not reset money. Existing
accounts receive the same initial $20 when the append-only migration runs.

The game server sends an authenticated balance heartbeat every five seconds. The
API accumulates elapsed seconds and weighted model units, then samples and commits
one prize in the existing heartbeat transaction on reaching 60 seconds. Repeated or
backdated heartbeats cannot reroll a committed prize. The first heartbeat
starts the clock; awards can appear up to one heartbeat interval after a minute.
The fractional minute and last heartbeat persist in SQLite. Gaps over 15 seconds
pause accrual rather than granting offline income; short gaps between heartbeats
are counted. API downtime pauses income and blocks paid spins.

A wallet landing on $67 (whole dollars) makes everyone do the 6-7 emote; see
`features/player_models/README.md`.

Every peer also ranks connected wallets from poorest to richest (`PlayerMoney.poorest_peers`,
ties broken by peer ID) and shows a small buzzing swarm of flies (`poverty_flies.gd`) over
the poorest 80% of players, rounded down. A lone connected player is never flagged, since
there is no one to be poorer than. The ranking and swarm are purely cosmetic and computed
identically on every client from the same replicated balances, so they need no extra
networking; like the balance label, they only render over other players, not your own.

Other players see the current balance below the character name. A server-owned
synchronizer sends balances to every peer, including late joiners. Clients cannot
set balances or submit payouts. Your own balance shows in the bottom-right corner
(`money_hud.gd`), just above `features/combat`'s health bar, and in the slot
interaction prompt. Offline and dev-auth play use temporary $20 wallets and the same income
and payout rules; these never transfer to a real account.

**Local dev:** running the project from the Godot editor binary with a window (the
editor's Play button, or `godot --path game`) starts temporary wallets at **$100,000**
instead of $20 (`PlayerMoney.local_dev()`), so gambling can be tested without grinding.
Exported web/server builds and the headless GUT/smoke checks keep $20, and accounts
API balances are never touched.

`PlayerMoney.charge(peer, id, amount_cents)` deducts a flat, feature-chosen price the
same idempotent way `credit_coin()` pays one out, rejecting (without spending anything)
if the wallet can't cover it. It's the `charge` action on `POST /api/game/money`
(`amount_cents`, capped server-side well above any planned price) — added for
`features/gun_machine`'s machine; see that feature's README for how it's spent.

`PlayerMoney.settle_roulette(peer, account, id, wager_cents, payout_cents)` settles a
whole roulette round in one idempotent operation: it deducts the wager and pays the
payout together, rejecting both if the wallet can't cover the wager. It's the `roulette`
action (`wager_cents` up to the slot cap, `payout_cents` at most 36 times the wager); see
`features/roulette/README.md`.

## Atomic cosmetic transactions

`PlayerMoney.cosmetics(peer, id, revision, document, delta, load = false)` is a
server-only interface for the pawn shop's cosmetic collection. It shares the
existing wallet lock, replicated balance, signed transport and gain notices.
The feature validates its catalog, rolls rewards and retains immutable retry
payloads; this method does not accept client-authored documents or own collection
rules. A negative `delta` buys a crate; positive values exchange duplicates; zero
changes only collection/equipment. `load = true` reads current account state.

The signed `/api/game/money` actions `cosmetics_load` and `cosmetics` return
`{revision, document, balance}`. A commit adds `revision`, `document` and
`delta` to the ordinary account/ID/timestamp payload. The API bounds documents
at 8 KiB, requires the crate/skin/equipment maps, and atomically commits a
revision CAS, wallet delta, document and immutable transaction ID in SQLite.
Mismatched retries or stale revisions return 409 without spending. A successful
replay returns current account state, not an old balance. Real-account collection
saves cannot be separated from the debit/credit; see
[crate lifecycle and configuration](../pawn_shop/README.md#prawn-skin-crates).

Temporary wallets retain idempotent cosmetic receipts in session memory.
They do not acquire persistent currency or account state. Deploy the API first;
older ordinary charge, sale, spin, roulette, income and inventory actions stay
unchanged. Tests include fake account transport through this actual interface,
SQLite rollback/reopen/concurrency and the original wallet/slot network suites.

## Animated slot payouts

`spin()` keeps its existing immediate-settlement behavior. Slots use the server-only
`spin_animated(peer, id, wager_cents, rerolls, blessings)` wrapper instead: it commits
the same atomic API operation but withholds the prize from replicated balances and
keeps that wallet busy. `reveal_spin(peer, id)` adds the held prize exactly once when
the cabinet finishes; wrong/stale IDs do nothing. The hold belongs to PlayerMoney,
not a second cabinet balance. Refreshes, purchases and other spins cannot expose or
spend the prize while held. Temporary income remains additive. Reveal checks the
original account; session reset clears holds and a removed cabinet releases its hold.
Authenticated prizes survive disconnect/server crashes in the existing database;
temporary offline wallets still reset with the session.

## Server connection

Deploy the updated **API first**, then the matching game server and web client. The bot
does this automatically: API builds deploy as soon as they finish, ahead of the slower
server and web client builds. The API migration is automatic on startup. Keep its existing persistent API_DB
volume. No new secret is required: the server's `--ticket-key-file` and the API's
`API_TICKET_KEY_FILE` share the existing ticket key.

The game server uses `Network.resolve_api_url()` (the normal API URL), or pass
`--api=http://api:8080/api` for a direct internal connection. The endpoint is
`POST /api/game/money`, authenticated with `X-Game-Signature`: hex HMAC-SHA256 of
`game-money-v1\n` plus the exact JSON body, using the ticket key. Bodies include
`account_id`, `action` (`balance`, `spin` or `credit`), `id` (32 random bytes as hex
for spins and credits), and `timestamp` (Unix seconds, within 60 seconds of the API
clock).

For unblessed spins, the API generates uniform random reels and transactionally records
the result, deducts the request's `wager_cents` (each machine sets its own; omitted
or zero defaults to $1 for older game servers), and pays a prize scaled to that
wager so every machine keeps the same 80% return. `wager_cents` is capped server-side
at $1,000,000,000 — see `features/slot_machine/README.md` for the buy-in per machine.
A unique operation ID makes retries idempotent. Insufficient funds reject the entire
spin, including a would-be win. The game remembers unresolved operation IDs so
retrying after a lost response recovers the result without charging again. A spin's
recorded balance reflects its settlement; the next heartbeat refreshes any income
awarded since then.

Coins scattered around the map (`features/coins/`) pay a flat $10 the same way: the
server calls the `credit` action with a fresh operation ID, the API adds the reward
and records the ID so a retried request doesn't pay twice.

Validation: Go store/API tests cover persistence, concurrent spending, replay,
authentication, income and exact expected payouts. GUT covers offline wallets,
random income, labels, reel timing and interaction. Deterministic sampling tests in
`tests/features/money/test_random_income.gd` and
`api/internal/store/income_random_test.go` cover matching decade rules, billion-dollar
and larger wins, model scaling, minute gating, replay and overflow safety. The slot network test checks real
server/two-client balance replication; `SLOT_TEST_DATABASE=1` includes the real API,
SQLite and a full minute of income.

## Kaaba luck

`spin(peer, id, wager_cents, rerolls, blessings)` retains temporary-wallet extra
rolls in `rerolls` and adds optional Kaaba `blessings` (clamped to 0..5). The server reads them from KaabaPrayer,
never from a client payload, and includes `blessings` in its signed spin request.
The API rejects counts outside 0..5; omitted counts default to zero for old servers.
Each stack adds 200% of the base 4% win chance, giving 12% with one and 44% with five.
Temporary wallets use the identical distribution. Prizes, charges and transactional
retries are unchanged; replaying a settled operation always returns its original
result, even if the blessing count has since changed. Deploy the API first.

## Money log

Whenever a wallet gains money, the server calls `PlayerMoney.announce_gain(peer, cents,
reason)`, which shows `+$10.00: <reason>` to that player only in the chat log
(`features/chat_box`'s `send_notice()`). `credit_coin()` and `sell_loot()` take a required
`reason` and announce on success; minute income and slot wins announce too (a slot win only
once the reels stop). Features that pay out must pass a player-facing reason.
