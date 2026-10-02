# Street building sources

Ten floor-centered building models, in meters and Z-up, with independently painted
128px atlases. Meshes and padded UV maps preceded generation. Native GDScript
import converts to Y-up and preserves winding and UVs. The corner shop and workshop
are hollow shells with 3 m entrance openings; the native importer creates fitted
wall/header/roof collision rather than a solid bounding box for these two buildings.

See `texture_prompt.md`, the PNG/SVG guides and `manifest.json`. Runtime texture PNGs
are in `game/assets/street_district/textures/`. The remaining authored buildings are
closed scenery. Interior layout and containment are owned by the native district.
