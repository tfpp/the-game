# Use interaction

Self-registers the `use` action: physical E and the controller's right face button
(B on Xbox / Circle on PlayStation). The touch overlay calls this feature's `use()`
through the `interaction` group, once per touch press.

An interactable is a Node3D in the `interactables` group with these methods:

- `can_use(player: Player) -> bool`: range/aim/visibility eligibility.
- `interaction_text() -> String`: the local prompt.
- `use() -> void`: sends a request to the server.
- Optional `interaction_color() -> Color`: cosmetic prompt color, default white.
  Valuable pickups use their catalog rarity color and retain plain-text names/prices.

The feature selects the nearest eligible entity while gameplay is active. Every
entity must independently validate the sender and eligibility on the server;
the client-side prompt is only a convenience.

`target_text() -> String` returns the current eligible target's interaction text,
or an empty string when none is usable. WebXR uses this for its 3D prompt and calls
the same `use()` entry point as touch; server checks are unchanged.
