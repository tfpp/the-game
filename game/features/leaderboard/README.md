# Leaderboard

Open **Esc → Activities → Leaderboard** for Money, Jumps and Kills rankings. Everyone
seen by this server remains listed after leaving, marked **(offline)**. Money is
the last observed wallet balance; jumps and kills accumulate across connections
for signed-in accounts. New players appear even with zero scores. Equal scores
keep the server's roster insertion order, consistently on every client.

## Ownership and networking

`leaderboard.gd` owns history and jump counting. It reads `PlayerMoney.balances`
and `Combat.kills_for()` without changing wallets, combat scores or their callers.
It accumulates connection counter differences once, retaining final values on
disconnect. Jump requests still use the actual RPC sender and now require an
existing player. `jumps_for(peer)` remains the current connection's count.

The server associates players with immutable IDs from `Network.peer_accounts`,
so reconnecting with a new peer ID or renaming updates the same historical row.
Authenticated names come from Network, not client-provided row data. Account IDs
stay private: only display names, scores and the current peer (zero when offline)
are replicated through the existing authority-1 synchronizer, including at spawn
for late joiners. The panel reads these snapshots and never writes scores.
Offline and dev-auth players are remembered for that session only, without merging
people by display name or sharing temporary scores with real accounts.

## Persistence

Authenticated history is saved to `user://leaderboard.json`, with a temporary file
and atomic replacement, every five seconds when changed, on disconnect and on
feature shutdown. Pass `-- --leaderboard-save-path=/persistent-volume/leaderboard.json`
to override the location. The parent directory must exist and **container operators
must mount persistent storage** to retain history across container replacements.
A crash can lose up to five seconds of recent updates. Invalid saved rows are skipped.
Clients do not read or write this file; changing network sessions clears their roster.

History starts when this feature is deployed; the old live roster provides no
records to backfill players who never return. Money remains owned by the accounts
API; the historical snapshot is refreshed when a player returns and their wallet
loads, and is not an offline query of the accounts database.

Tests in `tests/features/leaderboard/` cover the existing menu, ranking and jump
behavior plus disconnect snapshots, account reconnects/renames, reused peer IDs,
save/load, malformed rows, guest isolation, session clearing and late-join sync config.
