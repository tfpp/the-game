# Van route map

Screen-only UI artwork: `game/assets/starter_room/travel_map.png`, generated with
ImageGen. This image is not a model/world texture. Normalized clickable pins in
`route_map.gd` connect to the existing authenticated van travel actions. Geography
is an illustrative travel diagram, not a claim about streamed zones' coordinates.

Art prompt: Square top-down illustrated street map for a gritty retro game. Aged
cream paper, charcoal building footprints, dusty ochre main roads, thin gray side
streets, faded teal river at the right, folded paper and ink wear. Flat cartography,
no text or pins. Casino plaza upper left, parking garage upper right, street market
lower left, roadside pawn shop lower right. Naturally connected urban streets.

Captured in Godot 4.7.2 Compatibility renderer using
`res://tests/features/starter_room/capture.tscn`: desktop 960×540, portrait 390×844,
and landscape 844×390. Run with a display and an output directory after `--`.

The pawn shop reuses the existing textured `street_props/models/service_door.res`
mesh as mirrored double doors. Its existing invisible collision/interaction hull
preserves the authenticated garage return and the closed exterior boundary.

During transit a private SubViewport renders the existing operations van model.
Scrolling lane markings, suspension bounce and body roll animate during the
server-controlled trip. It has its own 3D world, no colliders or gameplay input,
and hides on arrival/cancellation. The travel duration is unchanged.
