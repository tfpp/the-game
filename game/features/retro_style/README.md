# PS1 presentation

World surfaces use nearest-neighbour sampling with mipmaps, matte vertex lighting,
and low-polygon silhouettes. The casino's textured finishes add restrained
ordered dithering, mapped in world space so textures never swim when the camera
turns (an earlier affine blend made props appear to slide). This runs in the
surface shader, independently of the optional viewport effect below; there is no
depth-of-field or bloom pass.

All fourteen referenced world-image imports are capped at 128 pixels on the longest
side (square artwork is 128×128; the sky panoramas keep their aspect ratio).
Original source artwork remains available for editing. Font atlases, UI atlases
and streamed arcade screens retain their resolution so text and games stay usable.
Cards, chips and prompts stay legible; multiplayer gameplay keeps its existing owners.

`RetroStyle` styles existing and newly streamed meshes in bounded batches, then
stops processing. Materials and primitive meshes are handled once per resource;
weak caches do not retain unloaded rooms. Authored shader materials are preserved, including the world builder's baked
lightmaps. Standard materials with `per_pixel_lighting` metadata retain per-pixel
lighting so broad procedural surfaces do not interpolate illumination from only
their corners.
Remote-player movement and gameplay replication stay with their original owners.

Mobile and desktop use the same rendering settings: native 3D resolution by default,
authored shadows and light masks, and authored prop draw distances. RetroStyle
does not override viewport resolution or anti-aliasing, including on resize.
There is no mobile-only local-light budget or small-prop distance cutoff.
Universal material/mesh styling and room-based visibility still apply.

On Android, iOS and touch browsers (including iPad desktop user agents), the HUD
retains orientation-aware UI scaling (480×720 portrait, 960×540 landscape virtual
layout sizes). Physics still catches up at most two steps per frame to avoid
slow-frame spirals. The existing desktop-only radar remains hidden.

For a reproducible native mobile-layout visual/counter probe:

```sh
godot --path game res://tests/features/retro_style/retro_probe.tscn -- --retro-mobile
```

The console reports renderer counters and saves day/night screenshots under /tmp.
The probe simulates touch controls and checks native 3D scale. Run without
--retro-mobile for desktop. These runs do not establish physical-phone frame rate;
removing the graphics restrictions increases rendering work on phones.

Models use texture artwork by default. Casino palette meshes combine a shared
128px detail atlas with per-vertex tints and model-space UVs. Older solid-colour
StandardMaterial3D surfaces keep their plain colour with matte vertex shading: a
shared grain albedo used to be multiplied in, but it darkened guns, gnomes and other
dark props to near black. Authored texture/UV setups and custom shaders are preserved.
This includes streamed props because it uses the existing bounded material styling queue.

## Experimental posterization

Open the main menu (Esc, controller Start, or touch pause), then **Settings →
Graphics**. The focusable, touch-friendly strength slider applies immediately and
saves locally through SettingsStore (`posterization`), not to the server/account.
Zero (the default) is **Off** and skips the fullscreen draw and screen-texture copy.
Increasing strength reduces RGB steps logarithmically from 256 to 4 per channel
(roughly 8 to 2 bits/channel, including 32 steps at 50%). This is a retro
reduced-color approximation, not an exact historical indexed or RGB565 palette.

`posterization.gd` is a child of this feature's existing scene and implements the
existing `settings_pages` interface; `set_strength(float)` clamps and persists the
local preference. A single nearest-sampled, no-mipmap screen read in a CanvasLayer
at -1 quantizes the completed 3D viewport before HUD/menu canvases. This includes
transparent world surfaces, streamed rooms, arms, holdables and generated guns,
which already render as 3D in that viewport, in first person and F3 alike.
No materials, camera masks, physics, networking, resolution or shared state change.
The same local choice survives respawn, reconnect and new rooms; other players
choose independently. Headless/dedicated servers do not allocate the effect.
At nonzero strength it costs one fullscreen copy/pass; no CPU per-frame polling.
WebXR hides canvas layers while immersive, so this canvas effect is not applied
inside VR (the saved choice resumes on exit).

Tests: `tests/features/retro_style/test_posterization.gd` plus existing retro and
settings suites. A real Compatibility-renderer pixel probe checks 3D world and
equipped-item-layer coverage, authored shader surfaces, HUD exclusion, Off identity
and resize:
`xvfb-run -a godot --path game res://tests/features/retro_style/posterization_probe.tscn`.

WebXR owns render scale while immersive and restores the prior scale on exit.
RetroStyle's UI resize handling leaves that scale intact in either mode.
