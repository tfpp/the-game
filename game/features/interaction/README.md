# Use interaction

Self-registers the `use` action: physical E and the controller's right face button
(B on Xbox / Circle on PlayStation). The touch overlay calls this feature's `use()`
through the `interaction` group, once per touch press.

An interactable is a Node3D in the `interactables` group with these methods:

- `can_use(player: Player) -> bool`: range/aim/visibility eligibility.
- `interaction_text() -> String`: the local prompt.
- `use() -> void`: sends a request to the server.

The feature selects the nearest eligible entity while gameplay is active. Every
entity must independently validate the sender and eligibility on the server;
the client-side prompt is only a convenience.
