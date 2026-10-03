# Desktop radar

A north-up, 76-metre local floor plan below the top-right player/connection panel.
Mint marks the local player and facing; gold dots mark other players on the same
storey. Phones, tablets, touch controls and dedicated servers do not show it.
Desktop browsers and native desktop clients, including gamepad play, do.

The HUD builds a horizontal slice from nearby collidable CSG meshes and static
box and concave mesh colliders explicitly marked with the `radar_geometry` group. The salon marks
its existing walls, tables, stairs and gallery this way, without extra render meshes.
The world builder automatically marks its structural collision when baking a
scene. This maps rooms, connecting halls, pillars and door/window openings without
drawing decorative mouldings or generating an extra map mesh. Translated/rotated
instances and streamed load/unload use the same collection and cache. Rebuild older
generated scenes once to include the persistent group. Upward floor triangles and wall intersections are drawn in 2D, excluding roofs and distant
storeys. It reads existing player replication and adds no camera or network state.
Geometry work is spread over frames and cached until the player moves, changes
height, or nearby scene membership changes (including streamed rooms).

Other features draw on the map by joining `radar_overlays` and implementing
`draw_radar_overlay(radar)` (the GPS route does). `walls()` exposes the current wall
slice; the radar node is in the `radar` group.

This is a distinct presentation feature: the existing HUD owns connection text
and input capture, while touch controls own mobile input. Neither owns a map.

Tests cover platform visibility, projection and roof/storey filtering. Run the
full-world probe for rendered screenshots and streamed-room/visibility checks:

```sh
godot --path game res://tests/features/radar/radar_probe.tscn
```

Geometry discovery indexes CSG and collision nodes once, then tracks scene-tree
additions/removals. The once-per-second nearby refresh visits those candidates,
rather than recursively walking every prop, avatar and UI node. Group membership,
disabled state, shape and world transform are still checked on each refresh, so
streamed rooms and moving structural geometry retain their existing behavior.
Nodes removed during a queued map build are skipped. The cache only observes the
current game scene, excluding private inventory-icon viewports and other scenes.
Mobile/touch players and dedicated servers retain the existing hidden radar.

Run the full-world CPU discovery comparison (no GPU/browser FPS claim):
`godot --headless --path game res://tests/features/radar/scan_probe.tscn`.
It compares the former recursive traversal with indexed discovery on the same
loaded scene, asserts identical nearby roots, and reports median/p95 microseconds.

Browser map builds now slice CPU collision faces directly: CSG roots use
`bake_collision_shape()`, concave colliders expose their stored faces, and boxes
use analytic CPU triangles. The production path does not call `get_meshes()` or
read render mesh arrays back from WebGL. Individual large roots are sliced in
128-triangle chunks, with at most 2,048 triangles and 16 completed roots per
frame, checking a 2 ms time budget between chunks. Collision snapshot copying
and final floor-mesh upload are indivisible, so this is a work budget rather than
a hard guarantee on frame duration. Unloading a partially sliced source discards
its unpublished work. Regression tests preserve CSG subtraction openings and
transformed box slices and compare chunked versus uninterrupted slicing.
