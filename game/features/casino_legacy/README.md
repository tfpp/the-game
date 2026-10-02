# Old casino access

The **OLD CASINO** door on the new casino's north promenade at (-21, 0, -18.8)
teleports to the retained `res://world/room.tscn` at world offset (500, 0, 500).
The **NEW CASINO** door on its south promenade returns to a safe landing at
(-21, 1, -16.8). Existing `GarageDoor` handles server validation, range checks
and player teleportation. Both rooms exist on every peer; no scene switching or
new RPC implementation is introduced.

The original layout, stairs, gallery, static patrons and scenery are retained.
Eight current slot-machine prefabs and a roulette table are also instantiated,
with their bases lowered 0.25 m to match the old -1.5 m pit. They keep their existing
`NetworkedInteraction` components and share the active wallet. Removed/relocated
features such as the old shops, companions and attractions are not automatically
restored; this is a reachable comparison/fallback room, not a historical game build.

The old room's WorldEnvironment is overridden to null, so it does not replace the
new casino's shared indoor lighting. Its GPS area bounds provide the correct room
visibility extent. The distant room lives in its own feature, keeping it out of
main casino world bounds and existing geometry/collision tests.

Tests cover the validated door round trip, out-of-range rejection, floor support,
arrival capsule clearance and presence of working gambling prefabs. Full game and
multiplayer checks verify that the auto-loaded feature has matching peer paths.

## Developer access

Since issue #438 this entrance is a development door: it stays hidden and locked until `sv_cheats 1` (see [dev access](../dev_access/README.md)).
