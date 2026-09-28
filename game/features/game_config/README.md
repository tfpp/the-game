# Game settings

The Game settings page owns the shared jump-height, frog-hop-rate and frog-height
multipliers. Each existing `request_*` RPC is also used by the developer console.
The server accepts finite values from connected players (or local server calls),
clamps to the existing ranges and replicates through `Sync`, including late joins.
Settings are world/session state, not persistent player preferences. Any connected
player may tune them; simultaneous requests are applied in server arrival order.
The Settings page and console use the same state and request interfaces.

Tests live in `tests/features/game_config` and the console integration tests.
