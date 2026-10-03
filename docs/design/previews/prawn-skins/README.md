# Prawn skin crate review

Actual Godot 4.7 Compatibility renders of the base game and this feature, not
concept art. The collection is seeded **only in the capture test** to review all
examples without grinding. No production cheat endpoint is added.

- `crate-in-shop.png`: reused wooden crate, cream prawn stencil, wall-mounted sign,
  gun wall and neighbouring shelves. Floor/approach/wall contact are also tested.
- `crate-contents.png`: all five Harbour Prawn Pot outcomes, actual painted models
  and exact 60/25/10/4/1 percent chances; purchase below the scroll.
- `skin-preview.png`, `painted-pistol.png`: the same Crown Prawn shader on actual
  classic geometry. Stats and attachment markers remain unchanged.
- `reveal.png`: 2.4-second decelerating reel; decorative cards use only the opened
  crate's contents and configured weights. The winning card is already committed.
- `phone-contents.png`, `phone-preview.png`: 390×844 logical viewport, scrolling
  content and touch-sized actions, including duplicate exchange.

Reproduce from `game/`:

```sh
xvfb-run -a godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/pawn_shop/skin_capture.tscn -- /tmp/prawn-skins
```

Reviewed station floor placement, sign contact, coarse paint, actual preview models,
reel visibility and desktop/phone readability. These native captures do not
measure browser GPU performance or physical controller/touch feel. Mesa reports
two texture-leak messages at renderer shutdown; rendering and headless gameplay
checks complete, and no new runtime textures are authored for this feature.
