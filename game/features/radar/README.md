# Desktop radar

A north-up, 76-metre local floor plan below the top-right player/connection panel.
Mint marks the local player and facing; gold dots mark other players on the same
storey. Phones, tablets, touch controls and dedicated servers do not show it.
Desktop browsers and native desktop clients, including gamepad play, do.

The HUD builds a horizontal slice from nearby collidable CSG meshes. Upward floor
triangles and wall intersections are drawn in 2D, excluding roofs and distant
storeys. It reads existing player replication and adds no camera or network state.
Geometry work is spread over frames and cached until the player moves, changes
height, or nearby scene membership changes (including streamed rooms).

This is a distinct presentation feature: the existing HUD owns connection text
and input capture, while touch controls own mobile input. Neither owns a map.

Tests cover platform visibility, projection and roof/storey filtering. Run the
full-world probe for rendered screenshots and streamed-room/visibility checks:

```sh
godot --path game res://tests/features/radar/radar_probe.tscn
```
