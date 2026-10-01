# Touch controls

Phone overlay (`touch_controls.gd`): floating move stick on the left, drag-to-look on
the right, JUMP, USE, FIRE and a pause button. Shown only while `Controls.touch_visible()`.

`attack_input.gd` presses `primary_action` and `gun_fire` (what the left mouse button
does) via `send_attack()`. The FIRE button holds them while touched, and the controller
right trigger (`JOY_AXIS_TRIGGER_RIGHT`) presses them once past 0.5 and releases below
0.3. The right bumper stays bound too. Desktop bindings are unchanged.

The shared web `shell.html` preserves browser reload and native macOS screenshot
shortcuts before Godot's canvas handler can prevent their defaults. Mac pointer
release and click-to-resume are owned by `features/control_scheme/system_shortcuts.gd`.

When the server refuses a client for a version mismatch, the login screen's "Reload
page" button reloads with `?v=<server build>`. The shell appends that `v` to the engine
script and to same-origin `fetch()` requests (WASM, PCK), so browsers bypass their
cached bundle instead of reloading the stale build forever (#371).
