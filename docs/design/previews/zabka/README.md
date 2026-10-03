# Żabka rendered review

Actual main-game Godot 4.7.2 Compatibility renders at 1280×720 (Mesa llvmpipe),
not concept art or a browser FPS measurement. `zabka.png` shows the fourth bay
from the plaza; `frogs.png` shows all three live frogs and the glass enclosure.
The native capture uses the real offline colony; it does not spawn mock animals.

Reproduce from the repository root:

```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/strip_mall/capture.tscn -- /tmp/zabka-review
```

No external artwork is shipped. Green/white branding and coffee/hot-dog wording
were checked against Żabka's own café description:
https://zabkagroup.com/pl/convenience/zabka-cafe/ . The modeled pixel-letter signs
are an in-game interpretation, not an imported official logo.
