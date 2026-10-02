# Actual Godot strip mall review

Captured with the main game, Godot 4.7.2 Compatibility / Mesa llvmpipe through
xvfb-run, using `tests/features/strip_mall/capture.tscn`. No concept imagery is
presented as a game render. Views show the casino entrance, mall arrival and
overview, return kiosk, canopy underside and planted trough.

`wendys-first-person.png` and `wendys-third-person.png` come from the existing
Wendy's probe, updated to preload the mall. It used offline Use to deliver a
burger before taking both camera-mode captures. Menus and controls are unchanged;
physical touch/controller and browser performance were not manually tested.

The graphical captures completed, but Mesa/Godot emitted texture/resource leak
warnings at shutdown (also observed in the existing Wendy's probe). No script
errors occurred; headless import/tests and the full verification are clean.
These captures do not establish a browser frame-rate improvement or a multiplayer
rendering benchmark.

Reproduce from the repository root:
```sh
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/strip_mall/capture.tscn -- /tmp/strip-mall
xvfb-run -a godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/food_court/wendys_probe.tscn
```
