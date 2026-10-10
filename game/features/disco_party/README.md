# Disco party

A walnut-and-gold DJ booth stands in the gaming pit at (4.2, -1.25, 0), east of
the ramp lane and 1.8 m in front of the slot bank. A mirror ball hangs on a cable
from the hall ceiling (y 8.75) over the pit centre at (0, 6.5, 0).

Walk up to the booth and press **E / B / Circle / touch USE** to drop the beat.
For **30 s** everyone in the casino gets the party: the ball spins fast, six
colored additive light beams sweep the room, one shadowless omni light pulses in
time and a 120 BPM disco loop plays positionally from the ball. The booth sign
shows who is on the decks and the time left. Afterwards the booth recharges for
**45 s** before anyone can start another party.

## Networking

`DiscoParty` (the feature root) owns the state on the server. Use goes through
`NetworkedInteraction.register_use`: the server resolves the sender's player,
checks the 2.5 m range from the deck and that the booth is idle. The server runs
the clocks and replicates `net_seconds_left`, `net_recharge_left` and `net_dj`
(whole seconds, so they change once a second) through `NetworkedEntity`. Every
peer derives the visuals and music from those fields, so late joiners walk into a
party already in progress. Two simultaneous presses start one party; a session
change ends it. State lives in server memory only.

## Audio

`DiscoBeat.build()` synthesizes the one-bar loop (kick, clap, off-beat hats,
octave bass; 22.05 kHz mono 16-bit) the first time a party plays on a peer with
speakers. No audio file ships. Dedicated servers and headless runs stay silent.
