# PS1 presentation and mobile optimizations

World surfaces use nearest-neighbour sampling with mipmaps, matte vertex lighting,
and low-polygon silhouettes. A single screen shader applies five-bit RGB colour
with ordered dithering at native resolution. It renders on CanvasLayer -1,
behind the HUD and menus. The casino's textured finishes retain world-space
mapping so textures do not swim when the camera turns. Rendered vertices keep
their original projected positions; no shader changes geometry or collision.
Small palette meshes blend in 35% affine UV interpolation; broad world-mapped
surfaces retain their stable mapping. The effect was inspired by
[Midnight PSX Effects](https://github.com/DiegoSainzPardoLaso/Midnight-Psx-Effects);
its Unity shader cannot be loaded by Godot.

Desktop and mobile render 3D at native resolution. The colour shader samples
each output pixel once, with one screen copy and one canvas pass. Profile the
result on target hardware before making frame-rate claims.

All fourteen referenced world-image imports are capped at 128 pixels on the longest
side (square artwork is 128×128; the sky panoramas keep their aspect ratio).
Original source artwork remains available for editing. Font and UI atlases
retain their resolution so text stays usable.
Cards, chips and prompts stay legible; multiplayer gameplay keeps its existing owners.

`RetroStyle` styles existing and newly streamed meshes in bounded batches, then
stops processing. Materials and primitive meshes are handled once per resource;
weak caches do not retain unloaded rooms. Authored shader materials are preserved, including the world builder's baked
lightmaps. Standard materials with `per_pixel_lighting` metadata retain per-pixel
lighting so broad procedural surfaces do not interpolate illumination from only
their corners.
Remote-player movement and gameplay replication stay with their original owners.

On Android, iOS and touch browsers (including iPad desktop user agents):

- 3D rendering and the HUD use native resolution, with orientation-aware UI scaling
  (480×720 portrait, 960×540 landscape virtual layout sizes).
- Shadow maps, MSAA, screen-space AA and TAA are disabled.
- At most two nearby local lights are active, selected four times per second.
- Small props stop drawing beyond 40 metres; room architecture remains visible.
- Physics catches up at most two steps per frame, so a slow frame doesn't
  snowball into slower ones.
- Decorative sphere/cylinder meshes are capped at 12 radial segments.
- The existing desktop-only radar remains hidden.

No device FPS guarantee is implied by desktop browser emulation. Profile on the
actual target phone before selecting a frame-rate target. For a reproducible native
mobile-profile visual/counter probe:

```sh
godot --path game res://tests/features/retro_style/retro_probe.tscn -- --retro-mobile
```

The console reports renderer counters and saves day/night screenshots under `/tmp`.
The probe also simulates touch controls; browser tests exercise actual touch-device
detection and radar visibility.

The reference salon adds original table, bar, gallery and patron meshes. Their
palette shader computes warm illumination per vertex; indoor texture shaders use
fixed warm shading with broad light pools, so disabling mobile shadow maps does
not expose the room to the outdoor sun. The updated probe captures both the
original lobby viewpoint and the furnished salon at noon and midnight.

Models use texture artwork by default. Casino palette meshes combine a shared
128px detail atlas with per-vertex tints and model-space UVs. Older solid-colour
StandardMaterial3D surfaces keep their plain colour with matte vertex shading: a
shared grain albedo used to be multiplied in, but it darkened guns, gnomes and other
dark props to near black. Authored texture/UV setups and custom shaders are preserved.
This includes streamed props because it uses the existing bounded material styling queue.
