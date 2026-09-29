# Roulette table

One table stands at `(6, 0, -4)`. Approach it from any side (it's round), look at
its center within 3.5 metres, then press **E**, **Circle / B**, or mobile **USE**.
The on-screen prompt identifies the table. Menus and chat suppress interaction.

There's no betting or currency: spinning is free and just for fun. The wheel is an
American layout — pockets 0, 00 and 1-36, with 0 and 00 green and the rest split
18 red / 18 black.
Each spin is an independent, uniformly random pocket; unlike the slot machine there
is no forced win rate. The ball takes 3 seconds to settle, visibly circling the
wheel before landing.

The server validates the actual RPC sender's player, distance and facing, and
checks for a clear line of sight to the table. Only one spin runs at a time; other
requests during it are ignored. The spinning ball position, operator name and final
number/color are replicated together in a server-owned `MultiplayerSynchronizer`
snapshot, so late joiners see the current state. A spin finishes even if its
player disconnects.

## Layout

- `feature.tscn` places the table in the world.
- `table.tscn` is the reusable entity: collision, replication and view.
- `roulette_table.gd` owns validation, spin progression and replicated state.
- `roulette_wheel.gd` draws the pocket, names it ("00") and generates the red/black/green mapping.
- `roulette_table_view.gd` builds the placeholder table, wheel and ball.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another table, instance `table.tscn` under `feature.tscn` with a unique node
name and position. All peers must load the same scene; each instance has its own
wheel and busy state.
