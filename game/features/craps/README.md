# Craps table

The green table at **(-6, -1.5, 0)** sits opposite roulette, between the slot rows.
Look at it from within 3.5 metres and press **E**, controller **B / Circle**, or mobile
**USE**. The existing interaction system hides prompts while menus/chat are active.

This is **free pass-line play**, like the free roulette wheel: no money is wagered,
won or lost. On the come-out roll, 7 or 11 wins and 2, 3 or 12 loses. Any other total
sets the point. Keep rolling until that point wins or a 7 loses; other totals leave
the point intact. After a win/loss the next roll starts a new come-out round.

Everyone shares the same round and can take the next roll. The table displays the
roller, both dice, their total, the point and the result. Dice tumble for two seconds;
only the settled faces represent the result. A departing roller cannot strand a round.

`craps_table.gd` owns server-only independent d6 draws, roll timing and pass-line
resolution. Its request RPC accepts no dice, point or player ID: it validates the
actual sender's player, range, facing and line of sight, and rejects busy requests.
`table.tscn` replicates one atomic state dictionary through a server-owned synchronizer,
including spawn state for late joiners. Session changes reset the table.
`craps_table_view.gd` only presents that state; animation never affects the result.
`feature.tscn` loads through the standard feature loader, without world/core changes.

Tests: `tests/features/craps/test_craps_table.gd`; run `harness/verify.sh` from the
repository root. The standalone multiplayer probe is run with
`python3 game/tests/features/craps/network_test.py`.
