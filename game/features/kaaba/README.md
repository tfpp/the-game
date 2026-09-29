# Kaaba

A scaled-down Kaaba in the northwest of the main room, at (-24, 0, -24).

## Praying

Stand within 5.5 m of the Kaaba's centre (anywhere around it) and press **Use**
(E, Circle / B, or mobile **USE**). A takbir-style chant in the Hijaz maqam plays at
the Kaaba for everyone nearby, and after 6 s of prayer you earn one blessing. Walking
away interrupts the prayer.

Blessings stack up to 5. Each one gives a losing slot machine spin one more roll of
the reels, so the win chance goes from 4% to 1 − 0.96^(1 + blessings) (about 22% at
5). A win spends all your blessings. The Kaaba and slot prompts show your count.

`KaabaPrayer` (`kaaba_prayer.gd`, node `Prayer`) owns the per-peer `blessings` and
`praying` dictionaries on the server and replicates them with a synchronizer, so late
joiners see current counts. Blessings reset on disconnect and session change and are
not persisted. `SlotMachine` reads `blessings_for()` and passes it to
`PlayerMoney.spin()` as `rerolls`, then calls `consume()` on a win.

Authenticated wallets now send bounded rerolls to the accounts API, which rolls and
settles one charged spin atomically. Deploy the updated API before the game server.
The bonus still applies only to slots, not roulette or craps, and does not multiply prizes.

Prayer uses NetworkedInteraction for validated Use requests and replicated state.
Completion sends a mint blessing burst at the player; a successfully paid blessed
spin sends a gold crescent and star above the machine, before its result is revealed.
Both are authority-only NetworkedEntity events visible to nearby peers, including
the local player, with no replay for late joiners. Effects expire after two seconds.
No new controls; touch and controller use the existing Use action.
`kaaba_chant.gd` synthesizes the chant at runtime.

Validation: from the repository root, run
`python3 game/tests/features/kaaba/run_network.py` for a real server, player,
observer and late joiner. This extends the existing slot probe to pray before
spinning, verifies live effects and late-join state without replaying old VFX,
then exercises five spins and competing requests. API Go tests cover authenticated
rerolls and idempotent settlement; the probe uses dev wallets.
