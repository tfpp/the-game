# Investigating character animation frame time

Investigation started **2026-10-02**, using Godot
`4.7.2.stable.official.ed1daf0bf` on macOS. The diagnostic and optimization work is
on `chore/profile-animation-bisect`, based on `aa79e686`. This is a record of the
observations and working hypothesis, not a claim that the complete frame-time
problem has been solved. After the first optimization, the user supplied another
graph and confirmed that `profile_skeleton 0` still made the game substantially
faster. Reducing repeated script work did not eliminate the main-pose cost.
The first native-clip migration following [animation.md](animation.md) is now
implemented for ordinary roaming patrons; its measurements are recorded below.

## Most probable hypothesis

**Per-frame patron body poses dirty the shared human skeletons and trigger
substantial engine work downstream of the script calls.** Repeated pose passes
and fixed-rest calculations add avoidable CPU work. Guests likely contribute
bursts because their pose-update timers start together.

The strongest evidence is the sequence of controlled animation switches:

- Toggling patron animation had the largest reported effect among the groups.
- Disabling finger curls produced no noticeable improvement in the user's graph.
- Disabling the main skeleton-pose pass produced a large, sustained downward step
  in the supplied graph, while animation calculations and rig transforms remained
  active.

This narrows the cause to the main pose pass **and the work it triggers**. It does
not yet identify the split between script calculations, native skeleton updates,
skin/render data updates, GPU work, or synchronization waits. The hypothesis that
native downstream work accounts for much of the gap between script time and
Process Time is an inference, not a measured attribution.

Finger curls can take measurable CPU time without changing total frame time much:
the body pose still dirties the skeleton when fingers are disabled. That is a
plausible explanation for the finger result, rather than evidence that finger
calculations are free. Lights, shadows, other rendering work and pacing have not
been independently ruled out as contributors to the remaining frame time.

## Initial evidence and timing interpretation

The first custom-profiler example was:

```text
Frame #11750: 21.000 ms / 16.667 ms budget
Wall-clock landmarks (gaps include engine work, waiting and pacing).
Not script call stacks or CPU/GPU attribution.
0.000 ms (+0.000) Process frame boundary
7.500 ms (+7.500) RenderingServer pre-draw
18.700 ms (+11.200) RenderingServer post-draw (CPU submission, not GPU completion)
19.500 ms (+0.800) Physics tick begins
21.000 ms (+1.500) Next process frame boundary
```

The frame exceeded the 60 FPS budget by about 4.33 ms. The largest landmark gap
was the 11.2 ms between pre-draw and post-draw. This made rendering/update/waiting
work worth investigating, but the gap is not an 11.2 ms GPU measurement. Likewise,
the final 1.5 ms is not an exclusive measurement of physics.

In a separate selected editor-profiler frame, the user reported about **17 ms
Frame Time**, **16.32 ms Process Time**, and the screenshot showed **5.60 ms Script
Functions**. These are different observations from the 21 ms landmark example.
Selected rows from that screenshot were:

| Function | Displayed time | Displayed count |
| --- | ---: | ---: |
| `SkinnedHuman.set_finger_curl` | 2.93 ms | 352 |
| `SkinnedHuman.pose` | 2.79 ms | 115 |
| `SkinnedHuman.set_digit_curl` | 2.57 ms | 176 |
| `SalonGuestModel._process` | 2.34 ms | 27 |
| `SalonGuestModel._update` | 2.33 ms | 27 |
| `BlockPlayerModel.animate` | 2.07 ms | 63 |
| `PatronModel.pose` | 1.26 ms | 22 |
| `PatronModel.sit` | 1.23 ms | 20 |
| `CardDealerModel._process` | 0.71 ms | 11 |

These rows are not independent slices of the frame. Inclusive function time
contains nested calls; use Self scope when inspecting exclusive script work.
The initial screenshot's scope was not separately recorded, so do not sum its
rows. See the [Godot profiler documentation](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/the_profiler.html#scope-of-measurement-and-measurement-windows).

In Godot 4.7.2, the process timer brackets scene processing, a message-queue flush,
navigation processing, renderer synchronization and drawing. Process Time is
therefore broader than GDScript execution. Subtracting 5.60 from 16.32 leaves about
10.72 ms, but does not identify its owner or make it all rendering time. See
[Godot's process timer](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L4689-L4724).

The repository selects `gl_compatibility` in
[`game/project.godot`](../game/project.godot). CPU/GPU attribution has not been
collected for this investigation.

### Local profiler implementation

[`frame_capture.gd`](../game/features/profiler/frame_capture.gd) measures monotonic
wall-clock time between `SceneTree.process_frame` boundaries.
[`profiler.gd`](../game/features/profiler/profiler.gd) adds physics-frame and
RenderingServer pre/post-draw timestamps. These landmarks include engine work,
waiting, scheduling and pacing; they are not sampled call stacks. Post-draw marks
CPU submission, not GPU completion.

Capture retains 240 graph intervals and the latest 120 missed frames, with up to
128 landmarks per frame. UI refresh is throttled to four times a second. The local
graph scales against at least twice the budget and expands for larger samples.
The editor graph and local graph are different instruments. The supplied cropped
graph has no readable numeric axes, so its step change is qualitative evidence;
no millisecond or percentage reduction was inferred from it.

## Bisection record

| Step | Intervention or observation | Result and interpretation |
| --- | --- | --- |
| 1 | Inspect wall-clock landmarks and editor script rows | Rendering/update work was plausible; script rows suggested character posing, but did not establish the cause. |
| 2 | Add switches for guests, dealers, musicians, patrons and players | Allowed one visual animation family at a time, with characters still present. |
| 3 | User compares groups | Patrons produced the greatest frame-time jump. Enabling guests increased variability. Numbers were explicitly described as rough. |
| 4 | Add independent `profile_fingers` switch | User reported no noticeable graph effect. Finger curls became a lower priority for total-frame optimization. |
| 5 | Add independent `profile_skeleton` switch | User reported a large change after `profile_skeleton 0`, accompanied by a graph with a sustained lower band. Strongest evidence for the main body-pose path. |
| 6 | Remove repeated main posing, cache rests, avoid unchanged writes | Local CPU benchmark and pose parity checks passed. |
| 7 | User repeats the skeleton toggle after optimization | Another graph shows a large downward step with `profile_skeleton 0`. Substantial main-pose/downstream cost remains; begin the migration described in `animation.md`. |
| 8 | Replace ordinary idle/walk posing with shared clips and AnimationTree; stagger guests | First native graphical crowd comparison improves median frame time from 24.974 to 21.514 ms. Casino-scene and web-client benefits still need measurement. |

The suggested step-5 setup was all groups disabled, only patrons enabled, fingers
disabled throughout, then skeleton enabled versus disabled. The user confirmed
the skeleton toggle and large graph change; the complete switch state and numeric
before/after frame timings were not captured separately. Repeat and record them
before assigning a precise cost.

## Code findings

### Patron movement continues when patron posing is frozen

[`CasinoPatron._process()`](../game/features/casino_patrons/patron.gd) smooths remote
positions, updates visibility/collision state, derives walking and falling state,
advances idle time, and updates the body-root and collider transforms. The patron
switch guards only `_body.pose(...)`. Server route following, collision, replicated
state and those surrounding updates continue.

This means the patron result isolates visual pose work more closely than removing
NPCs would. It does not imply patron AI or networking were removed during the
test. There is also no camera-distance/frustum gate on this patron body-pose call,
and it is still called when `net_alive` hides the body. These are code findings,
not separately measured costs or changes made in this investigation.

### Avatar animation and the repeated main pass

[`BlockPlayerModel.animate()`](../game/features/player_models/block_player_model.gd)
calculates locomotion/stride, blends ten body pivot rotations, sets arm visibility,
updates rig height/landing/bob/drop transforms, and handles player punch posing.
It normally applies `human.pose(...)` afterward. NPC avatar nodes do not run their
own player `_process()` loop; their owning models call `animate()` directly.

Before optimization, [`PatronModel.pose()` and `sit()`](../game/features/casino_patrons/patron_model.gd)
called `animate()`, then changed the NPC head/limp or seated pose, then applied
`human.pose(...)` again. The intermediate main skeleton pass was overwritten by
the final one. Both passes also reset resting finger curls.

| Path | Main passes before | After first optimization | Work after or around them |
| --- | ---: | ---: | --- |
| Ordinary patron `pose()` | 2 | 1 | Head turn, flinch, limp and limb adjustments |
| Patron `sit()` | 2 | 1 | Seated hip, leg, torso, arm and head adjustments |
| Trump while reaching | 3 | 2 | `reach()` changes the right arm and reapplies the main pose |
| Mitch with a raised peace gesture | 3 | 2 | Extra arm pose, then individual finger overrides |
| Mitch's intern | 2 | 1 | Two hand IK reaches to wheelchair handles |
| Seated salon guest | 2 | 1 | Two hand IK reaches to the table and curls of 0.2 |
| Musician update | 3 | 2 | Base patron pose, then musical sway/head pose and instrument grips |
| Dealing card dealer | 1 | 1 | Animated two-hand IK and curls of 0.35 |
| Idle/non-dealing card dealer | 2 | 2 | Head turn applied after avatar animation |

Counts describe the procedural paths before the later native-clip migration, not
all possible overlay combinations. That migration replaces ordinary walkers'
per-update main pass with native base evaluation and one head overlay. It does
not combine every remaining layered procedural pass.

### Shared skeleton work

[`SkinnedHuman`](../game/features/player_models/skinned_human.gd) instantiates one
shared imported human asset per avatar, finds the Skeleton3D/surface, and caches
bone-name indices. The asset has 45 bones, including three joints for each of ten
digits. Individual avatars have their own skeleton state and material.

The main `pose()` pass writes the arm-visibility shader parameters, converts the
ten pivot rotations to bone rotations, resets both forearm/wrist positions and
wrist rotations, and restores resting finger curls of 0.12.

Previously `_bone()` fetched and orthonormalized global rest bases for the bone
and its parent, inverted the parent basis, formed the Euler basis, converted the
result to a quaternion, and wrote it every call. Name indices were already
cached; rest calculations were not. No GDScript runtime code in the repository
changes bone rests or hierarchy, so those fixed rest calculations can be cached.

Godot's position/rotation setters dirty the skeleton even for identical values;
dirty requests can be deferred/coalesced. Repeated setters therefore do not prove
a complete native update happens once per bone or once per script pass. Also,
`get_bone_global_rest()` refreshes transforms when **rest** is dirty, not after every
pose write. See the [4.7.2 skeleton implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/skeleton_3d.cpp#L738-L897).

### Fingers, IK and overlays

`set_finger_curl()` visits five digits; `set_digit_curl()` visits three segments,
reads rest orientation, derives a local curl axis, creates a quaternion and
applies it. Those loops explain why finger functions appeared high in the script
list, but the user's full-frame toggle result takes precedence over that ranking.

`reach_grip()` queries current global bone poses, solves arm reach, optionally
extends joint positions for distant item markers, aims the upper arm/forearm,
reveals the arm and curls the fingers. Mitch's intern, guests, dealers and
musicians add such reaches after body posing. `orient_grip()`, `left_gesture()`,
`six_seven()`, `place_shoulder()` and `_aim_bone()` also operate outside the main
`pose()` pass. Freezing the main pass does not freeze every skeleton writer.

This matters for unchanged-write checks: compare against the **actual current
bone value**, not just a cached last body pose. An item or emote overlay may have
changed the bone since the body last wrote it. The next body pass must restore it.

### Guest timing and other animation families

[`SalonGuestModel`](../game/features/casino_patrons/salon_guest_model.gd) updates
visible-in-tree guests at a 0.1-second interval. In the inspected baseline,
`_since` started at zero and reset to zero after each update. Guests spawned
together could therefore update on the same frames. `_time = chosen * 1.7`
offsets their visual idle motion, but did not stagger their timer. This remains
the leading explanation for the reported guest variability. The migration now
staggers deadlines; its graphical variability benefit has not been measured.
Seated guests also add
both table reaches after `sit()`. `is_visible_in_tree()` is not a camera-frustum
test.

[`CardDealerModel`](../game/features/casino_patrons/card_dealer_model.gd) updates
dealing hands each process frame; non-dealing staff pose about every 0.1 seconds.
[`MariachiMusicianModel`](../game/features/mariachi_band/musician_model.gd) caps
updates at 30 Hz and skips them beyond 32 metres from the camera. These scheduling
differences can make different groups affect average cost and variability
differently. Their individual frame-time costs have not been quantified.

## Diagnostic controls and their limits

[`animation_bisect.gd`](../game/features/profiler/animation_bisect.gd) owns static,
local, session-only flags. [`commands.gd`](../game/features/console/commands.gd)
provides validated console commands and completion; it does not evaluate arbitrary
code. There are no RPCs, persistence or per-frame tree scans in the switches.

| Command | Work skipped by `0` |
| --- | --- |
| `profile_animations guests 0` | Guest `_process()` updates |
| `profile_animations dealers 0` | Dealer `_process()` updates |
| `profile_animations musicians 0` | Musician `_process()` updates |
| `profile_animations patrons 0` | Wandering patron model poses, including Mitch/intern and Trump's reach |
| `profile_animations players 0` | Player-avatar `_process()` updates; direct NPC `animate()` calls are unaffected |
| `profile_fingers 0` | Shared human curl methods, including direct digit curls such as Mitch's peace sign |
| `profile_skeleton 0` | Bone work in `SkinnedHuman.pose()`, after its shader writes; now also native patron clip evaluation and its head overlay |

`profile_animations all 0/1` changes all five groups. Commands without values query
state. Finger and skeleton flags are independent, start enabled, and are **not**
reset by `profile_animations all 1`. They apply to every shared human rig on the
client, including callers outside the five groups. Some overlays write bones
directly and bypass the curl methods.

For the original procedural skeleton test, dummy rig pivot/root transforms, animation calculations
and arm-visibility shader writes remain active. Keep fingers disabled throughout
the comparison to avoid independent curl writers confounding it. Other NPC
families and held-item/emote overlays remain outside the group bisection.

During bisection, [`feature.tscn`](../game/features/profiler/feature.tscn) enabled
`freeze_animations_on_start`. Graphical debug runs with that option wait for two process-frame
signals and freeze the five groups, allowing initial setup first. Headless runs
and release builds do not auto-freeze. The freeze happens even if graph capture
is disabled. Exiting the profiler feature resets all flags. **Normal startup is
now restored:** the option defaults off, and characters animate without console
commands.

## Optimization implemented

The optimized path is separate from freezing animations:

1. Add an optional `apply_skeleton` argument to `BlockPlayerModel.animate()`,
   defaulting to true. Patron `pose()` and `sit()` pass false, apply NPC pivot
   adjustments, then perform their existing final main skeleton pass.
2. Cache local rests, orthonormalized global rest bases and inverse parent rest
   bases once in `SkinnedHuman._ready()`.
3. Check actual bone positions/rotations before main-pass resets and writes.
   Route digit rotation writes through the same exact-value check. Changing
   bones still update; the check does not introduce a motion threshold.

For this first procedural optimization, update rates and final poses were preserved.
Distance culling, batching all overlays, and renderer changes were not implemented.
Caches assume this imported rig's rests/hierarchy remain fixed; future runtime
retargeting would need to refresh them.

## Validation and measurements

### Pose correctness

A temporary GDScript scene captured all 45 global bone transforms across 49 pose
samples before and after optimization: walking, idle, knockdown/flinch, sitting,
reaching, returning from extended item IK, Mitch's raised peace gesture and his
intern's handle grips. The serialized transforms were identical. This is sampled
parity, not exhaustive proof for every animation combination.

Permanent tests in
[`test_skinned_pose.gd`](../game/tests/features/player_models/test_skinned_pose.gd)
verify that identical main poses cause no further `pose_updated` signal, a changed
head still updates, and an extended item grip is fully restored by the next body
pose. The final optimization verification passed **1,659 tests**, format/lint,
imports, release-note validation, offline smoke, multiplayer smoke and Go checks
through `harness/verify.sh`. Earlier diagnostic-only runs passed 1,657 tests.
Pre-existing asset `.import` edits were preserved byte-for-byte.

### Local CPU benchmark

A temporary headless Node scene built 40 ordinary `PatronModel` instances with
looks `index % 6`. Each trial called every model's `pose()` for 300 simulated
steps of `1/60` second: half walking, half idle, no limp/flinch, idle phase
`step * 0.016 + index`. Four trials were run before and after optimization, both
with fingers disabled and enabled. Setup was excluded from timing, using
`Time.get_ticks_usec()` around the nested pose-call loops.

| Fingers | Before, ms per batch of 40 poses | After, ms per batch of 40 poses | CPU reduction |
| --- | ---: | ---: | ---: |
| Disabled | 0.767 average (0.764–0.770) | 0.501 average (0.500–0.505) | 34.7% |
| Enabled | 2.202 average (2.197–2.211) | 1.323 average (1.315–1.331) | 39.9% |

The loop did **not yield between simulated steps**. It measures synchronous pose
calls, including native work invoked immediately by them, but excludes rendering,
pacing and deferred per-frame engine updates. These are not game-frame timings
and do not establish a 35–40% overall FPS/frame-time improvement. The graph result
with fingers disabled and this CPU benchmark answer different questions.

Temporary benchmark/parity/probe scenes and logs were kept under `/private/tmp`,
not committed as runtime dependencies. The method above records the benchmark
parameters without relying on those temporary files surviving.

### Native clip migration

Ordinary roaming patrons (looks 0–3) now use the shared
[`locomotion.tres`](../game/assets/casino_patrons/animations/locomotion.tres)
AnimationLibrary. Its idle and looped walk tracks are baked from the existing
steady procedural gait, with 48 samples per stride and a matching loop boundary.
The checked-in native [baker](../game/features/casino_patrons/animation/bake_clips.gd)
and scene reproduce the resource without another authoring dependency:

```sh
godot --headless --path game res://features/casino_patrons/animation/bake_clips.tscn
```

[`patron_locomotion.gd`](../game/features/casino_patrons/animation/patron_locomotion.gd)
gives each character an AnimationTree blend state and manual playback clock; the
AnimationPlayer only supplies the shared library. Nine body-bone rotation tracks
replace per-frame limb pivot posing and GDScript bone conversion. The torso
accessory anchor and rig bob retain native tracks; the necessary head anchor and
one head-bone overlay retain procedural turning/flinch. Head is excluded from
the base clip tracks. Manual tree advancement completes before that targeted
overlay, so ordering does not depend on separate automatic `_process()` callbacks.

Named characters, seated poses, player locomotion and their layered actions keep
their procedural ownership during this first migration. A migrated patron also
uses that path while knocked down, then seeks back to its current stride phase on
recovery. NPC routing/networking still own horizontal movement; clips do not add
root-motion authority. Guest deadlines now have a position-derived scheduling
offset separate from their visual phase. Each update consumes accumulated elapsed
time, retains the deadline phase, and runs at the existing roughly 10 Hz rate.

The native-clip skeleton switch now stops the complete clip evaluation, including
its two retained anchor/root tracks. Its scope is therefore broader than the
original procedural bone-only switch; do not compare them as identical isolated
interventions. The native path initializes resting hands once and preserves the
independent finger control.

Four tests in
[`test_patron_clips.gd`](../game/tests/features/casino_patrons/test_patron_clips.gd)
cover actual skinned-foot stride/stopping, head and knockdown/recovery behavior,
shared resources with independent manual playback, and staggered guest updates
without losing elapsed animation time. Multiple native-rendered gait/idle views
were inspected. These checks are separate from the earlier 49-sample parity test,
which applied only to the procedural repeated-work optimization.

Full migration verification passed **1,663 tests**, imports, format/lint, release
notes, offline and multiplayer smoke checks, and Go checks.

The initial graphical comparison used the Compatibility renderer on an Apple M4
Max, a 640×360 window with VSync disabled, 40 `PatronModel` instances (`look % 6`),
eight columns at two-metre spacing, half walking and half idle, the same camera
and simple lighting in both runs. It warmed up for 90 frames and recorded the next
360 wall-clock process-boundary intervals. The comparison enabled clips on all
40 test models; production enables only the four ordinary looks. It is an isolated
crowd workload, not a capture of the full casino scene.

| Path | Mean frame time | Median | 95th percentile |
| --- | ---: | ---: | ---: |
| Optimized procedural baseline | 25.989 ms | 24.974 ms | 34.567 ms |
| Shared native clip playback | 22.247 ms | 21.514 ms | 29.248 ms |

This first run showed roughly **14% lower median frame time**, with the same
population and graphics settings. Unlike the headless benchmark, these intervals
include drawing and engine work, but still do not attribute CPU versus GPU costs.
It is a preliminary single comparison on one native machine, not a guarantee
of this percentage in the casino, on web clients, or with different active groups.
An exported web comparison was also run in an isolated headless Chrome session
using WebGL2 through ANGLE Metal on the same Apple M4 Max. The same crowd scene,
90-frame warmup and 360-frame samples ran in both states without browser script
errors:

| Web path | Mean frame time | Median | 95th percentile |
| --- | ---: | ---: | ---: |
| Procedural | 16.668 ms | 16.700 ms | 17.500 ms |
| Clips | 16.666 ms | 16.700 ms | 17.400 ms |

Both were effectively at a 60 Hz browser scheduling ceiling. This validates
exported execution and gives no evidence of a median frame-time regression in
that workload; it does **not** establish a web FPS improvement or savings on a
more heavily loaded browser. The real casino scene, Safari, mobile and other
hardware still need representative comparisons.

The web acceptance scene and browser automation were temporary. Release web
templates reject command-line scene overrides, so the scene was selected in a
temporary project configuration; the real `game/project.godot` and export presets
were unchanged. Temporary files added solely for that export were removed after
the test.

## Repeating the graphical test

Use the same renderer, resolution, camera, profiling settings and scene. Keep
VSync/FPS cap settings constant. Close the console and profiler inspector while
collecting samples and disregard toggle/menu frames. Because NPCs move, repeat
comparisons rather than treating one selected frame as a stable population cost.

The saved local viewpoint was position `(11.522, 0.914, 17.915)`, yaw `0.195`, pitch
`0.002` radians. `Player.global_position` is the current local position;
`net_position` is replicated state. To restore that viewpoint, pause at the first
statement of the **local** `Player._physics_process()` and paste into the debugger
Evaluator, with that Player as the current script context:

```gdscript
[set("global_position", Vector3(11.522, 0.914, 17.915)), set("yaw", 0.195), set("pitch", 0.002), set("velocity", Vector3(0, 0, 0)), reset_physics_interpolation()]
```

Resume and let the frame settle. This debugger expression is not an in-game console
command and should not be applied to another peer's player.

Normal startup now enables animations. To repeat the earlier isolated patron
comparison on the migrated checkout, run these console commands individually:

```text
profile_animations all 0
profile_animations patrons 1
profile_fingers 0
profile_skeleton 1
```

Measure the optimized animated state, then run `profile_skeleton 0` and measure
the frozen-main-pass baseline. Toggle back and repeat. Keep finger state fixed.
Separately test normal fingers with `profile_fingers 1`; restore all normal paths
explicitly with `profile_animations all 1`, `profile_fingers 1` and
`profile_skeleton 1`.

Record switch states, Process Time, Script Functions total, typical frame times,
spike frequency and sample duration. Where possible record median/tail values
from numerical samples rather than estimating them from a cropped graph.

## Outstanding work

| Question | Evidence needed next |
| --- | --- |
| How much did the first optimization improve the graphical workload? | No numerical pre/post measurement was recorded. The new skeleton-toggle graph confirms substantial residual cost, not a precise improvement over the original checkout. |
| What fraction remains native/rendering work? | Compare Process Time and script time in both switch states, then collect native CPU or renderer-specific GPU timing if needed. |
| How much does guest staggering reduce spikes? | Deadlines are now staggered and rate/elapsed-time tests pass; a controlled graphical before/after variance comparison is still needed. |
| Are hidden/distant patron poses material? | Measure a separate visibility/distance experiment without changing population or rendering settings at the same time. |
| Are remaining layered passes or IK significant? | Isolate those writers after the main-pass result, especially Mitch/intern, Trump, musicians and idle dealers. |

A large residual gap between animated and frozen skeleton states already showed
that the repeated-work optimization addressed only part of the problem. Keep that result
distinct from correctness tests and the headless CPU speedup. Further changes
should follow the next measurements rather than treating the hypothesis as a
confirmed GPU bottleneck.
