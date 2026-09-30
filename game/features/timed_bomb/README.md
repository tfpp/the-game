# Timed bomb

A one-shot four-digit defusal puzzle beside spawn, at **(-2.3, -1.5, 4.5)** on
the gaming floor. The central aisle, spawn's entire +/-3m jitter square and
south ramp stay clear. Walk over and Use **E / B / Circle / touch USE**.
Click/tap the keypad, or navigate it with controller focus and A/Cross.
Leading zeroes count. Clear erases the input; Close/Esc cancels without guessing.

## Shared state

The accounts API's SQLite `timed_bomb` singleton owns the random code, absolute
Unix deadline, armed/defused/exploded state and shared five-second guess cooldown.
The first successful status request starts **24 real hours**, once, not per player.
Downtime counts. Reconnects, respawns and server redeploys never rearm the puzzle.
Simultaneous guesses/expiry serialize in a transaction; expiry wins at the deadline.
There is no in-game removal, pickup, damage, rearm or reset action.
This does not restrict future maintainers or future feature requests.

`NetworkedInteraction` authenticates Use/guess requests and checks range. The
feature checks the exact four-ASCII-digit schema, range, armed state and pending
request again. Async replies are session-scoped and never delivered to a replacement
player after disconnect. Defusal submitted in range can finish after moving away.
Only public state, availability and remaining seconds replicate, including late
joins. Countdown uses server elapsed wall time between API samples, not game frames
or the client's clock. A backend outage disables guesses and retries automatically;
it never creates a replacement live puzzle or exposes the code.

The code is generated with Go crypto/rand, stored only in the puzzle table and
never returned by an endpoint, replicated, logged, or shown as a clue.
Players must guess or learn it from a trusted operator outside the game; there
is deliberately no database-browser or code-reveal command.

## Expiry

A short orange low-poly blast and existing positional explosion cue play for
current observers; a spent dark case remains for late joiners without replaying
the effect. Expiry is harmless: no damage, displacement or world destruction,
preserving the casino's safe-zone role. No dynamic lights or ongoing particles.

## Deployment and offline preview

Deploy **API before game** and retain the existing API_DB volume. New append-only
migration, no new dependencies/secrets. `POST /api/game/timed-bomb` requires the
existing ticket key and `X-Game-Signature`: hex HMAC-SHA256 over
`game-timed-bomb-v1\n` plus exact JSON bytes. Body:
`{action: "status"|"defuse", code: "<four digits>" (defuse only), timestamp: <Unix>}`.
Timestamp must be within 60 seconds. Replies contain only deadline, state,
remaining and a generic message. No player/account data is stored.

Offline and keyless dev-auth servers use a **separate practice puzzle** in
`user://timed_bomb_practice.json`, with its own hidden local code and absolute
deadline. This is not database-backed and is not the live puzzle. Corrupt/unwritable
storage fails closed instead of silently restarting the clock. The exported
`practice_path` is for isolated tests. Browser practice persistence follows
Godot's user-data storage, not the server database.

## Tests

`tests/features/timed_bomb/` covers validation/authority, busy and outage rejection,
real-time expiry, persistence, shared cooldown, modal controls, countdown formatting,
code-free spawn replication, real ENet late clients and floor/spawn/route clearance.
Go store/API tests cover generation format, reopening SQLite, terminal states,
simultaneous defusal, cooldown and signed endpoint/schema/privacy.
Run targeted GUT and `cd api && go vet ./... && go test ./...`, then
`harness/verify.sh`.
