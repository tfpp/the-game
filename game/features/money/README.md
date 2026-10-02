# Player money

Accounts start with **$20 once** and earn **$5 per minute connected** with the default
model, or **$4.25 per minute** with the girl model. Amounts are
integer cents in the accounts API's existing SQLite database, keyed by immutable
account ID. Renaming, disconnecting, and restarting do not reset money. Existing
accounts receive the same initial $20 when the append-only migration runs.

The game server sends an authenticated balance heartbeat every five seconds. The
API accumulates elapsed seconds at the selected model's rate and awards them on
reaching 60 seconds. The first heartbeat
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

`PlayerMoney.credit_reward(peer, id, amount_cents, reason)` is the server-only
variable-reward interface used by Vivienne's case for its $100 helper fee.
`sell_loot` delegates to this same implementation without changing its signature,
prices, busy handling, notices or retries. Both use the existing signed `sell`
API transaction: positive server-chosen cents and a stable operation ID. This is
an amount-credit operation, not a new balance or protocol; no API deployment change
is needed. Callers must validate eligibility, keep their ID through retries and
block pending/duplicate claims. Temporary wallets still rely on the owning feature
to prevent replay; the API additionally records idempotent transactions.

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
income, labels, reel timing and interaction. The slot network test checks real
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
