# Armoured operations van

Civilian cash-in-transit reference proportions: angular bonnet/cab, tall secure
cargo shell, small protected cab glazing, reinforcing plates, heavy bumpers and
rear locking bars. Original work; no third-party model or texture is included.
Blockbench MCP is unavailable; this extends the existing native Prop builder.

`build.gd` is the authoritative enhancement recipe. It derives the rear moving
leaves and remaining shell from the original `operations-van/build.gd` export.
Triangle clipping preserves interpolated UVs and the approved 128×128 atlas.
Body hardware intentionally samples half-texel-centered paint, steel and rubber
swatches in that atlas. Both cab leaves are separately authored continuous profiles
with a sloped inset window, rubber gasket, 60mm skin returns, inner vinyl panel,
recessed latch, compact hinges and attached mirrors. The profile follows the actual
windshield rake; no rectangular bars or old painted door skins remain layered over it.
The cab uses a dedicated 128px ImageGen-painted atlas from `cab-uv-template.png`.
`cab-paint-prompt.txt` retains the exact prompt and `cab-paint-source.png` the original
response. Body-space UVs stay continuous across the four frame sections; the two
cab doors mirror the same six padded charts. Native processing downsamples and
extrudes each chart edge into 2px gutters; nearest mipmap sampling is enabled.
Normal rebuilding does not touch approved artwork or the original `van.res`.
The original exact UV chart, paint source and prompt stay in `operations-van/`.

The chassis has ladder rails, crossmembers, two hub-connected axles, a rear differential,
leaf springs, a continuous engine/gearbox/driveshaft chain, sump, fuel tank, muffler
and exhaust. The cab has two seats and a
dashboard; a bulkhead separates it from the empty cargo compartment. The shell
and door backs form closed surfaces in the open poses, including a roof liner.

Metres, Y up, +Z bonnet, floor-centred model pivot. Original shell: 5 × 2 × 2.25m;
bumper/guard envelope about 5.36 × 2.6 × 2.3m including mirrors. Four leaf pivots
are at the front edges of the cab and outer edges of the rear cargo opening.
100-degree outward swings. Two materials/textures (body and cab), five indexed
mesh surfaces, 1,416 triangles. One garage copy plus a private driving
preview. Gameplay collision stays separate from visual hardware. The cab leaves use convex
collision cages exported from the same authoritative sloped outline; their upper
front corners no longer have invisible rectangular collision above the skin.

From repository root, after a Godot import:

```sh
godot --headless --path game -s ../docs/design/model-sources/armoured-operations-van/build.gd
# Only to rebuild the cab texture from retained painted artwork:
godot --headless --path game -s ../docs/design/model-sources/armoured-operations-van/build.gd -- \
  "$PWD/docs/design/model-sources/armoured-operations-van/cab-paint-source.png"
godot --path game --audio-driver Dummy res://tests/features/starter_room/capture_van.tscn
```

The capture scene renders the actual native exported meshes and material in
Godot's Compatibility renderer: front, rear, underside, all doors open, cab and
cargo interior, plus both cab doors closed in close-up and the driver door open.
Review images are written under
`docs/design/previews/armoured-operations-van/`. A real X display (or Xorg dummy)
is required; `--headless` does not provide rendered review.

Gameplay behavior belongs to `starter_room/feature.tscn`, not the visual prefab.
Each leaf has its own `NetworkedInteraction`, authenticated range/cooldown checks,
replicated `net_open`, session reset and existing door sound cues. Matching
endpoints remain outside streamed room content. The private driving vignette uses
closed visual leaves, removes all collision and has no interaction endpoints.

The side-mounted RouteMap forwards to the existing OperationsVan travel system.
This separates its interaction target from the cab handles without changing trip
validation, destinations or owner-only transition behavior.

`test_van_doors.gd` covers real ENet opening/closing, late-join poses, authority,
spoofed payloads, distance, cooldown, collision clearance, geometry winding,
normal/UV validity, floor contact and the texture cap. Existing layout/travel
coverage checks the garage routes and preserved trip behavior.
