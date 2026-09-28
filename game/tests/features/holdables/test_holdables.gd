extends GutTest
## Integration coverage for the pickup <-> hand flow (features/holdables/item_pickup.gd,
## hand.gd): who can pick up what, and what each item category's primary action does.
## Runs single-process, so `multiplayer.get_remote_sender_id()` is 0 and every RPC here
## resolves to peer 1 — the same trick test_slot_machine.gd uses to call server RPCs
## directly instead of standing up real peers (see harness/net_smoke.sh for that).

const HandScene := preload("res://features/holdables/hand.tscn")
const ItemPickupScene := preload("res://features/holdables/item_pickup.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _player: Player
var _hand: Hand


class _ThrowStub:
	extends Node
	var spawned_item_id := ""
	var spawned_from := Vector3.ZERO

	func spawn_thrown_item(item_id: String, from: Vector3, _to: Vector3) -> void:
		spawned_item_id = item_id
		spawned_from = from


func before_each() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	await get_tree().physics_frame


func _pickup_at(item_id: String, position: Vector3) -> ItemPickup:
	var pickup := ItemPickupScene.instantiate() as ItemPickup
	pickup.item_id = item_id
	add_child_autofree(pickup)
	pickup.global_position = position
	return pickup


func test_pickup_in_range_hands_the_item_to_an_empty_hand() -> void:
	var pickup := _pickup_at("pistol", _player.global_position)
	await get_tree().physics_frame
	assert_true(pickup.can_use(_player))
	pickup.request_pickup()
	assert_true(pickup.net_taken)
	assert_eq(_hand.net_item_id, "pistol")


func test_pickup_out_of_range_cannot_be_used() -> void:
	var far := _player.global_position + Vector3(0, 0, ItemPickup.PICKUP_RANGE + 1.0)
	var pickup := _pickup_at("ball", far)
	await get_tree().physics_frame
	assert_false(pickup.can_use(_player))


func test_a_full_hand_cannot_pick_up_another_item() -> void:
	_hand.net_item_id = "banana"
	var pickup := _pickup_at("ball", _player.global_position)
	await get_tree().physics_frame
	assert_false(pickup.can_use(_player))
	pickup.request_pickup()
	assert_false(pickup.net_taken)
	assert_eq(_hand.net_item_id, "banana")


func test_an_already_taken_pickup_stays_taken() -> void:
	var pickup := _pickup_at("banana", _player.global_position)
	await get_tree().physics_frame
	pickup.request_pickup()
	assert_eq(_hand.net_item_id, "banana")
	# A second hand shouldn't be able to grab the same, now-empty, pickup.
	var other_hand := HandScene.instantiate() as Hand
	other_hand.peer_id = 2
	add_child_autofree(other_hand)
	assert_false(pickup.can_use(_player))


func test_empty_hand_primary_action_does_nothing() -> void:
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")


func test_eating_food_consumes_it() -> void:
	_hand.net_item_id = "banana"
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")


func test_firing_a_weapon_keeps_it_in_hand_and_starts_a_cooldown() -> void:
	_hand.net_item_id = "pistol"
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "pistol")
	assert_gt(_hand._fire_cooldown, 0.0)


func test_throwing_a_prop_empties_the_hand_and_asks_holdables_to_spawn_it() -> void:
	var stub := _ThrowStub.new()
	stub.add_to_group(&"holdables_root")
	add_child_autofree(stub)
	_hand.net_item_id = "ball"
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_eq(stub.spawned_item_id, "ball")


func test_requests_from_another_peer_are_ignored() -> void:
	_hand.net_item_id = "banana"
	_hand.peer_id = 2  # Pretend this hand belongs to someone else.
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "banana")
