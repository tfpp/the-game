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

Limitation: authenticated wallets get their reels from the accounts API, which
doesn't know about blessings yet, so blessings only change the odds on temporary
(offline / insecure-auth) wallets. `kaaba_chant.gd` synthesizes the chant at runtime.
