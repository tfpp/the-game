# Slot audio

- `win.ogg`: existing optional winning “cha-ching!” sound (Ogg Vorbis, not Opus).
- `toot.wav`: original synthetic losing toot, mono 16-bit PCM at 22,050 Hz,
  0.22 seconds, non-looping. No external recording or licensed sample was used.
- `lose.ogg`: legacy negative cue, retained but no longer loaded.

The toot is a falling 115–70 Hz buzz with second/third harmonics (weights
1 / 0.45 / 0.25, normalized by 1.7), 32 Hz frequency wobble (±9 Hz), and
39 Hz amplitude flutter (0.8 ±0.2). A 12 ms attack and power-1.4 release
fade avoid clicks; peak synthesis amplitude is capped at 0.5.
Slot playback adds -14 dB attenuation and random pitch 0.85–1.35, which
also varies the duration. Winning playback explicitly resets pitch and volume.

The slot machine loads the literal paths above at startup. Restart/re-export
after replacing clips. Missing clips are allowed; gameplay and visual results
still work. Export Ogg files as Vorbis, not Opus, for Godot compatibility.
