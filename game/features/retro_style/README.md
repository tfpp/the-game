# PS1 presentation and mobile budget

World surfaces use nearest-neighbour sampling with mipmaps, matte vertex lighting,
and low-polygon silhouettes. The casino's textured finishes add restrained
ordered dithering and a 4% affine texture interpolation blend. This runs in the
surface shader: no full-screen texture copy, depth-of-field or bloom pass.

All fourteen referenced world-image imports are capped at 128 pixels on the longest
side (square artwork is 128×128; the sky panoramas keep their aspect ratio).
Original source artwork remains available for editing. Font atlases, UI atlases
and streamed arcade screens retain their resolution so text and games stay usable.
Cards, chips and prompts stay legible; multiplayer gameplay keeps its existing owners.

`RetroStyle` styles existing and newly streamed meshes in bounded batches, then
stops processing. Materials and primitive meshes are handled once per resource;
weak caches do not retain unloaded rooms. Authored shader materials are preserved.
Remote-player movement and gameplay replication stay with their original owners.

On Android, iOS and touch browsers (including iPad desktop user agents):

- 3D rendering is capped at 432 pixels high, at most 70% of native resolution.
- HUD and touch controls keep native resolution, with orientation-aware UI scaling
  (480×720 portrait, 960×540 landscape virtual layout sizes).
- The 3D budget uses physical window dimensions, not stretched UI coordinates.
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

## Measured comparison

Native Compatibility renderer, same 1280×720 lobby camera and touch HUD; previous
main at `04475dc` versus this mobile profile. Day/night are fixed in the probe.
Counters measure submitted rendering work, not phone frame rate:

| Metric | Previous | Mobile PS1 |
| --- | ---: | ---: |
| Day visible draw calls | 2,285 | 1,027 |
| Day visible primitives | 228,820 | 169,072 |
| Night visible draw calls | 2,324 | 1,043 |
| Night visible primitives | 291,860 | 184,480 |
| Four casino image payloads, including mips | 25,152,216 bytes | 262,140 bytes |

That is about 55% fewer visible draws and 99% less decoded image data for the four
casino textures. At this window size, the mobile 3D buffer is 960×540 (56% of the
original pixel count), while UI remains 1280×720. Scene counters vary with players,
viewpoint and streamed rooms. These figures do not measure texture-driver overhead.

The reference salon adds original table, bar, gallery and patron meshes. Their
palette shader computes warm illumination per vertex; indoor texture shaders use
fixed warm shading with broad light pools, so disabling mobile shadow maps does
not expose the room to the outdoor sun. The updated probe captures both the
original lobby viewpoint and the furnished salon at noon and midnight.

With the new salon furnishings, the eye-level salon probe submitted 291–303 draws
and 66,119–77,675 primitives at 1280×720 with the mobile profile. This is a different
viewpoint from the lobby comparison above; it is not a like-for-like improvement
claim or a physical-phone FPS result.

Models use texture artwork by default. Casino palette meshes combine a shared
128px detail atlas with per-vertex tints and model-space UVs. Older solid-colour
StandardMaterial3D surfaces receive a shared grain albedo with triplanar mapping;
authored texture/UV setups and custom shaders are preserved. This includes streamed
props because it uses the existing bounded material styling queue.
