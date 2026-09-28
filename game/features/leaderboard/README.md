# Leaderboard

"Leaderboard" in the Esc menu: three tabs ranking every connected player by money,
jumps and kills, highest first.

## How it works

- `leaderboard_panel.gd` is read-only UI. It reads `features/money`'s
  `PlayerMoney.balances` for the Money tab and `features/combat`'s `Combat.kills`
  for the Kills tab — both already server-authoritative and replicated — by looking
  those features up by group (`player_money`, `combat`), the same cross-feature
  pattern `features/slot_machine` uses to reach the wallet.
- Jump counts belong to neither of those, so `leaderboard.gd` adds the one dictionary
  this feature needs: a peer-keyed `jumps` count, replicated like `PlayerMoney.
  balances`. `core/player/player.gd`'s `jumped` signal only ever fires for the local
  peer's own `Player` (puppets skip physics), so each client reports its own jumps
  with the server-validated `request_record_jump` RPC, the same any_peer pattern
  `features/player_models` uses for body type requests.
- Every list is built fresh each frame the panel is open, from every `Player` node
  currently in the `players` group — nobody who has left the world shows up, and
  everybody currently in it does, even with a score of zero.
- Ties break on peer id, so every client's ranking agrees.

## Adding a new tab

Add a tab to `LeaderboardPanel.TABS`, a case to `_values()` reading whichever
feature owns that stat, and a case to `value_text()` if it needs custom formatting
(like Money's dollar amounts). Don't add a new dictionary here for a stat another
feature already tracks — read it from that feature instead, like Money and Kills do.
