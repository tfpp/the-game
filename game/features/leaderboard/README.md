# Leaderboard

Open **Esc → Activities → Leaderboard** for Money, Jumps and Kills rankings. Everyone
seen by this server remains listed after leaving, marked **(offline)**. Money is
the last observed wallet balance; jumps and kills accumulate across connections
for signed-in accounts. New players appear even with zero scores. Equal scores
keep the server's roster insertion order, consistently on every client.

## Longest-online statue

A bronze portrait stands beside spawn on the north promenade at **(4.6, 0, -15.8)**,
looking west toward new arrivals. Its pedestal rests on the live floor (y = 0),
with the avatar's feet on the cap at y = 0.9. The 1.5 m footprint clears the entire
spawn-jitter square, elevator corridor and neighboring door approaches. No Use
prompt or key is needed, on desktop, touch or controller.

The server selects the most cumulative recorded online time among its historical
roster, including offline players, immediately when a roster becomes available and
then **every 60 seconds**. Ties keep roster insertion order. The plaque shows the
name and whole hours/minutes; the frozen bronze avatar copies body, head, tail,
hairstyle, outfit, equipped clothing/hat and height. Disconnects retain the last
portrait; reconnects and renames reuse the same account record. Respawning does
not change account totals. Old saves without these fields load with zero time and
a default portrait until the player returns.

Authenticated totals come only from `PlayerMoney.playtime_for(peer)`, reading the
API's existing persistent heartbeat counter. No game timer estimates or increments
account time. API downtime/busy gaps retain the last observed total. As with money,
this ranks **players observed by this server**, not accounts that have never joined;
previous deployments' time becomes available when the account next joins. The
API field is additive: older APIs keep working but do not provide account time.
Guests/offline previews instead accumulate session-only connected time in the
leaderboard and never save or transfer it into accounts. Authenticated time and
portrait snapshots use the existing leaderboard save path and volume requirements.

`longest_online()` is a server-only, identifier-free display snapshot:
`{name, seconds, portrait}`. Existing panel entries and tabs are unchanged.
`online_statue.tscn` lives under this feature; its `NetworkedEntity` replicates
only `champion` on change and at spawn, so late joiners see the same minute snapshot.
It registers no actions; clients cannot choose a winner or submit time/portraits.
Changing sessions clears the sculpture. Portraits are scenery, not Players,
interactables or killable targets. Three shared bronze/patina materials reuse the shipped
avatar geometry/UVs, face texture and casino grain; no new texture assets, animations,
dynamic lights or per-frame avatar posing are added. The wooden pedestal uses the
existing walnut texture. All reused textures stay within 128px.

Tests: `tests/features/leaderboard/test_online_statue.gd`, `test_statue_network.gd`
(real ENet server/late client with rejected action), and `test_statue_placement.gd`
(live GridMap floor and capsule routes), alongside the original leaderboard suite.
For native rendered review of front/rear views and creature choices:

```sh
xvfb-run -a godot --path game res://tests/features/leaderboard/statue_visual_probe.tscn
```

Captures go to `/tmp/statue-*.png`, outside runtime assets.

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
