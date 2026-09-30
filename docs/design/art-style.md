# Casino Royale — Art Style Guide

## Concept Art

To view concept art with this art style view the images in `docs/design/concept-art`

## Purpose

This document defines the visual language for **Casino Royale** so characters, props, environments, lighting, and future concept art all feel like they belong to the same game.

The target is a **simple retro low-poly 3D style** with **low-resolution textures**, strong silhouettes, restrained detail, and an atmosphere that can shift from faded casino warmth to oppressive urban dread.

The style should feel like an older 3D game remembered more vividly than it actually looked: chunky geometry, simple materials, slightly imperfect textures, dramatic lighting, and environments that rely on mood rather than realism.

---

## 1. Core Visual Identity

### The shorthand

**Low-poly retro 3D + simple pixel-like textures + 1960s casino decay + dark urban dread.**

The game should not look modern, glossy, physically accurate, or overly polished.

The visual appeal comes from:

- Large, readable polygon shapes.
- Simple geometry with visible angular construction.
- Low-resolution textures with broad blocks of color.
- Minimal surface detail.
- Strong light-versus-dark contrast.
- Warm, inviting casino lighting against cold, hostile slum environments.
- Slightly exaggerated proportions and silhouettes.
- A feeling of faded luxury surrounded by neglect.

The final image should read clearly at a distance before the viewer notices any small details.

---

## 2. Geometry

### General rule

**Use fewer polygons than feels necessary.**

Models should be visibly low-poly without becoming voxel art.

Surfaces should be built from broad planes instead of many small curves. Rounded objects should still reveal their faceted construction.

### Preferred

- Angular heads and faces.
- Blocky hands and fingers.
- Simplified shoes.
- Straight or lightly segmented limbs.
- Large planar folds instead of simulated cloth.
- Furniture built from clean primitive forms.
- Cars with broad, angular body panels.
- Columns, walls, doors, pipes, and railings with simple silhouettes.
- Obvious faceting on curved architecture and props.

### Avoid

- Smooth sculpted anatomy.
- Dense subdivision.
- Tiny bevels everywhere.
- High-poly fingers, ears, noses, or facial anatomy.
- Realistic cloth simulation.
- Decorative geometry that could be represented by a texture.
- Perfectly rounded modern-looking assets.

A model should still look intentional when shown with flat lighting and no texture.

---

## 3. Texture Style

Textures should be **simple, low-resolution, and slightly coarse**.

They should support the form rather than hide it.

### Hard texture limit and GoldSrc direction

Runtime textures for models and world surfaces must be **128×128 pixels or smaller
on both dimensions**. Scale power-of-two texture size to the model's physical size
and visible detail: small pickups can use 16×16 or 32×32, modest props 32×32 or
64×64, and larger/detail-heavy models up to 128×128. Do not use 128×128 as a default.
Use nearest
filtering with mipmaps, broad painted colour, simple seams and vents, restrained
grime, and readable silhouettes: a GoldSrc-inspired appearance. Avoid photographic
surface detail and high-resolution normal/roughness texture stacks.

Props need deliberate UV1 maps with named, padded islands. Stack or mirror repeated
surfaces such as tyres, hubs, crate panels and barrel facets; keep distinct islands
separate. Pack with rotation and allocate pixels by visibility and detail importance,
with smaller budgets for undersides and hidden faces. Generate artwork against the exported UV template,
process the final atlas down to the runtime limit, and review checker and painted
renders before accepting it. Large source artwork and enlarged guides belong
outside `game/`. See [the model workflow](model-workflow.md).

### Preferred

- Broad patches of color.
- Low-frequency shading.
- Visible pixel structure when viewed closely.
- Simple painted highlights and shadows.
- Small amounts of grime or wear.
- Slight color variation between texture blocks.
- Simple repeating materials for walls, carpets, concrete, clothing, and wood.

### Character textures

Faces should use very few marks:

- Simple eyebrows.
- Minimal eyes.
- A basic mouth.
- A few large shadow shapes.
- Hair represented as broad dark masses.
- No pores, stubble maps, skin microdetail, or realistic subsurface shading.

Clothing should use large color regions and only a few defining details.

For example, the casino dealer is recognizable through:

- White shirt.
- Black vest.
- Red bow tie.
- Dark trousers.
- Small gold name badge.
- Dark hair.

Those elements matter more than seams, stitching, fabric weave, or realistic wrinkles.

### Avoid

- 4K-style detail.
- Photorealistic materials.
- Fine fabric patterns.
- Skin pores.
- Normal-map-heavy surfaces.
- Procedural micro-noise.
- High-frequency scratches everywhere.
- Perfectly clean vector-like textures.

---

## 4. Character Design

Characters should be simple enough that their job or role is readable immediately from silhouette and color.

### Shape language

- Heads are angular and slightly oversized.
- Facial features are broad and economical.
- Hands are chunky.
- Arms and legs use simple tapered forms.
- Clothing is modeled as large masses rather than layered fashion simulation.
- Hair is a solid sculpted shape with only a few planes.
- Posture should be natural but uncomplicated.

### Casino staff

Casino employees should feel like they belong to an aging institution that still insists on formality.

Visual cues include:

- Vests.
- Bow ties.
- White shirts.
- Dark trousers.
- Small badges.
- Restrained red, black, cream, brass, and dark wood tones.

They should not look glamorous or luxurious. Their uniforms should feel slightly dated and institutional.

### NPC presentation

Character concept sheets should normally use:

- Neutral pose.
- Full body visible.
- Front view.
- Back view.
- Side view when needed for modeling.
- Plain dark or neutral background.
- Even lighting.
- No dramatic action pose unless specifically requested.

Concept art should function as a modeling reference first and an illustration second.

---

## 5. Environment Design

The environments should use the same low-poly simplicity as the characters.

Detail should come from **composition, lighting, repetition, and atmosphere**, not mesh density.

### Casino

The casino should feel warm, old, safe, and slightly depressing.

Key qualities:

- Dated 1960s-inspired interiors.
- Dark wood.
- Brass or dull gold accents.
- Deep red.
- Muted green gaming felt.
- Cream-colored lighting.
- Patterned carpet used sparingly.
- Heavy trim.
- Old-fashioned fixtures.
- Warm pools of light surrounded by darker corners.

The casino is not a modern luxury resort.

It should feel like a place that has been maintained for decades without truly being renewed.

### Slums and exterior spaces

The world outside the casino should feel colder, emptier, and more threatening.

Key qualities:

- Concrete.
- Rain.
- Standing water.
- Puddles.
- Dim fluorescent fixtures.
- Failing lights.
- Dark open space.
- Long sight lines that disappear into blackness.
- Narrow alleys and compressed spaces.
- Abandoned vehicles.
- Industrial pipes.
- Utility structures.
- Dirty gray, faded yellow, black, and cold blue-gray tones.

The environment should suggest danger before anything dangerous actually appears.

---

## 6. Lighting

Lighting is one of the most important parts of the art direction.

### Casino lighting

Use:

- Warm amber.
- Soft cream.
- Dull gold.
- Localized pools of light.
- Darker spaces between fixtures.

The casino should feel visually warm even when the decor is dreary.

### Slum lighting

Use:

- Cold white fluorescent light.
- Weak blue-gray ambient light.
- Deep shadow.
- Occasional sickly yellow industrial light.
- Flickering or partially failed fixtures.
- Large areas with little or no illumination.

### The contrast rule

**Warmth belongs to the casino. Cold darkness belongs outside it.**

A transition between the two should be immediately visible.

The elevator concept is a strong example:

A warmly lit, old-fashioned elevator opens directly into a dark abandoned parking garage. The elevator feels safe. The garage does not.

That contrast should be used repeatedly throughout the game.

---

## 7. Atmosphere and Dread

The game should create dread through restraint.

Do not fill every dark area with monsters, gore, signs, props, or visual noise.

Instead use:

- Empty space.
- Distant darkness.
- Repetition.
- Long corridors.
- Unoccupied parking bays.
- Water reflections.
- Flickering lights.
- Obscured corners.
- Isolated abandoned objects.
- Large structures disappearing into shadow.
- Warm safe areas visible behind the player.

The player should often feel that they are looking into a space that continues farther than they can comfortably see.

### Important

The horror atmosphere should come from **uncertainty and environment**, not from turning the game into a conventional horror aesthetic.

Avoid excessive blood, grotesque imagery, supernatural decoration, or constant visual scares unless a specific area calls for them.

---

## 8. Color Language

The palette should remain restrained.

### Casino palette

Primary colors:

- Dark brown.
- Mahogany.
- Deep red.
- Black.
- Cream.
- Muted green.
- Dull brass/gold.

Accent colors should feel aged rather than saturated.

### Slum palette

Primary colors:

- Charcoal.
- Concrete gray.
- Dirty white.
- Faded yellow.
- Near-black.
- Muted blue-gray.
- Rust brown.

Bright color should be rare outside the casino.

### General rule

Avoid large areas of highly saturated modern color.

Color should feel faded, dirty, warm, cold, or institutional depending on the location.

---

## 9. Materials

Materials should remain visually simple.

### Good material treatment

Wood:
- Large dark grain blocks.
- Slight warm variation.
- Minimal gloss.

Metal:
- Dark or dull.
- Simple highlight.
- Brass should look aged rather than mirror-polished.

Concrete:
- Broad gray variation.
- Occasional stains.
- No excessive surface noise.

Wet ground:
- Simple reflective response.
- Puddles can carry strong lighting reflections.
- Avoid physically perfect water.

Fabric:
- Mostly flat color.
- Minimal shading.
- No visible weave.

Skin:
- Simple warm tones.
- Broad shadow regions.
- No realistic skin shaders.

---

## 10. Props

Props should be recognizable through silhouette.

Good examples:

- Slot machines with simple rectangular cabinets.
- Old fluorescent fixtures.
- Boxy sedans.
- Dumpsters.
- Folding gates.
- Elevator indicators.
- Wooden casino furniture.
- Chips represented with simple cylinders and bold colors.
- Pipes and utility boxes built from primitives.

A prop does not need every real-world component.

Model the pieces required for recognition and interaction.

---

## 11. Elevators and Transitions

The casino elevator is a major visual motif.

It should feel older than the surrounding world.

Preferred characteristics:

- Dark wood interior.
- Brass trim.
- Warm ceiling lamp.
- Old floor indicator.
- Folding or scissor-style gate.
- Slightly excessive decorative trim compared with the slums.

The elevator should feel almost comforting.

When the doors open, the destination should often create an immediate visual contradiction:

- Warm elevator → cold parking garage.
- Warm elevator → rain-soaked alley.
- Warm elevator → empty industrial space.
- Warm elevator → strange or absurd late-game destination.

The doorway itself acts as a frame between two worlds.

---

## 12. Composition for Concept Art

Concept art should resemble an in-game screenshot or model reference rather than polished cinematic key art.

### Character sheets

Use:

- Plain background.
- Full-body view.
- Orthographic or near-orthographic perspective.
- Even lighting.
- Minimal shadows.
- No environment.

### Environment concepts

Use:

- Eye-level camera.
- Strong readable foreground, middle ground, and darkness beyond.
- Large simple shapes.
- One dominant light source or lighting contrast.
- Sparse props.
- Deep negative space.

Do not clutter the image merely to make it appear detailed.

---

## 13. What This Style Is Not

This art direction is **not**:

- Photorealism.
- Modern PBR realism.
- Voxel art.
- Minecraft-like construction.
- PS1 texture warping as a gimmick.
- Highly detailed pixel art painted onto 3D models.
- Clean modern low-poly illustration.
- Fortnite-style stylization.
- Pixar-like character design.
- Modern luxury casino imagery.
- Cyberpunk neon overload.
- Constant horror imagery.
- Highly polished cinematic concept art.

The visuals should feel crude in a deliberate, controlled way.

---

## 14. Practical Asset Rule

When creating an asset, ask:

**What is the minimum amount of geometry and texture detail required for the player to immediately understand what this is?**

Start there.

Only add detail when it improves:

1. Silhouette.
2. Gameplay readability.
3. Atmosphere.
4. Location identity.

If it does none of those things, it probably does not need to be added.

---

## 15. Prompt Language for Future Concept Art

The following wording should be reused when generating visual references:

> Retro low-poly 3D game art, deliberately simple geometry, chunky angular forms, very low-resolution painted textures, broad blocks of color, restrained detail, late-1990s/early-2000s PC game feel, no photorealism, no high-poly sculpting, no detailed PBR materials.

For environments, add:

> Dreary atmospheric environment, sparse props, strong negative space, simple low-poly architecture, coarse textures, dramatic pools of light and deep shadow.

For slum environments, add:

> Cold abandoned urban atmosphere, wet concrete, puddles, failing fluorescent lights, darkness beyond the visible space, muted gray and dirty yellow palette, subtle sense of dread.

For casino interiors, add:

> Warm aged casino lighting, dark wood, brass trim, deep red accents, muted green felt, dated mid-century decor, faded luxury rather than modern glamour.

---

## 16. Review Checklist

Before approving a new visual asset, check:

- Does the silhouette read immediately?
- Is the mesh simpler than a modern game asset would normally be?
- Are the textures visibly low-resolution and restrained?
- Is unnecessary surface detail absent?
- Does it avoid modern PBR realism?
- Does it match the warm casino / cold slum lighting language?
- Is the palette muted?
- Does the environment use darkness and empty space effectively?
- Does the asset look like it belongs beside the existing dealer character?
- Would simplifying it further improve the style?

If an asset looks impressive because of its technical detail rather than its shape, lighting, or atmosphere, it has probably drifted away from the target style.

---

## 17. Current Visual Reference Standard

The current reference standard established during concept development is:

- **Dealer character:** very simple low-poly humanoid, angular face, chunky hands, flat dark vest and trousers, white shirt, red bow tie, minimal gold badge, extremely restrained facial and clothing detail.
- **Dealer side profile:** maintains the same simple polygon density and broad planar construction from every angle.
- **Elevator / parking garage:** warm old-fashioned wood-and-brass elevator contrasted against a dark, wet, abandoned concrete garage with sparse fluorescent lighting and deep visibility falloff.

Future assets should feel visually compatible with these references before additional complexity is introduced.

---

## Guiding Principle

**Simple models. Simple textures. Strong lighting. Strong atmosphere.**

Casino Royale should achieve its identity through composition and mood, not asset complexity.
