# Mechanical slot sound effects

The active WAV files are original deterministic sound designs, synthesized offline
by `docs/design/model-sources/slot-cabinet-v2/audio/build.gd`. No downloaded samples
or additional runtime dependencies. 22,050 Hz, mono, PCM16; each is at most 1.8 s.

- `lever.wav`: latch and spring engagement.
- `motor.wav`: periodic motor/ratchet, loop enabled by the presentation controller.
- `stop.wav`: short reel brake/detent, pitch varies with stop order.
- `payout.wav`: short, bounded metallic coin cascade.
- `bell.wav`: three inharmonic mechanical bell strikes.
- `loss.wav`: quiet mechanism close, not a win fanfare.

All use GameSFX and spatial attenuation. Existing win.ogg/lose.ogg are legacy,
unreferenced media retained for provenance; current code uses the WAV cues above.
