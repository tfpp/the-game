Place optional, short, non-looping Ogg Vorbis clips here:

- `win.ogg`: winning “cha-ching!” sound.
- `lose.ogg`: losing/negative sound.

The slot machine loads these exact paths at startup. Restart/re-export after adding
them. Missing clips are allowed; gameplay and visual results still work.

The codec must be **Vorbis**, not Opus. Both can use an `.ogg` extension, but
Godot cannot import Opus clips through its Ogg Vorbis importer. Check downloaded
clips with `ffprobe` or export them explicitly as Ogg Vorbis from your audio editor.
