# Mariachi band

**Mariachi Corona de Oro** plays on a round walnut stage on the casino's west
promenade, at (-20.8, 0, 0), facing east into the gaming pit. The stage sits
against the west wall with an open audience aisle between it and the pit.
All five musicians face east in a straight lineup, forward of the backdrop so
their animated meshes remain clear of the wall. GPS lists the band under
Objects and
each musician under People.

- Five musicians on the player avatar rig (`MariachiMusicianModel`, a `PatronModel`):
  two trumpets, violin, vihuela and guitarrón, in black charro suits with silver
  buttons, red moños and gold-trimmed sombreros. Hands follow the music: strums and
  guitarrón plucks land on the beat, the violin bows each note, and the trumpets and
  violin raise or lower their instruments as they trade the tune.
- Songs (`MariachiSongs`): *La Cucaracha* and *Jarabe Tapatío* (the Mexican Hat Dance),
  both traditional and public domain, arranged in C. Each plays twice, then the band
  moves on. Trumpets take the first strain in thirds, the violin the second.
- Press **Use** (E, controller B/Circle, touch USE) within about 2 m of the stage edge
  to request the next song. Requests share a 4 s server-wide cooldown, so two players
  can't skip twice at once.
- Each musician is a `StationaryPatron` (`features/casino_patrons`): guns gib them and
  they come back after 6 s, like the salon guests. The music pauses and requests stop
  only while all five are down.

## Networking

`mariachi_band.gd` (`MariachiBand`, the feature root) owns the song. Its
`NetworkedInteraction` replicates `net_song` and `net_take` (bumped every time a song
starts) on change and in spawn snapshots. The server advances the song on its own clock
or on an accepted `use` request (sender resolved by the component, range checked from
the stage centre, no payload). Every peer restarts the clip when `net_take` changes,
so late joiners start the current song from the top. Musician deaths use the existing
`StationaryPatron` replication. Nothing is persisted; a session change starts over
from the first song.

Only peers with speakers play audio: the dedicated server and headless runs skip
playback. The clip plays positionally from the stage (`AudioStreamPlayer3D`, audible
within 32 m) on the `GameSFX` bus, so the Sound effects volume and mute apply.
Musicians pose at most 30 times a second and only within 32 m of the camera; their
suits, sombreros and instruments are merged into one vertex-coloured mesh per rig
pivot (`MariachiMeshKit`, `vertex_color.tres`).

## Audio

The clips in `assets/mariachi_band/audio/` are rendered offline by `MariachiSynth`
(wavetable trumpets and violin, decaying plucked strings, a small room reverb) from
the scores in `MariachiSongs`, mono 22,050 Hz, imported as looping QOA. Tails wrap
round so each clip loops seamlessly. After changing either script, re-bake:

```sh
godot --headless -s features/mariachi_band/tools/bake_songs.gd
godot --headless --import
```

## Tests

`tests/features/mariachi_band/`: song data and synth (`test_mariachi_songs.gd`),
server requests, cooldown, downed band, rotation, late-join snapshot and hand reach
(`test_mariachi_band.gd`), real ENet late join and client requests
(`test_mariachi_network.gd`), and placement against the real room collision
(`test_mariachi_placement.gd`). `band_probe.tscn` renders the band (needs a window):
`godot res://tests/features/mariachi_band/band_probe.tscn -- --band-capture=/tmp/band.png`
(`--band-camera=x,y,z`, `--band-target=x,y,z`, `--band-time=seconds`).
