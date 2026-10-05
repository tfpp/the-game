# Web budget check (Phase 1 F4, first pass)

Recorded **2026-10-05** on base `57f35c98` with Godot `4.7.2.stable` and the
`gl_compatibility` renderer. This is a census and native measurement, **not** a
browser profile: the CI runner has no web export templates, so no web build was
made. F4 stays open until someone profiles the exported build in a browser.

## How to repeat

```bash
cd game
xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
  res://tests/features/profiler/web_budget_probe.tscn | grep WEB_BUDGET
```

The probe (`tests/features/profiler/web_budget_probe.gd`) loads `main.tscn`, counts
the Crown with `SceneCensus` (`features/profiler/scene_census.gd`), then creates a
private garage and Rain Alleys excursion, moves the local player into each return
cab and repeats the census. It then samples 240 frames at each spot. In a browser,
enable the frame graph with `profiler 1` in the backtick console at the same spots.

## Census

| Area | Lights (omni/spot/dir) | Shadowed | Lights reaching view | Processing nodes | Physics nodes | Mesh nodes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Crown (whole main scene) | 37 (31/2/4) | 2 | 7 at spawn | 257 | 119 | 1697 |
| Garage instance | 8–17 (omni) | 0 | 5 at arrival | 46 | 57 | 1078 |
| Rain Alleys instance | 6 (omni) | 0 | 8 at arrival | 8 | 5 | 45 |

Garage tube lights flicker and fail, so the lit count varies with time. Headless
(17) counts every tube before the first failures; the rendered sample saw 8.

Native draw info at the sample points: Crown 82 draw calls / 318 objects, garage
83 / 255, alley 114 / 286. Frame times under Xvfb were about 100–130 ms, but that
runner renders with the llvmpipe software rasterizer on four CPU cores; they
measure the CPU rasterizer, not the game, and are not a web number.

## Budget guard

`tests/features/profiler/test_web_budget.gd` fails if the Crown gains more than 2
shadowed or 40 dynamic lights, or if a slum instance gains any shadowed or
directional light, or more than 18 (garage) / 8 (alley) lights. Raise a limit only
with a browser measurement showing it is affordable.

## Findings to follow up in Part 2

- The Crown keeps 257 processing nodes while a player is in a slum: the Crown is
  not unloaded on clients (A3's deferred Crown unloading). Its 4 directional lights
  are hidden by render zones in the slum, so they cost no light passes there.
- The garage's 1078 mesh nodes are mostly saved GridMap/tile meshes; draw calls stay
  low (83), so it is not the bottleneck it appears to be.
- Per-frame animation cost of crowds is covered in
  [profiling-animation.md](profiling-animation.md).
