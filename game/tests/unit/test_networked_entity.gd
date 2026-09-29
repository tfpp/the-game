extends GutTest

var _entity: NetworkedEntity
var _target: Counter
var _result: NetworkedEntity.Result


class Counter:
	extends Node
	@export var value := 0
	@export var position_sample := Vector3.ZERO
	var last_peer := 0
	var allowed := true

	func validate(_peer: int, payload: Dictionary) -> bool:
		return (
			allowed
			and payload.size() == 1
			and payload.get("amount") is int
			and payload["amount"] in [1, 2, 3]
		)

	func apply(peer: int, payload: Dictionary) -> bool:
		last_peer = peer
		value += int(payload["amount"])
		return true


func before_each() -> void:
	_target = Counter.new()
	_entity = NetworkedEntity.new()
	_entity.name = "NetworkedEntity"
	_entity.replicated_properties = [NodePath(".:value")]
	_entity.continuous_properties = [NodePath(".:position_sample")]
	_target.add_child(_entity)
	add_child_autofree(_target)
	_entity.request_finished.connect(_finished)
	assert_true(_entity.register_action(&"add", _target.validate, _target.apply, 0.1))


func _finished(_action: StringName, result: NetworkedEntity.Result) -> void:
	_result = result


func test_registered_actions_commit_on_server_and_report_authenticated_sender() -> void:
	_entity.request_action(&"add", {"amount": 2})
	assert_eq(_result, NetworkedEntity.Result.ACCEPTED)
	assert_eq(_target.value, 2)
	assert_eq(_target.last_peer, 1)


func test_unknown_actions_invalid_payloads_and_denied_permissions_cannot_mutate() -> void:
	_entity.request_action(&"set", {"value": 99})
	assert_eq(_result, NetworkedEntity.Result.UNKNOWN_ACTION)
	_entity.request_action(&"add", {"amount": "1"})
	assert_eq(_result, NetworkedEntity.Result.DENIED)
	_entity.request_action(&"add", {"amount": 1, "peer": 99})
	assert_eq(_result, NetworkedEntity.Result.DENIED)
	_entity.request_action(&"add", {"amount": "x".repeat(4097)})
	assert_eq(_result, NetworkedEntity.Result.INVALID_PAYLOAD)
	_target.allowed = false
	_entity.request_action(&"add", {"amount": 1})
	assert_eq(_result, NetworkedEntity.Result.DENIED)
	assert_eq(_target.value, 0)


func test_actions_default_to_deny_and_cannot_overwrite_registered_handlers() -> void:
	assert_false(_entity.register_action(&"add", _target.validate, _target.apply))
	assert_false(_entity.register_action(&"empty", Callable(), _target.apply))
	assert_false(_entity.register_action(&"bad", _target.validate, _target.apply, NAN))
	_entity.request_action(&"empty")
	assert_eq(_result, NetworkedEntity.Result.UNKNOWN_ACTION)
	assert_eq(_target.value, 0)


func test_cooldown_is_shared_and_session_reset_clears_it() -> void:
	_entity.request_action(&"add", {"amount": 1})
	_entity.request_action(&"add", {"amount": 2})
	assert_eq(_result, NetworkedEntity.Result.COOLDOWN)
	assert_eq(_target.value, 1)
	var deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_entity.request_action(&"add", {"amount": 2})
	assert_eq(_target.value, 3)
	watch_signals(_entity)
	_entity._on_session_changed(Network.Mode.OFFLINE)
	assert_signal_emitted(_entity, "session_reset")
	_entity.request_action(&"add", {"amount": 1})
	assert_eq(_target.value, 4)


func test_replication_declaration_owns_only_component_and_includes_spawn_state() -> void:
	var sync := _entity.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_same(sync.get_node(sync.root_path), _target)
	var config := sync.replication_config
	assert_eq(config.get_properties().size(), 2)
	assert_true(config.property_get_spawn(NodePath(".:value")))
	assert_true(config.property_get_spawn(NodePath(".:position_sample")))
	assert_eq(
		config.property_get_replication_mode(NodePath(".:value")),
		SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	)
	assert_eq(
		config.property_get_replication_mode(NodePath(".:position_sample")),
		SceneReplicationConfig.REPLICATION_MODE_ALWAYS
	)


func test_legacy_adapter_uses_same_permissions_and_cooldown() -> void:
	_entity.receive_legacy_action(&"add", {"amount": 1})
	assert_eq(_target.value, 1)
	_entity.receive_legacy_action(&"add", {"amount": 1})
	assert_eq(_target.value, 1)
	assert_eq(_result, NetworkedEntity.Result.COOLDOWN)


func test_interaction_component_rejects_missing_player_and_forged_payload() -> void:
	var spatial := Node3D.new()
	var interaction := NetworkedInteraction.new()
	spatial.add_child(interaction)
	add_child_autofree(spatial)
	assert_true(
		interaction.register_use(
			func(_p: Player) -> bool: return true, func(_p: Player) -> bool: return true
		)
	)
	interaction.request_finished.connect(_finished)
	interaction.request_use()
	assert_eq(_result, NetworkedEntity.Result.DENIED)
	interaction.request_action(&"use", {"peer": 1})
	assert_eq(_result, NetworkedEntity.Result.DENIED)
