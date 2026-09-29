# Gnomes and express tunnels

Four burrows of three gnomes each live in the outer walls. Every hole is a little
doggy door with a flap that swings open as a gnome passes. North, South, East and West
burrows each have four doors on their wall.

## Behavior

`gnome_train.gd` is server-authoritative. After resting inside a hole, the burrow picks
another of its holes (favoring far ones). Gnomes come out one after another. Each one
wanders its own random route through two to four stops in front of the wall, planned
on the prebaked navmesh (`gnome_navmesh.tres`), then slips into the chosen door. While
out, gnomes sidestep players and anything in the `killable` group (casino patrons, the
penguin, frogs, dummies), fading the sidestep out near the doors so they still line up.

The server snaps every route point onto the floor collision below it (layer 1,
skipping players and other moving bodies), so gnomes walk on the floor rather than
at the navmesh's rounded height. Every door sits at y=0, the floor at the wall base.

Each gnome stands on flat boots over an unshaded contact-shadow disc, and door frames
reach 2 cm into the floor, keeping them grounded even without shadow maps. Doors
and their "Gnome tunnels - USE" labels have no mobile-only distance cutoff.

Sync replicates each gnome's position, facing and a bitmask of which gnomes are out.
Clients never query the navmesh; they only smooth and show that state. Features load
before networking starts, when every peer still counts as the server, so the train
checks authority every physics frame and resets its burrow on `Network.mode_changed`:
a joining client drops anything it simulated before connecting.

## Killing

Each gnome (`gnome.gd`) is a layer-2 `StaticBody3D` in the `killable` group, like the
frogs, so any weapon or power punch hits it without blocking player movement. The
server marks it dead and broadcasts the shared `MeshExplosion`. A dead gnome is only
hidden with its hitbox disabled, never freed; it comes back the next time its burrow
comes out of a hole. Burrowed gnomes are hidden the same way.

## Express tunnels

Use any of the 16 labeled doors (E, B/Circle, or mobile USE) to enter the shared
Gnome Express passage. Move normally to run at **four times** your normal speed,
then Use a labeled green exit to surface in front of that door. All four burrows
connect; North, South, East and West stations each have four numbered exits.

`gnome_tunnels.gd` derives links from the existing train/hole nodes, reusing
`RoomDoor` and its server-side sender/range validation and owner teleport RPC.
Doors and markers exist on every peer. `StreamedRoom` builds only the static
`tunnel_interior.tscn` geometry locally before arrival. The passage lives away
from the casino at z=-1000, avoiding changes to world geometry.

Movement remains owner-authoritative: while inside the tunnel bounds, only the
local player's private MovementConfig has its max_speed multiplied. Leaving,
respawning or unloading the feature restores the prior value; jump settings
and other movement tunables are preserved. No permanent player state is added.
