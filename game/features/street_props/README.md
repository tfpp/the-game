# Exterior street kit

50 independent static prefabs: lamps, signs, street furniture, barriers, utilities,
fencing, drains and clutter. Each has its own 32–128 px image-generated diffuse
texture and explicit UV map. Twelve 128 px repeating surface textures supplement
these atlases. Runtime assets are in `assets/street_props`; OBJ and UV authoring
sources are outside `game/`. Native GDScript import does not repaint textures.

Generic prefab collision uses a fitted box; the district keeps props away from
routes. Street lamp lighting belongs to the district scene, not these prefabs.
