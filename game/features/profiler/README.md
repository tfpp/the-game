# Local frame profiler

## Temporary animation bisect

See [the animation profiling investigation](../../../docs/profiling-animation.md)
for the experiment record, code findings, current hypothesis and optimization
measurements.

Normal animation startup is restored after the bisection. The optional
`freeze_animations_on_start` export can still freeze the suspect groups in graphical
debug runs after initial setup, with an editor Output status message. It defaults
off; release exports and headless runs do not auto-freeze.

Use the backtick console while standing at the same position and view angle:

```
profile_animations
profile_animations all 1
profile_animations all 0
profile_animations guests 1
```

`0` freezes and `1` resumes. Each group can be changed independently:

| Group | Work skipped |
| --- | --- |
| `guests` | SalonGuestModel updates, including seated guests and Rusty |
| `dealers` | CardDealerModel updates, including idle staff |
| `musicians` | Mariachi body, hand and instrument animation |
| `patrons` | Wandering CasinoPatron body poses, including Mitch and Trump's reach |
| `players` | BlockPlayerModel player avatar updates |

These switches only skip local visual updates. Characters still render, and player
movement, NPC routes, collisions and networking keep running. Held-item/emote
overlays and other NPC families are outside this first experiment. Initial poses
still run. Switches reset on exit and are neither saved nor replicated.

`profile_fingers 0` skips `SkinnedHuman` finger curls while body and hand/arm poses
continue. `profile_fingers 1` restores them; `profile_fingers` queries the state.
Fingers retain their last curls while frozen. This is an independent switch, enabled
by default and unaffected by `profile_animations all`. Use it with just `patrons`
or `guests` enabled to isolate their finger work. Direct digit curls (Mitch's peace
sign) are included. The switch applies to all shared human rigs on this client.

`profile_skeleton 0` skips the bone conversions and writes in `SkinnedHuman.pose()`.
Animation calculations, dummy rig pivot/root transforms and arm-visibility shader
writes continue. Bones retain their last main pose; separate hand IK and emote
overlays can still change them. `profile_skeleton 1` restores the pass, and
`profile_skeleton` queries it. Like the finger switch, it starts enabled, applies
to all shared human rigs locally, and is unaffected by group switches.

To narrow a patron result, disable all groups, enable only patrons, leave
`profile_fingers 0` throughout, then compare `profile_skeleton 1` and
`profile_skeleton 0`. This separates the main skeleton pass (and engine updates
it triggers) from the remaining animation calculations and rig transforms.

The initial baseline applied the patron skeleton twice: during avatar animation
and again after NPC adjustments. This checkout now defers the first pass, caches
fixed rest transforms, and avoids rewriting unchanged bones. The existing switches
still apply to the optimized path. Ordinary roaming patrons (looks 0–3) now use
shared idle/walk bone clips blended by a manually advanced AnimationTree, with a
targeted head overlay. Named/seated characters retain the procedural path. The
skeleton switch also freezes native clip evaluation. Guest updates remain at
10 Hz, with staggered deadlines independent of their visual phase; the initial
baseline started their timers together. Seated guests still recurl fingers while
reaching for the table.

Record an all-on baseline on this checkout, then all-off, then enable groups one at
a time. Close the console and profiler panel before collecting each sample; ignore
the first few frames after a toggle. Compare the editor profiler's Process Time
and Script Functions total. This isolates the animation cost without simultaneously
changing lights, shadows, news-screen rendering or zone refreshes.

## Frame capture

Open the existing console with backtick / **Esc → More → Console**:
- `profiler 1`: enable the passive frametime graph.
- `profiler 0`: disconnect capture and hide the graph (retained traces remain).
- `profiler`: query enabled state.
- `profiler_budget 16.667`: set the local budget in milliseconds (1–1000).
  Default is exactly 1000/60 ms, independent of monitor refresh rate or FPS cap.
- `profiler_clear`: discard the graph, missed frames and selected trace.

Close the console and choose **Esc → More → Profiler** to inspect misses. Click/tap a row,
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

## Web budget census

`SceneCensus.count(root)` counts visible dynamic lights (shadowed, by type),
processing and physics-processing nodes and mesh nodes under a node;
`SceneCensus.lights_reaching(root, point)` counts lights whose range covers a point.
`tests/features/profiler/web_budget_probe.tscn` prints the Crown and slum numbers and
`test_web_budget.gd` guards the light budget. See
[profiling-web.md](../../../docs/profiling-web.md).
