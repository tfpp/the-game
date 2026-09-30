# Connected casino wing and vault kit

The live Golden Crown north wall has a three-metre doorway at `(0, 0, -34)`.
Walk through the promenade into the gaming hall, lounge and card room. Beyond
these, the crossroads connects a bar and an office corridor with a corner.
Physical stairs descend four metres to the vault lobby, security office,
counting room and vault. GPS lists the named rooms. The vault door uses the
existing server-authoritative sliding-door interaction; press E to open it.

This first layout deliberately fixes the route graph. `layout.gd` composes
variable-size rectangular room shells through the existing W03 attachment
contract. Unused sockets are capped; joined boundary rings share indexed shell
vertices and one structural collision mesh. The casino entrance is the only
external open socket. The original casino games and garage elevator remain in
place. The vault is a room/set-piece foundation; its gold and safes are scenery,
with no new robbery, reward, combat or safe-zone rules.

## Furnishing catalogue

`catalogue.gd` declares reusable slot banks, card tables, bar counters, lounge
sets, desks, security desks, counting desks, safe banks and gold racks. Each
`ProceduralSetDefinition` supplies a packed scene, floor-centred footprint and
allowed room roles. Props reuse existing casino models and small textures.

Each room's population rule declares allowed set IDs, optional weights,
quarter-turn rotations, density, local slots, placement bounds and forbidden
volumes. A set is chosen only among those fitting the available slot. The
central three-metre aisle and attached side-door cross aisles are reserved.
Changing `furnishing_seed` on `feature.tscn` varies furnishings deterministically
on every peer while preserving the route. Do not reroll independently on a
client. Empty catalogues preserve the existing garage population behavior.

To extend the kit, add a set scene and catalogue definition, then opt room roles
into it. To compose another room, use `room_kit.gd` and attach its sockets through
`ProceduralSocketAttachment.attach`; do not manually approximate doorway poses.
Keep the graph stable for shared games and check room volumes and traversal.

## Validation and previews

`tests/features/casino_wing/test_casino_wing.gd` checks graph reachability, exact
socket alignment, standing capsule clearance and floor support, room separation,
actual model bounds against declared placement footprints, deterministic role
filtering, the casino entrance and actual player stair traversal both ways.
Existing garage/lift tests cover backward compatibility of shared systems.

Run native screenshot capture with your Godot binary:

```sh
godot --path game --rendering-method gl_compatibility \
  res://features/casino_wing/tools/capture.tscn -- \
  "$PWD/docs/design/previews/casino-wing"
```

The checked-in previews show the gaming hall, card room, bar, stairs, vault door,
vault interior and connected room layout.
