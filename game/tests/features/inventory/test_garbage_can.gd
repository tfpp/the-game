extends GutTest
## The garbage can empties only the requester's carried items, after confirmation,
## within range, and sits clear on the lobby floor beside the wardrobe counter.

const CAN := preload("res://features/inventory/garbage_can.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const FEATURE := preload("res://features/inventory/feature.tscn")
const ROOM := preload("res://world/room.tscn")

var _can: GarbageCan
var _hand: Hand
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_can = CAN.instantiate() as GarbageCan
	add_child_autofree(_can)
	_player.net_position = Vector3(1, 0, 0)


func after_each() -> void:
	Controls.start()
	await get_tree().process_frame


func test_empty_inventory_cannot_be_trashed() -> void:
	assert_false(_can.can_use(_player))
	_hand.inventory().collect("shirt:2")
	assert_false(_can.can_use(_player), "Worn clothes are not carried items")
	_hand.inventory().collect("banana")
	assert_true(_can.can_use(_player))


func test_use_only_asks_for_confirmation() -> void:
	_fill()
	_can.use()
	assert_true(_can.is_confirming())
	assert_true(_can.is_in_group(&"modal_ui"), "Gameplay input pauses behind the dialog")
	assert_eq(_hand.net_item_id, "pistol", "Nothing is thrown away before confirming")
	_can._close()
	assert_false(_can.is_confirming())
	assert_false(_can.is_in_group(&"modal_ui"))
	assert_eq(_hand.net_item_id, "pistol")


func test_confirm_empties_hand_and_backpack_but_keeps_clothes_and_keys() -> void:
	_fill()
	_can.use()
	_can.confirm()
	var inventory := _hand.inventory()
	assert_false(_can.is_confirming())
	assert_eq(_hand.net_item_id, "")
	assert_eq(inventory.backpack.count(""), PlayerInventory.CAPACITY)
	assert_eq(inventory.shirt, "shirt:2")
	assert_eq(inventory.keys, PackedStringArray(["upper_study_key"]))


func test_out_of_range_confirm_changes_nothing() -> void:
	_fill()
	_player.net_position = Vector3(10, 0, 0)
	_can.confirm()
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_hand.inventory().backpack[0], "banana")


func test_foreign_peer_cannot_empty_another_players_inventory() -> void:
	_fill()
	assert_false(_can.entity._validate_use(7, {}), "Peer 7 has no player in range")
	assert_eq(_hand.net_item_id, "pistol")


func test_clear_carried_waits_for_loading() -> void:
	_fill()
	_hand.inventory().loading = true
	assert_eq(_hand.inventory().clear_carried(), 0)
	_hand.inventory().loading = false
	assert_eq(_hand.inventory().clear_carried(), 2)


func test_can_stands_on_the_lobby_floor_clear_of_the_wardrobe_counter() -> void:
	var feature := FEATURE.instantiate()
	var position := (feature.get_node("GarbageCan") as Node3D).position
	feature.free()
	var room := ROOM.instantiate() as Node3D
	add_child_autofree(room)
	await wait_physics_frames(3)
	var space := room.get_world_3d().direct_space_state
	var floor := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(position + Vector3.UP * 2, position + Vector3.DOWN)
	)
	assert_false(floor.is_empty())
	if not floor.is_empty():
		assert_almost_eq((floor["position"] as Vector3).y, position.y, 0.03, "Sits on the floor")
	var clear := {Vector3.LEFT: 2.0, Vector3.RIGHT: 0.4, Vector3.FORWARD: 2.0, Vector3.BACK: 1.0}
	for direction: Vector3 in clear:
		var from := position + Vector3.UP * 0.5
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + direction * float(clear[direction]))
		)
		assert_true(hit.is_empty(), "Clear %s of the can" % direction)


func _fill() -> void:
	var inventory := _hand.inventory()
	inventory.collect("pistol")
	inventory.collect("banana")
	inventory.collect("shirt:2")
	inventory.collect("upper_study_key")
