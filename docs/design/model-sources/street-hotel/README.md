# Street hotel authoring

The existing vintage hotel props remain the furniture source, with their existing
UV meshes and individually generated 32/64/128px atlases. Hotel architecture is
native mesh geometry built from actual socket boundaries. New exterior quads map
to the already painted hotel-facade atlas: TL windows, TR walls, BL trim, BR roof.
No texture painting is performed before authoring new geometry.

`features/street_hotel/tools/build_assets.gd` bakes ten floor scenes and derives the
street view from the existing assembled socket layout. The view preserves building
positions, rotations, scale and road geometry, simplifies building silhouettes and
resizes existing generated facade artwork to 32px. Bake with the real compatibility
renderer so instance buffers persist. The rebuild does not repaint the original
hotel props or generated street textures.
