# Hotel prop room

Use **HOTEL PROPS** on the dev room's south wall, beside **HOTEL WING**. Use is E,
controller B/Circle, or the mobile Use button. The **DEV ROOM** door inside returns
in front of the same teleport. Both places appear in GPS.

The 20×16 m room contains all fifty props from the reviewed vintage hotel pack at
real-world scale: reception, lounge, guest-suite and room-service displays. Small
items sit on their furniture rather than floating on inspection pedestals. The
central aisle and arrival are clear. The static interior streams only for visitors;
portal endpoints remain on every peer, and dedicated servers never build the room.

`hotel_portal.gd` extends the existing RoomDoor for GPS and preloading. Its child
NetworkedInteraction authenticates the sender, validates distance, rejects payloads
and rate-limits successful travel. Owner-only `server_teleport` retains player
movement authority. No shared prop state, extra player or world environment is added.

## Assets

Each prop has one native ArrayMesh, one material, a separate box collision and a
reusable scene in `props/`. The fifty PNGs live in `assets/hotel_props/textures/`;
ten are 32×32 (including the letter), seventeen 64×64, and twenty-three 128×128.
Materials use nearest filtering with mipmaps. Repeated faces intentionally reuse
UV zones; rounded parts unwrap continuously. Glass and mirrors are opaque retro
representations. Props are static display furniture, not inventory pickups.

The reviewed OBJ sources, manifests, UV guides and generation prompts are outside
`game/`, under `docs/design/model-sources/hotel-props/`. No Blender/Python dependency
is introduced. To rebuild native assets without repainting textures:

```sh
godot --headless --path game --editor --import
godot --headless --path game -s res://features/hotel_props/tools/import_props.gd
```

Edit `interior.tscn` to furnish the room; feature loading needs no central scene edits.
Tests cover mesh UVs, texture allocations, individual atlases, clear supported
arrival, room loading/unloading, GPS links, authenticated travel and late joins.
