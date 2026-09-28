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

Other players see the current balance below the character name. A server-owned
synchronizer sends balances to every peer, including late joiners. Clients cannot
set balances or submit payouts. Your own balance shows in the bottom-right corner
(`money_hud.gd`), just above `features/combat`'s health bar, and in the slot
interaction prompt. Offline and dev-auth play use temporary $20 wallets and the same income
and payout rules; these never transfer to a real account.

`PlayerMoney.charge(peer, id, amount_cents)` deducts a flat, feature-chosen price the
same idempotent way `credit_coin()` pays one out, rejecting (without spending anything)
if the wallet can't cover it. It's the `charge` action on `POST /api/game/money`
(`amount_cents`, capped server-side well above any planned price) — added for
`features/gun_machine`'s machine; see that feature's README for how it's spent.

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

For spins, the API generates independent random reels and transactionally records
the result, deducts $1, and pays the prize. A unique operation ID makes retries
idempotent. Insufficient funds reject the entire spin, including a would-be win.
The game remembers unresolved operation IDs so retrying after a lost response
recovers the result without charging again. A spin's recorded balance reflects its
settlement; the next heartbeat refreshes any income awarded since then.

Coins scattered around the map (`features/coins/`) pay a flat $10 the same way: the
server calls the `credit` action with a fresh operation ID, the API adds the reward
and records the ID so a retried request doesn't pay twice.

Validation: Go store/API tests cover persistence, concurrent spending, replay,
authentication, income and exact expected payouts. GUT covers offline wallets,
income, labels, reel timing and interaction. The slot network test checks real
server/two-client balance replication; `SLOT_TEST_DATABASE=1` includes the real API,
SQLite and a full minute of income.
