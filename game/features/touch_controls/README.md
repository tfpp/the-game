# Touch controls

Phone overlay (`touch_controls.gd`): floating move stick on the left, drag-to-look on
the right, JUMP, USE, FIRE, a small CAM button and a pause button. Shown only while
`Controls.touch_visible()`. CAM calls the existing third-person camera's guarded
`toggle_camera()` through the `third_person_camera` group. Right-side swipes call
`orbit_look()` in third person, falling back to normal player aim in first person (or
if the feature is absent). Camera taps do not claim the look finger; move, look and
action fingers remain independent. See `features/third_person/README.md`.

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

The shell caches WebGL2 `getParameter(SCISSOR_TEST)` in JavaScript to avoid a
driver synchronization stall during Emscripten's per-frame state save. Native
`enable`/`disable` still execute; a WeakMap keeps each context independent. The
first read initializes from native state and lost contexts retain native query
behavior. Context loss invalidates the cache; its first use after restoration reads
native state again, preserving changes made by earlier restoration handlers.
Other parameters are unchanged.

Serve `game/` over HTTP and open
`tests/features/touch_controls/scissor_cache.html` in a WebGL2 browser to run the
regression against the actual inline shell implementation. It checks native state
agreement, independent contexts, query counts, GL errors and context restoration.
