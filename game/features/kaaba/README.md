# Kaaba

A scaled-down Kaaba in the northwest of the main room, at (-24, 0, -24).

## Praying

Stand within 5.5 m of the Kaaba's centre (anywhere around it) and press **Use**
(E, Circle / B, or mobile **USE**). A takbir-style chant in the Hijaz maqam plays at
the Kaaba for everyone nearby, and after 6 s of prayer you earn one blessing. Walking
away interrupts the prayer.

Blessings stack up to 5. Each adds **200% of the base slot win chance** (8 percentage
points): 4% without blessings, 12%, 20%, 28%, 36%, then 44% at five. This is additive,
not compounded. A win spends all your blessings; losses keep them. Prizes and buy-ins
are unchanged. The Kaaba prompt explains the bonus and slot prompts show total luck.
This works for offline/dev wallets **and authenticated accounts**.

`KaabaPrayer` (`kaaba_prayer.gd`, node `Prayer`) owns the per-peer `blessings`, `praying`
and private timers on the server. Its `NetworkedInteraction` component validates the
transport sender, empty payload, 5.5 m range around player height, active prayer and
stack cap. It replicates both dictionaries to everyone, including late joiners, and
broadcasts a reliable authority-only chant event. Late joiners see ongoing prayer and
current blessings but do not replay a chant that already started. The existing
`request_pray` RPC delegates to the same validation for compatibility; Use calls the
component directly. The existing spatial synthesized chant remains audible nearby.

Different players can pray simultaneously. Duplicate requests cannot restart timers.
Walking away, death or a missing player cancels an unfinished prayer. Earned blessings
survive respawn; disconnect and session change clear them. They are not persisted.
`SlotMachine` reads `blessings_for()` and passes it to `PlayerMoney.spin()` through the
legacy `rerolls` argument, then calls `consume()` on a win. That argument now means
blessing stacks, not repeated independent rolls. Both game and API map a uniform
0..124 ticket to the same outcome distribution, preserving equal winning symbols.

Deploy the updated accounts API before the game; old APIs ignore the new signed
`blessings` field. Existing clients never choose their own odds or payouts.

## Checks

- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/kaaba -gexit`
  from `game/`: validation, stacking, cancellation, exact odds and offline wallet.
- `python3 game/tests/features/kaaba/network_test.py` from the repository root:
  actual server, requester, observer and late joiner; broadcast chant, replicated
  ongoing/completed prayer, forged/duplicate requests, client mutation and disconnect.
- API tests exhaust every random ticket at every stack count and check authenticated
  validation and replay safety; normal slot and wallet tests remain applicable.
