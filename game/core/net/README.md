# Shared entity networking

Use `NetworkedEntity` for new server-owned shared objects. It is a child component,
so the owning node can be a `Node`, `Node3D`, physics body or another existing type.
Use `NetworkedInteraction` for objects activated by a nearby player. Doors and item
pickups are working examples. Player movement keeps its existing client authority.

## Request process

1. The client calls `entity.request_action(action, payload)`.
2. The component sends the request to the server. Sender identity comes from the
   transport, never a payload field.
3. The server looks up the registered action. Unknown actions are rejected. It checks
   the payload size, shared action cooldown and the feature's validation callback.
4. The feature's apply callback commits the change on the server and returns success.
5. Godot replicates the declared state fields. The requester receives
   `request_finished(action, result)` with accepted, denied, cooldown or invalid action/payload.

Callbacks run synchronously. Validation must check permissions and the full payload
schema without mutating state. Apply returns `false` if it cannot commit. Do not yield
inside either callback. Cooldowns start only after an accepted change.

The component never calls a method or sets a property named by a client. Register
trusted callbacks locally during the owner's `_ready()`. No actions are enabled by default.

## Declare state

Add a Node named `NetworkedEntity` with `networked_entity.gd` attached:

```ini
[node name="NetworkedEntity" type="Node" parent="."]
script = ExtResource("entity_script")
replicated_properties = Array[NodePath]([NodePath(".:net_enabled")])
```

Properties are relative to `target_path`, which defaults to the parent. The component
creates its server-owned `Sync` child. `replicated_properties` send on change;
`continuous_properties` send at `replication_interval`. Both include initial state
for spawning and late joins. Declare each field in one place; remove the old synchronizer
when migrating it. Do not synchronize nodes, objects or resources as state values.

## Register gameplay rules

```gdscript
@export var net_enabled := false
@onready var entity: NetworkedEntity = $NetworkedEntity

func _ready() -> void:
    entity.register_action(&"toggle", _may_toggle, _toggle, 0.25)

func _may_toggle(peer: int, payload: Dictionary) -> bool:
    return payload.is_empty() and peer == allowed_peer

func _toggle(_peer: int, _payload: Dictionary) -> bool:
    net_enabled = not net_enabled
    return true
```

For a nearby player interaction, attach `networked_interaction.gd` instead:

```gdscript
@onready var entity: NetworkedInteraction = $NetworkedEntity

func _ready() -> void:
    entity.register_use(can_use, _apply_use, 0.25)

func use() -> void:
    entity.request_use()

func can_use(player: Player) -> bool:
    return entity.in_range(player) and not already_taken

func _apply_use(player: Player) -> bool:
    # The server resolved this player from the authenticated sender.
    return give_item_to(player)
```

The interaction component rejects extra payload fields, finds the sender's player
and checks `interaction_range` from `interaction_offset` on the target. Keep key,
inventory, money and other gameplay rules in the feature callback.

## Lifecycle and migration

### Private instance membership

Player movement is filtered by `ZoneInstances.can_observe_player()` using a small
server-replicated membership roster. Owners and the server always receive their
player state; other peers receive it only in the same instance (or shared hub).
The player's `Sync` roots at `MovementState` and addresses the parent `net_*`
fields. This separates movement visibility from the spawned Player identity,
which remains available for global chat, account bookkeeping and owner teleports.
Unrelated remote player visuals and collision capsules are disabled locally.
`test_player_relevance.gd` exercises the actual player spawner with a server and
three clients, including private movement, owner teleport and hub return.

A privately spawned scene may place its entities under a root implementing
`network_peer_allowed(peer: int) -> bool`. `ZoneScope` in `features/zone_instances`
implements this using the server and the instance's current members. Set its
membership before adding the scene to the tree. The root synchronizer controls
spawn visibility, and descendant `NetworkedEntity` synchronizers filter state
with the same policy. Registered actions reject outsiders before calling gameplay
validation; broadcast events are sent only to allowed peers. Shared entities
without such a root retain their existing policy.

Use `replace_members()` when someone joins or leaves. It refreshes authoritative
synchronizer visibility, including the root's spawn visibility. This component
does not assign player zones or create map instances by itself; the zone service
owns those transitions. Real ENet privacy/revocation coverage lives in
`tests/features/zone_instances/test_scope_network.gd`.

For transient effects, the server calls `entity.send_event(event, payload, peer)`.
Omit `peer` to broadcast, or supply an authenticated recipient for an owner-only event.
Listen to `event_received` on clients. These reliable authority-only events are never
replayed to late joiners. Use them for sounds and ladder mounting; persistent state
still belongs in replicated properties. Client calls to `send_event` do nothing.

- Static endpoints must exist at matching paths before connecting on every peer.
  Keep components outside streamed room geometry.
- Dynamic entities use `MultiplayerSpawner` on the server. Set spawn data and stable
  names in its spawn function. Free them on the server with `queue_free()` so the
  spawner removes them everywhere. The component does not create a second spawn system.
- The `session_reset(mode)` signal fires on the server after a network mode change.
  Reset session-owned gameplay state there. The component clears action cooldowns.
- Existing feature RPCs may delegate to `receive_legacy_action` during migration.
  It preserves the real RPC sender and uses the same checks. New callers use
  `request_action` or `request_use`; do not add more feature-specific transport code.
- Migrate features when changing their networking. Existing specialized systems
  retain their authority rules until migrated. This component does not rewrite all
  networking or add server reconciliation for client-owned movement.

Automated coverage: `tests/unit/test_networked_entity.gd` and
`godot --headless --path game -s scripts/network_checks.gd -- doors`. The latter exercises a
generic spawned counter plus doors/pickups, including rejected requests, authenticated
senders, replication, late joins and removal on all peers.
