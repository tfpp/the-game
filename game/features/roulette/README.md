# Roulette table

One table stands at `(-9.1, -1.5, -5.5)`, with the wheel at its west end. Approach
either long side, look at the betting layout within 3.5 metres, then press **E**, **Circle / B**, or mobile **USE**.
The on-screen prompt identifies the table. Menus and chat suppress interaction.

There's no betting or currency: spinning is free and just for fun. The wheel is an
American layout — pockets 0, 00 and 1-36, with 0 and 00 green and the rest split
18 red / 18 black.
Each spin is an independent, uniformly random pocket; unlike the slot machine there
is no forced win rate. Each spin takes 3 seconds: the rotor speeds up, the ball
rolls around the track the other way and drops inward, and once the server settles
the result the ball rolls into that pocket and rides the rotor. Every peer animates
this locally from the replicated state, so the winning pocket isn't known on clients
until the spin ends.

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
- `roulette_wheel.gd` draws the pocket, names it ("00"), maps red/black/green and
  lists the pocket order around the wheel.
- `roulette_table_view.gd` shows the table model
  (`assets/roulette/models/roulette_table.glb`) and animates the rotor and ball.
- `../interaction/` supplies the shared Use binding and proximity prompt.

To add another table, instance `table.tscn` under `feature.tscn` with a unique node
name and position. All peers must load the same scene; each instance has its own
wheel and busy state.
