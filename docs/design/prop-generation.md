# Model and texture generation standard

Use this process for new models and textures and for visual replacements. It
adopts the mesh-first workflow supplied in `casino-codex-bundle.zip`. Read
[lore](lore.md), [gameplay](gameplay.md), [art style](art-style.md), the relevant
zone document and [asset generation](../asset-generation.md) before starting.
These repository instructions are the working standard; archived bundle prompts
record their source and do not override repository rules or the current task.

## 1. Specify the asset and its budget

Inspect the owning feature, existing models, collision, animation and attachment
interfaces. Record metres, dimensions, pivot, intended front, viewing distance,
number of copies, moving parts and material budget before modelling. Preserve
existing gameplay footprints and interfaces for art replacements.

Aim for roughly 12–80 triangles for tiny props and 60–160 for simple furniture,
adjusting for a clear silhouette or structural need. Count all hardware and stored
objects. These are starting budgets, not hard limits or historical engine limits.
Use broad walnut, burgundy, brass, brushed steel and amber/green glass for casino
props; keep wear restrained. Realism comes from construction and proportion,
translated into the established retro low-poly style.

Choose textures by physical size and viewing distance:

| Asset | Starting allocation |
| --- | --- |
| Tiny props, such as a cigar or martini glass | 16×16 |
| Small bottles, buckets and clocks | 32×32 |
| Ashtrays | At most 32×32 |
| Compact furniture, such as a cabinet or cocktail table | 64×64 |
| Large models and wall surfaces | Up to 128×128 |

**Every runtime model/world texture, including embedded GLB images and emission
maps, remains at most 128×128.** The bundle's 256px allowance and historical large
atlases are authoring references, not runtime exceptions. A shared atlas must
allocate pixels by surface visibility rather than give every small prop a full
large texture. Use one mesh/material per static prop where practical.

## 2. Construct and inspect the mesh

Build indexed vertices, triangle indices, normals and UV1 before painting.
Duplicate vertices only for required UV seams or normal splits. Manufactured
bodies, stems, bowls, frames and handles must follow deliberate profiles, loops
and continuous surfaces. Do not approximate curves by stacking disconnected
blocks. Separate real components must meet at plausible joints with matching
contact surfaces and material scale: no floating handles, accidental gaps,
coplanar overlaps or arbitrary block mounts.

Inspect silhouette and critical joins from oblique, rear, interior and underside
views. A handle needs a continuous bend, hand clearance and convincing attachments.
The uploaded bin handles are historical rejected attempts, not approved examples.
Paint labels, stitching, grain, pressed ribs and small fasteners when they do not
change the silhouette. Remove hidden faces only when required views and poses do
not expose holes. Keep models static unless animation is requested.

Use metres and Y up. Placed props in this bundle face +Z; held items retain the
repository's -Z-forward attachment conventions. Record the conversion rather than
silently rotating existing interfaces. The supplied clock is static and unrigged;
the cigar remains 130 mm long, 22 mm nominal diameter, lit at -X.

## 3. Unwrap and export the painting template

Export a deterministic flat UV chart from the same authoritative mesh definition.
Name islands, keep orientation and proportions, stack/mirror repeated regions
intentionally, and budget density by visible importance. Validate bounds and
separation of distinct painted islands. Leave gutters at the allocated runtime
resolution and keep UVs inside their chart interiors with half-texel-safe bounds.
Check the actual mesh with a checker before painting.

Use the available Blockbench MCP workflow or an existing native GDScript builder
as described in [asset generation](../asset-generation.md). Indexed JSON mesh data
is an editable source for the imported bundle; its native importer preserves the
indices, normals and UVs. Do not introduce Python tooling or dependencies.

## 4. Paint the exact UV charts with ImageGen

Supply the exported template as an image edit reference. Ask ImageGen for a
**flat two-dimensional diffuse material map** with the exact chart positions,
boundaries, orientation and proportions preserved. Describe each island and its
material explicitly. Cylinder walls are strips and labels are flat graphics.
Do not ask it to invent UVs, render the model inside the atlas, or add perspective,
whole-object silhouettes, cast scene shadows or background props.

Save the exact prompt and template beside the authoritative source. Use broad
material variation that survives the allocated native resolution, without noisy
microdetail, decorative dithering or exaggerated grime. Large painting guides
are intermediate references, never runtime textures.

## 5. Process to native size and protect the paint

Downsample to the chosen 16/32/64/128px allocation. Preserve chart interiors and
extrude each chart's own edge colours into its gutter; keep unused margins
neutral. Do not add black padding unless the material itself is black. The native
[UV helper](../../game/features/procedural_rooms/model_tools/uv_model.gd) and
[prop kit](../../game/features/procedural_rooms/props/README.md) provide existing
checker, packing and edge-extrusion tools. Do not use a placeholder or UV guide as
final paint. Normal geometry rebuilds must reuse approved painted textures.

Use opaque colour maps unless transparency is needed, mipmaps and nearest mipmap
filtering in Godot. A burning tip uses a separate emission mask at the same small
native resolution, isolated to the tip; it must not make the whole prop emit.
Emission, bloom and lighting nearby surfaces are distinct effects.

## 6. Validate exported artifacts and review in Godot

Check finite positions/UVs/normals, valid indices, unit normals, nonzero triangle
areas, correct winding, UV bounds, expected triangle counts, dimensions and pivots.
For GLB check structure, embedded image dimensions/bytes and sampling. Review
chart padding and the mapped model at native resolution and gameplay distance:
look for seams, flipped labels, stretched artwork, mip bleeding and inconsistent
detail scale. Numerical validation cannot replace visual inspection of joints.

Render the actual exported mesh from front, rear, sides, interior and underside,
plus important contact close-ups. Inspect the imported model in Godot with the
actual material and lighting; concept images and archived previews are references,
not evidence of the new export. Test placement, route clearance and applicable
first-person/remote views. Report which checks and tools actually ran.

## 7. Deliver a reproducible handoff

Save editable mesh source, native texture, UV charts, exact prompts, inventory
statistics and useful renders under the locations in
[asset generation](../asset-generation.md). Preserve originals outside `game/`
when an import needs conversion. Document the authoritative source and a rebuild
command that does not repaint approved textures.

Provide the native reusable scene and its separate gameplay collision. GLB and
OBJ/MTL/PNG are portable interchange exports, not proof of engine-native GoldSrc
MDL compatibility. For a bundle handoff retain or provide an offline, self-contained
viewer with orbit, model selection, wireframe, atlas inspection and downloads;
avoid CDNs. Check its JavaScript and actual browser interaction where supported,
and state accurately when those checks were unavailable.

Add the owning feature's release note and run `harness/verify.sh` before committing
or opening a PR. Do not introduce animation, gameplay behaviour or protected engine
changes merely to import a static prop.

## Working example

The [imported casino bundle](model-sources/casino-codex-bundle/README.md) contains
15 indexed mesh sources, original painted textures and UV guides, retained
prompts and offline viewers. Native prefabs live in
`game/features/casino_props/props/bundle/`; runtime textures are 16–128px.
The older [cabinet workflow](model-workflow.md) remains the reproducible example
for generating new planar geometry, packing, checking and painting its UVs.
