class_name NetworkedEntity
extends Node
## Attach to any shared entity. Transport and replication stay here; rules stay in its owner.

signal request_finished(action: StringName, result: Result)
signal session_reset(mode: Network.Mode)
signal event_received(event: StringName, payload: Dictionary)

enum Result { ACCEPTED, UNKNOWN_ACTION, INVALID_PAYLOAD, DENIED, COOLDOWN }

const SERVER_PEER := MultiplayerPeer.TARGET_PEER_SERVER
const MAX_PAYLOAD_BYTES := 4096

## Property paths relative to target, e.g. .:net_open or Inventory:keys.
@export var replicated_properties: Array[NodePath] = []
## Optional continuously replicated properties (positions etc.). Others send on change.
@export var continuous_properties: Array[NodePath] = []
@export var replication_interval := 0.05
@export var target_path := NodePath("..")

var _actions: Dictionary[StringName, Action] = {}
var _sync: MultiplayerSynchronizer


class Action:
	extends RefCounted
	var validate: Callable
	var apply: Callable
	var cooldown_msec: int
	var next_msec := 0


func _enter_tree() -> void:
	# The component owns its RPC endpoint, independently of its parent's node type.
	set_multiplayer_authority(SERVER_PEER)


func _ready() -> void:
	_configure_replication()
	Network.mode_changed.connect(_on_session_changed)


func target() -> Node:
	return get_node(target_path)


func is_authority() -> bool:
	# Detached nodes have no multiplayer API; release builds crash calling into null.
	return is_inside_tree() and multiplayer.is_server() and is_multiplayer_authority()


## Register trusted callbacks once in the owning feature's _ready.
## Both receive (authenticated_peer: int, payload: Dictionary) and return bool.
## Validation must not mutate state; apply commits synchronously on the server.
func register_action(
	action: StringName, validate: Callable, apply: Callable, cooldown_seconds: float = 0.0
) -> bool:
	if action.is_empty() or _actions.has(action) or not validate.is_valid() or not apply.is_valid():
		return false
	if not is_finite(cooldown_seconds) or cooldown_seconds < 0:
		return false
	var entry := Action.new()
	entry.validate = validate
	entry.apply = apply
	entry.cooldown_msec = ceili(cooldown_seconds * 1000)
	_actions[action] = entry
	return true


## The only feature-facing send API. Identity always comes from the transport.
func request_action(action: StringName, payload: Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_receive_action.rpc_id(SERVER_PEER, action, payload)


## Migration adapter for existing feature RPCs. Keeps the original remote sender
## and runs exactly the same authority, validation, cooldown and reply path.
func receive_legacy_action(action: StringName, payload: Dictionary = {}) -> void:
	_receive_action(action, payload)


## Transient server events (audio, mounting, effects); never replayed on late join.
## peer=0 broadcasts, otherwise only that authenticated peer receives it.
func send_event(event: StringName, payload: Dictionary = {}, peer: int = 0) -> void:
	if not is_authority():
		return
	if peer == 0 and _network_scope() == null:
		_receive_event.rpc(event, payload)
	elif peer != 0 and peer_allowed(peer):
		_receive_event.rpc_id(peer, event, payload)
	elif peer == 0:
		for recipient: int in multiplayer.get_peers():
			if peer_allowed(recipient):
				_receive_event.rpc_id(recipient, event, payload)
		if peer_allowed(multiplayer.get_unique_id()):
			_receive_event(event, payload)


## An instance root owns membership. Shared entities have no scope and retain
## their existing visibility. Requests and transient events use the same policy.
func peer_allowed(peer: int) -> bool:
	var scope := _network_scope()
	return scope == null or bool(scope.call("network_peer_allowed", peer))


func _network_scope() -> Node:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("network_peer_allowed"):
			return ancestor
		ancestor = ancestor.get_parent()
	return null


@rpc("authority", "call_local", "reliable")
func _receive_event(event: StringName, payload: Dictionary) -> void:
	event_received.emit(event, payload)


@rpc("any_peer", "call_local", "reliable")
func _receive_action(action: StringName, payload: Dictionary) -> void:
	if not is_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer := sender if sender != 0 else multiplayer.get_unique_id()
	var result := _evaluate(peer, action, payload)
	_action_result.rpc_id(peer, action, result)


@rpc("authority", "call_local", "reliable")
func _action_result(action: StringName, result: Result) -> void:
	request_finished.emit(action, result)


# gdlint: disable=max-returns
func _evaluate(peer: int, action: StringName, payload: Dictionary) -> Result:
	if not is_authority():
		return Result.DENIED
	if not peer_allowed(peer):
		return Result.DENIED
	if not _actions.has(action):
		return Result.UNKNOWN_ACTION
	if var_to_bytes(payload).size() > MAX_PAYLOAD_BYTES:
		return Result.INVALID_PAYLOAD
	var entry := _actions[action]
	if Time.get_ticks_msec() < entry.next_msec:
		return Result.COOLDOWN
	if not entry.validate.is_valid() or not entry.apply.is_valid():
		return Result.DENIED
	if not bool(entry.validate.call(peer, payload)):
		return Result.DENIED
	if not bool(entry.apply.call(peer, payload)):
		return Result.DENIED
	entry.next_msec = Time.get_ticks_msec() + entry.cooldown_msec
	return Result.ACCEPTED


func _configure_replication() -> void:
	var config := SceneReplicationConfig.new()
	for property: NodePath in replicated_properties + continuous_properties:
		if config.has_property(property):
			continue
		config.add_property(property)
		config.property_set_spawn(property, true)
		config.property_set_replication_mode(
			property,
			(
				SceneReplicationConfig.REPLICATION_MODE_ALWAYS
				if property in continuous_properties
				else SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
			)
		)
	if config.get_properties().is_empty():
		return
	_sync = MultiplayerSynchronizer.new()
	_sync.name = "Sync"
	_sync.root_path = NodePath("../" + str(target_path))
	_sync.replication_config = config
	_sync.replication_interval = replication_interval
	_sync.set_multiplayer_authority(SERVER_PEER)
	if _network_scope() != null:
		_sync.add_visibility_filter(peer_allowed)
	add_child(_sync)
	if _network_scope() != null:
		_sync.update_visibility()


func _on_session_changed(mode: Network.Mode) -> void:
	for entry: Action in _actions.values():
		entry.next_msec = 0
	if is_authority():
		session_reset.emit(mode)
