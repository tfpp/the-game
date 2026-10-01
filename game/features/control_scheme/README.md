# Controls

`control_scheme.gd` owns the Settings > Controls page, handedness presets,
sensitivity and saved per-action bindings. `input_bindings.gd` supplies the catalog.
The View section includes third-person toggle (F3) and camera orbit (hold middle
mouse); both use the existing capture, persistence, conflict warning and reset APIs.

`system_shortcuts.gd` releases the captured pointer when Command is pressed during
play on macOS (including Mac browsers). This happens before the final screenshot
key, which macOS may consume. Use Command-Control-Shift-4 to copy a selection, or
Command-Shift-3/4/5 for the other native screenshot modes. The OS creates the image.

The helper uses the existing `modal_ui` group and `Controls.pause()` to keep the
camera still and the automatic Esc menu hidden, including across focus changes.
After taking or cancelling the screenshot, release Command and left-click the game
to resume; that click is consumed. Esc opens the normal menu instead. Other Command
shortcuts also release capture. Existing menus are left alone. This is local to each
client; there is no network or persistent state. Touch/controller controls and other
platforms are unchanged. The web shell also excludes screenshot chords from Godot's
canvas key handler, just as it already does for browser reload shortcuts.
