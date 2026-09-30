extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const THROWN := preload("res://features/holdables/thrown_item.tscn")
var _hand: Hand
var _player: Player


class DropSink:
	extends Node
	var items: Array[String] = []

	func spawn_thrown_item(id: String, _from: Vector3, _to: Vector3) -> void:
		items.append(id)


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)


func after_each() -> void:
	await get_tree().process_frame


func test_each_item_needs_three_separate_actions_and_cannot_use_a_fourth() -> void:
	for kind: String in ["cigarette", "beer"]:
		assert_true(_hand.try_equip(kind))
		for remaining: int in [3, 2, 1]:
			var id := _hand.net_item_id
			assert_eq(ItemCatalog.uses_remaining(id), remaining)
			_hand.request_primary_action()
			assert_true(_hand.consumption.active())
			assert_eq(_hand.consumption.view_id(), kind)
			_hand.request_primary_action()
			_hand.request_drop_item()
			_hand.inventory().request_stow(-1)
			assert_eq(_hand.net_item_id, id)
			_hand._process(3.1)
			assert_false(_hand.consumption.active())
			assert_eq(ItemCatalog.uses_remaining(_hand.net_item_id), remaining - 1)
			_hand._process(10.0)
			assert_eq(ItemCatalog.uses_remaining(_hand.net_item_id), remaining - 1)
		assert_eq(_hand.net_item_id, "")
		_hand.request_primary_action()
		assert_false(_hand.consumption.active())


func test_partial_items_keep_uses_through_stow_swap_drop_and_pickup() -> void:
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	for kind: String in ["cigarette", "beer"]:
		_hand.inventory().collect(kind)
		_hand.request_primary_action()
		_hand._process(3.1)
		_hand.inventory().request_stow(-1)
		assert_eq(_hand.inventory().backpack[0], kind + ":2")
		_hand.inventory().collect(kind)
		_hand.inventory().request_equip(0)
		assert_eq(_hand.inventory().backpack[0], kind, "Fresh items remain independent")
		_hand.request_primary_action()
		_hand._process(3.1)
		# Exercise both hand-drop and inventory-drop paths.
		if kind == "beer":
			_hand.inventory().request_drop(-1)
		else:
			_hand.request_drop_item()
		assert_eq(sink.items.back(), kind + ":1")
		var thrown := THROWN.instantiate() as ThrownItem
		thrown.item_id = sink.items.back()
		thrown.net_landed = true
		add_child_autofree(thrown)
		thrown.set_physics_process(false)
		assert_true(thrown.interaction_text().contains("1"))
		thrown.request_pickup()
		thrown.request_pickup()
		assert_eq(_hand.net_item_id, kind + ":1")
		assert_eq(_hand.inventory().backpack.count(""), 7)
		_hand.request_primary_action()
		_hand._process(3.1)
		assert_eq(_hand.net_item_id, "")
		_hand.inventory().request_equip(0)
		assert_eq(_hand.net_item_id, kind, "The other item still has three uses")
		_hand.net_item_id = ""


func test_catalog_reuses_models_and_rejects_invalid_use_counts() -> void:
	for kind: String in ["cigarette", "beer"]:
		var original := ItemCatalog.find(kind)
		for remaining: int in [1, 2]:
			var partial := ItemCatalog.find("%s:%d" % [kind, remaining])
			assert_eq(partial.view_scene, original.view_scene)
			assert_eq(partial.weight, original.weight)
			assert_eq(partial.ground_clearance, original.ground_clearance)
			assert_true(partial.display_name.contains(str(remaining)))
		assert_false(original.display_name.contains("left"), "Do not mutate shared resources")
		for suffix: String in [":0", ":3", ":4", ":-1", ":01", ":2:1"]:
			assert_null(ItemCatalog.find(kind + suffix))
			assert_false(_hand.inventory().collect(kind + suffix))


func test_partial_use_snapshot_and_foreign_requests_preserve_remaining_count() -> void:
	_hand.net_item_id = "cigarette:1"
	var entity := _hand.consumption.entity
	assert_eq(entity._evaluate(2, &"consume", {}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(1, &"consume", {"uses": 3}), NetworkedEntity.Result.DENIED)
	_hand.request_primary_action()
	_hand._process(1.2)
	var late := HAND.instantiate() as Hand
	late.peer_id = 1
	add_child_autofree(late)
	late.set_process(false)
	late.net_item_id = _hand.net_item_id
	late.consumption.state = _hand.consumption.state.duplicate()
	late._process(0)
	assert_eq(late.consumption.view_id(), "cigarette")
	assert_almost_eq(late.global_position, _hand.global_position, Vector3.ONE * 0.001)
	late._process(2.0)
	assert_eq(late.net_item_id, "", "Late snapshot must retain the final-puff stage")
	assert_null(late.held_view())
