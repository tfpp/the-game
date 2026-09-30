# Local frame profiler

Open the existing console with backtick / **Esc → Console**:
- `profiler 1`: enable the passive frametime graph.
- `profiler 0`: disconnect capture and hide the graph (retained traces remain).
- `profiler`: query enabled state.
- `profiler_budget 16.667`: set the local budget in milliseconds (1–1000).
  Default is exactly 1000/60 ms, independent of monitor refresh rate or FPS cap.
- `profiler_clear`: discard the graph, missed frames and selected trace.

Close the console and choose **Esc → Profiler** to inspect misses. Click/tap a row,
or select it with controller navigation, to display its trace. Esc, controller B,
Close or the menu button dismiss the inspector using the shared modal lifecycle.
Touch uses the console's existing software keyboard; controllers need a keyboard
for commands. No new key/button is reserved. Recording continues while inspecting,
so the graph measures menu frames too, and the profiler itself has some overhead.

## What a trace measures

Each frame is the **monotonic wall-clock interval between SceneTree process-frame
boundaries**, not scaled/clamped `delta` or averaged FPS. The first boundary only
primes capture. Frames strictly exceeding their captured budget enter the miss list.
The graph displays the latest 240 intervals, scaled to their maximum, with a yellow
budget line. Display refresh is throttled to four times per second.

Traces retain timestamped process, physics-tick and RenderingServer pre/post-draw
landmarks with offsets and gaps. These are real observed events; gaps include
engine work, presentation waits, OS scheduling and frame pacing. Post-draw is **CPU
submission, not GPU completion**. Headless/skipped-render frames may have no render
markers. Multiple physics ticks can occur in one interval. No durations are
attributed to individual scripts or features, and gaps are not exclusive CPU costs.
Godot exports do not expose the editor's per-function profiler/call stacks to
GDScript; this inspector is a phase trace, not a substitute for that editor profiler.

Only the latest 120 misses are retained, with a lifetime miss count; each trace
caps landmarks at 128 and reports truncation. Selecting a trace pins a copy even if
the miss list later evicts it. Changing the budget or toggling capture restarts the
in-flight interval, so disabled time and mixed-budget intervals are not captured.

## Ownership and integration

`profiler.gd` owns local capture/UI and registers `frame_profiler` for the console
adapter. `set_enabled(bool)`, `set_budget(float) -> bool` and `clear_capture()`
are its public command interface. `frame_capture.gd` is deterministic with supplied
microsecond timestamps; `frame_graph.gd` is passive presentation only.
The feature loader loads `feature.tscn`; no core wiring is needed.

Disabled by default with no sampling signals or process callback. State is
session-local, never persisted or replicated. Every client (including an offline
host) profiles its own process, not the server or another player's machine.
Respawns/disconnects do not affect local capture; late joiners start disabled.
No personal information, files, network payloads or arbitrary script execution
are collected. Dedicated servers remain disabled unless explicitly invoked locally.

Tests: from `game/`, run
`godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/profiler -gexit`.
