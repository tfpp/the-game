# Touch controls

Phone overlay (`touch_controls.gd`): floating move stick on the left and a fixed AIM
stick on the right, aligned horizontally at rest. Smaller FIRE, USE and JUMP targets
sit in a row above AIM; CAM and pause sit at the top right. Layout scales to leave
separate thumb zones in portrait and short landscape viewports, respecting safe areas.
Shown only while
`Controls.touch_visible()`. CAM calls the existing third-person camera's guarded
`toggle_camera()` through the `third_person_camera` group. Right-side swipes call
`orbit_look()` in third person, falling back to normal player aim in first person (or
if the feature is absent). Camera taps do not claim the look finger; move, look and
action fingers remain independent. See `features/third_person/README.md`.

First-person AIM is **off by default**: swipe anywhere on the right side outside the
action/menu buttons to aim, including where the hidden stick would be. Enable or disable
**First-person aim joystick** in **Settings > Touch controls** (tap II, then Settings).
The preference is saved locally with SettingsStore, including browser localStorage.
Third person always offers AIM, independently of that preference. Hold the AIM stick
off-center for continuous player aim; return to center or lift to stop. It uses the existing radial deadzone and Settings > Controls
controller-stick sensitivity (radians/second), independent of rendering rate or viewport
pixel scaling. Right-side swipes outside AIM retain drag look / third-person orbit.
`aim_center()` and `move_center()` expose idle centers in the overlay's scaled UI space;
button-center helpers use that same space for both drawing and hit testing. Cancel,
resize, pause, focus loss, device changes and modal UI clear held touch input.
This is local input only: Player keeps existing aim replication and combat keeps its
server validation; no new RPC or shared state is introduced. The overlay joins the
existing `settings_pages` group and owns the local `touch_controls` preference store.
Disabling AIM or returning to first person with it disabled releases held stick input;
a fresh touch in its former area can then start a swipe.

`attack_input.gd` presses `primary_action` and `gun_fire` (what the left mouse button
does) via `send_attack()`. The FIRE button holds them while touched, and the controller
right trigger (`JOY_AXIS_TRIGGER_RIGHT`) presses them once past 0.5 and releases below
0.3. The right bumper stays bound too. Desktop bindings are unchanged.

The shared web `shell.html` preserves browser reload and native macOS screenshot
shortcuts before Godot's canvas handler can prevent their defaults. Mac pointer
release and click-to-resume are owned by `features/control_scheme/system_shortcuts.gd`.

Before Godot requests pointer capture, the shell focuses the canvas synchronously
within the original gesture and checks document focus. Background pages stay unlocked;
browser promise/synchronous refusals are handled without an unhandled rejection.
No focus event or timer retries capture. The existing Click to play / Resume UI
observes actual browser lock state and accepts a fresh click when focus returns.
The guard is canvas-local; native, touch and controller input are unchanged.
Run `node game/tests/features/touch_controls/pointer_lock_test.mjs` from the repository
root for dependency-free focus/refusal/recovery tests of the shipped shell script.

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
