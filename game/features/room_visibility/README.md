# Room visibility

The server checks each player's replicated position against existing
`StreamedRoom.bounds` and `GpsDestination.area` volumes. It sends the selected
room to that player when the assignment changes. The client loads only the
selected streamed interior and frees the previous one. Door interactions may
preload the destination briefly so the arrival floor is ready.

For rendering, the client sets Godot's camera far plane to the farthest corner
of the assigned room. The casino's bounds come from its world geometry; other
rooms use their authored extents. This keeps always-loaded geometry in distant
districts out of the draw list without fixed distance cutoffs. Shared gameplay
nodes remain present on every peer, and the server never loads client-only
room interiors.

New door-only districts should have either a `StreamedRoom` anchor or a GPS
destination with an `area` covering their visible district. The server uses
those same bounds for room assignment and camera clipping.
