extends GutTest

var _scope: ZoneScope
var _counter: Counter
var _entity: NetworkedEntity


class Counter:
	extends Node
	@export var value := 0
	var applied_peer := 0

	func validate(_peer: int, payload: Dictionary) -> bool:
		return payload.is_empty()

	func apply(peer: int, _payload: Dictionary) -> bool:
		value += 1
		applied_peer = peer
		return true


func before_each() -> void:
	_scope = ZoneScope.new()
	_scope.members = [7, 8]
	_counter = Counter.new()
	_entity = NetworkedEntity.new()
	_entity.replicated_properties = [NodePath(".:value")]
	_entity.name = "NetworkedEntity"
	_counter.add_child(_entity)
	_scope.add_child(_counter)
	add_child_autofree(_scope)
	_entity.register_action(&"increment", _counter.validate, _counter.apply)


func test_unrelated_peer_cannot_mutate_even_with_valid_payload() -> void:
	assert_eq(_entity._evaluate(9, &"increment", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_counter.value, 0)
	assert_eq(_entity._evaluate(7, &"increment", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_counter.value, 1)
	assert_eq(_counter.applied_peer, 7)


func test_membership_updates_revoke_requests_and_allow_new_member() -> void:
	_scope.replace_members([9])
	assert_false(_entity.peer_allowed(7))
	assert_true(_entity.peer_allowed(9))
	assert_true(_entity.peer_allowed(1))
	assert_eq(_entity._evaluate(7, &"increment", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_entity._evaluate(9, &"increment", {}), NetworkedEntity.Result.ACCEPTED)


func test_shared_entities_keep_existing_policy() -> void:
	_scope.remove_child(_counter)
	add_child(_counter)
	assert_true(_entity.peer_allowed(123))
	assert_eq(_entity._evaluate(123, &"increment", {}), NetworkedEntity.Result.ACCEPTED)
	remove_child(_counter)
	_scope.add_child(_counter)


func test_server_receives_scoped_events_without_remote_members() -> void:
	watch_signals(_entity)
	_entity.send_event(&"blast", {"power": 2})
	assert_signal_emitted_with_parameters(_entity, "event_received", [&"blast", {"power": 2}])
	assert_not_null(_entity.get_node_or_null("Sync"))
