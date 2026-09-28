# Gnomes and express tunnels

Four server-owned gnome trains run between their existing holes. Their navmesh,
replicated progress and avoidance behavior are unchanged.

Use any of the 16 labeled holes (E, B/Circle, or mobile USE) to enter the shared
Gnome Express passage. Move normally to run at **four times** your normal speed,
then Use a labeled green exit to surface at that hole. All four burrows connect;
North, South, East and West stations each have four numbered exits.

`gnome_tunnels.gd` derives links from the existing train/hole nodes, reusing
`RoomDoor` and its server-side sender/range validation and owner teleport RPC.
Doors and markers exist on every peer. `StreamedRoom` builds only the static
`tunnel_interior.tscn` geometry locally before arrival. The passage lives away
from the casino at z=-1000, avoiding changes to world geometry.

Movement remains owner-authoritative: while inside the tunnel bounds, only the
local player's private MovementConfig has its max_speed multiplied. Leaving,
respawning or unloading the feature restores the prior value; jump settings
and other movement tunables are preserved. No permanent player state is added.
