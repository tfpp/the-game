# Mechanical slot sound effects

The mechanical WAV files are original deterministic sound designs, synthesized offline
by `docs/design/model-sources/slot-cabinet-v2/audio/build.gd`. No downloaded samples
or additional runtime dependencies. 22,050 Hz, mono, PCM16; each is at most 1.8 s.

- `lever.wav`: latch and spring engagement.
- `motor.wav`: periodic motor/ratchet, loop enabled by the presentation controller.
- `stop.wav`: short reel brake/detent, pitch varies with stop order.
- `payout.wav`: short, bounded metallic coin cascade.
- `bell.wav`: three inharmonic mechanical bell strikes, played at -10 dB and normal pitch.
- `toot.wav`: original synthetic losing toot, mono 16-bit PCM at 22,050 Hz,
  0.22 seconds, non-looping. No external recording or licensed sample was used.
- `loss.wav`: unused mechanism close, retained alongside the synthesis recipe.

The toot is a falling 115–70 Hz buzz with second/third harmonics (weights
1 / 0.45 / 0.25, normalized by 1.7), 32 Hz frequency wobble (±9 Hz), and
39 Hz amplitude flutter (0.8 ±0.2). A 12 ms attack and power-1.4 release
fade avoid clicks; peak synthesis amplitude is capped at 0.5.
Slot playback adds -14 dB attenuation and random pitch 0.85–1.35, which
also varies the duration. Winning playback explicitly resets pitch and volume.

All use GameSFX and spatial attenuation. Existing win.ogg/lose.ogg are legacy,
unreferenced media retained for provenance. Restart/re-export after replacing clips.
