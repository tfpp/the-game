# Asset generation guide

Use this guide when creating or changing models and their textures for Casino Royale.
Read [lore](design/lore.md), [gameplay](design/gameplay.md) and the
[art style](design/art-style.md) first, plus the relevant
[zone document](design/zones/) for location-specific work. Follow
[game/AGENTS.md](../game/AGENTS.md) when editing game assets or their integration.
The [model and texture workflow](design/model-workflow.md) supplies the detailed
UV, painting and validation process; this guide explains how to choose and connect
the available tools.

## Inspect before building

Find the feature that owns the asset and inspect its scene, materials, import
settings, collision, attachment markers and callers. Reuse an existing model or
native model builder when it already fits. An art replacement should preserve
gameplay dimensions, collision, interactions and animation interfaces unless the
task asks to change them.

Record the intended dimensions in meters, pivot, viewing distance, number of
simultaneous copies, moving parts, texture size and geometry/material budget.
Use nearby assets as the baseline. A first-person weapon needs different attention
from a prop repeated throughout a room; choose budgets for the actual use rather
than assuming every asset needs thousands of triangles.

## References and existing examples

Open the relevant images before modeling. Filenames alone do not communicate
proportions, color or atmosphere.

| Location | Use |
| --- | --- |
| [Dealer front](design/concept-art/dealer.png) and [side](design/concept-art/dealer-side.png) | Character proportions, angular anatomy, clothing and restrained detail. |
| [Casino](design/concept-art/casino.png) | Faded luxury, warm lighting, furniture and materials. |
| [Elevator entrance](design/concept-art/elevator-parking-garage.png) and [garage loot](design/concept-art/loot-parking-garage.png) | Warm/cold contrast, abandoned concrete spaces and sparse composition. |
| [Saved model and scene previews](design/previews/) | Compare new work with rendered assets already in the project. |
| [Authoring sources](design/model-sources/) | UV guides, painting prompts, manifests and retained source artwork. |
| [Game assets](../game/assets/) and feature scenes | Inspect actual shipped geometry, texture sizes, scale and integration. |

Run `rg --files docs` to find newer references. The
[garage prop kit](../game/features/procedural_rooms/props/README.md) and
[loot models](design/loot-models.md) are useful examples of simple geometry,
shared texture space and reusable scenes.

User-supplied photos and real object references can clarify construction and
proportions. Translate them into the game's style instead of copying photographic
detail. Record the source and license for third-party assets or imagery actually
included in the repository; a reference image is not automatically a reusable texture.

## Shape and art direction

Build the silhouette first and review it before adding detail. Aim for the existing
GoldSrc-inspired, retro low-poly look: broad planes, obvious facets, chunky forms,
coarse painted surfaces and restrained wear. Use geometry for silhouette, visible
depth and moving parts. Paint seams, small bolts and scratches when they do not
need their own shape. Remove hidden faces only when no required pose reveals them.

Keep metal dull and palettes restrained. Casino assets favor aged wood, brass,
cream and deep red; slum assets favor concrete, charcoal, rust and dirty yellow.
Avoid smooth subdivision, photorealistic materials, dense bevels and microdetail.
Low-poly does not mean every object should be a stack of cubes: use sparse meshes
and faceted cylinders where they describe the shape better.

Count exported triangles, material surfaces, textures and scene nodes separately.
A low triangle count does not compensate for dozens of separate draw submissions.
Share meshes/materials across repeated props, and combine static parts where useful
without merging away animation pivots or interaction nodes.

## Prefer Blockbench through MCP

Use the installed Blockbench MCP tools for new authored models when available.
Read the `blockbench-use` skill, then the relevant modeling, texturing, animation
or headless skill. Discover the live tools and their schemas; tool availability
depends on the installed plugin and active format. The names below describe the
workflow, not commands to paste into a shell.

- **Desktop:** use `get_capabilities` to inspect the current project and formats.
  Preserve existing unsaved work. Inspect the outline and textures before edits,
  use native undo-aware tools, and save an editable `.bbmodel` explicitly.
- **Headless:** use `bbmodel_info` for an existing file, or `bbmodel_create` for a
  new one. Use `bbmodel_edit` for geometry and UV operations when exposed, then
  `bbmodel_validate` and rendered review. Pass the returned revision into subsequent
  edits where supported. Do not edit the same file simultaneously in the desktop
  app and headless server; reopen it after external changes.
- For ordinary Godot mesh assets, choose Generic Model (`free`) unless an existing
  pipeline requires another format. A Minecraft format imposes different limits
  and does not itself produce a Godot-ready asset.
- Inspect `list_export_formats` before desktop export. Export through a codec
  that actually supports the required meshes, materials and animation. Retain the
  `.bbmodel` source alongside the documented runtime export process.

If an MCP connection or renderer is unavailable, report the specific limitation.
Use an existing native GDScript builder where appropriate rather than silently
switching to a lossy format or adding a new toolchain. The current
[cabinet workflow](design/model-workflow.md) and prop kit are supported native
alternatives, not general importers for arbitrary Blockbench models.
Do not introduce Python scripts, tooling or dependencies.

## Keep textures small

**Model and world textures must be at most 128×128 pixels on both dimensions.**
Use the smallest size that remains readable in play, including embedded GLB
textures and any additional material maps. The limit is a ceiling, not a target.

| Starting size | Typical use |
| --- | --- |
| 16×16 or 32×32 | Small pickups, simple surfaces and tiny palettes. |
| 32×32 or 64×64 | Modest props with a few readable material regions. |
| Up to 128×128 | Larger models or assets whose visible detail needs the space. |

Prefer a compact shared atlas and as few materials as practical. Use power-of-two
dimensions, mipmaps and nearest mipmap filtering. Avoid unnecessary alpha channels,
duplicate images and extra normal/roughness maps. Inspect both encoded file size
and the imported asset; small PNG dimensions do not measure total mesh or GPU cost.

Author UV1 islands explicitly. Keep surface proportions, reuse repeated or mirrored
artwork deliberately, and give visible features more texture space than hidden
undersides. Pad islands and extrude edge colors to prevent mip bleeding. For a solid
palette, sampling one swatch is intentional; patterned surfaces need proportionate
UVs. Check with a UV checker before painting.

When generating artwork, use the actual UV template as an edit reference and ask
for flat diffuse artwork with named regions, not a perspective picture of the model.
Save the prompt. Reduce the painting to the chosen runtime size, which may be well
below 128×128, and inspect the applied result. Preserve existing painted atlases on
geometry rebuilds. Keep large painting drafts and enlarged UV guides outside `game/`.

Emission can provide small readable accents. Verify it in the game renderer:
bright/unshaded surfaces, bloom and illumination of nearby objects are different
effects. Do not assume an export preserves every material setting or add dynamic
lights to every repeated prop without checking their cost.

## Files, export and game integration

| Artifact | Location |
| --- | --- |
| Model exports, small runtime textures and feature media | `game/assets/<feature>/` |
| Reusable scenes, materials and behavior | `game/features/<feature>/` |
| Large painting sources, prompts, UV guides and manifests | `docs/design/model-sources/<asset>/` |
| Useful review renders | `docs/design/previews/<asset-or-feature>/` |
| Temporary captures and experiments | A temporary directory, outside runtime assets. |

Keep editable `.bbmodel` sources with the asset or its documented authoring sources.
Record which file is authoritative and how to rebuild exports. Keep paths portable;
do not document a developer's machine-specific application or cache paths.

Godot uses meters; document and verify any conversion from Blockbench units. Check
axes, normals, face winding, UVs, root transforms and pivots after import. Use a
floor-centered pivot for ordinary placed props, while held items and animated
parts need their own attachment or hinge origins. Collision should describe gameplay
space, not every decorative surface.

Reference runtime assets through full literal `res://` paths so export discovery
can find them. Keep Godot import settings needed to reproduce the result. Follow
the owning feature's existing GLB or native mesh/scene pipeline instead of rebuilding
its loader. For held items, preserve the `Grip`, optional `SupportGrip` and weapon
`Muzzle` conventions in [Holdables](../game/features/holdables/README.md), including
marker orientation and -Z forward. Verify camera clearance, hand contact, dropped
placement and remote-player presentation when affected.

## Render and inspect existing models

For a `.bbmodel`, the headless MCP `bbmodel_render` tool can produce a PNG and
`bbmodel_contact_sheet` can render several views without opening the desktop app.
For example, use these arguments with `bbmodel_render`:

```json
{
  "file": "game/assets/roulette/models/roulette_table.bbmodel",
  "view": "three-quarter",
  "lighting": "studio",
  "orthographic": true,
  "width": 800,
  "height": 600
}
```

Inspect the returned image, not just the successful tool result. Headless model
editing does not require a GPU, but the built-in renderer requires its runtime
dependencies and a working WebGPU device. If rendering is unavailable, use the
desktop viewport or a Godot preview on a machine with rendering support.

For Godot scenes, prefer an existing feature preview. This working cabinet example
captures textured, checker and rear views (commands run from the repository root):

```sh
godot --headless --path game --editor --import
godot --path game res://features/procedural_rooms/model_tools/preview_model.tscn -- \
  /tmp/casino-asset-preview
```

The import can run headlessly; this capture scene requires a graphical renderer.
The [prop kit](../game/features/procedural_rooms/props/README.md) has another preview
scene. Inspect a preview script's arguments before using it: there is no universal
screenshot flag across the repository. For a new fixture, reuse the existing pattern
of a camera, simple lighting and `RenderingServer.frame_post_draw` before saving
the viewport image. An AI-generated concept image is not evidence of the imported
model's appearance.

Review front, back, sides and gameplay distance. Check seams, pixel scale, mip
bleeding, silhouette, collision clearance and the actual runtime materials. For
animations, inspect multiple poses and the loop boundary; a rest-pose screenshot
cannot verify motion. Include the relevant first-person or in-world view rather
than relying only on an isolated studio render.

## Handoff

Deliver the editable source, runtime asset, owning scene and reproducible export
instructions. Record dimensions, triangle count, material count, texture sizes,
references/licenses and any limitations. Include a useful render and identify what
was checked in Blockbench versus Godot; do not claim runtime performance from a still.

Add a new feature-owned release note for notable work, following
[release notes](release-notes.md). Run checks appropriate to the changed integration
and `harness/verify.sh` before any commit or PR. Do not change protected engine or
build paths merely to add an asset.
