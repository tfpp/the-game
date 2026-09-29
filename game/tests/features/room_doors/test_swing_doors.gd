extends GutTest

const DOOR := preload("res://features/room_doors/swing_door.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PICKUP := preload("res://features/holdables/item_pickup.tscn")
const KEY_SCRIPT := preload("res://features/room_doors/room_key_pickup.gd")
const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Doorways := preload("res://features/world_builder/doorways.gd")

var _player: Player
var _hand: Hand


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_move(Vector3(0, 1, -1.5))
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func _move(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at


func _door(locked: bool = false) -> SwingDoor:
	var door := DOOR.instantiate() as SwingDoor
	if locked:
		door.key_id = "upper_study_key"
	add_child_autofree(door)
	return door


func test_open_close_range_cooldown_and_both_swing_directions() -> void:
	var door := _door()
	_move(Vector3(0, 1, -10))
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.CLOSED)
	_move(Vector3(0, 1, -1.5))
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN, "Rapid repeated Use is ignored")
	await wait_seconds(0.5)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.CLOSED)
	await wait_seconds(0.5)
	_move(Vector3(0, 1, 1.5))
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_OUT)


func test_locked_door_requires_key_then_stays_unlocked_for_everyone() -> void:
	var door := _door(true)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.LOCKED)
	assert_true(_hand.inventory().collect("upper_study_key"))
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)
	_hand.inventory().keys = PackedStringArray()
	await wait_seconds(0.5)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.CLOSED)
	await wait_seconds(0.5)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN, "Unlock persists without the key holder")


func test_other_player_blocks_swing_and_mode_change_resets_lock() -> void:
	var door := _door(true)
	assert_true(_hand.inventory().collect("upper_study_key"))
	var other := PLAYER.instantiate() as Player
	other.name = "2"
	other.set_multiplayer_authority(2)
	add_child_autofree(other)
	other.set_physics_process(false)
	other.net_position = Vector3(0, 1, 0.8)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.LOCKED)
	other.net_position = Vector3(10, 1, 10)
	door.request_use()
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)
	door._reset(Network.Mode.OFFLINE)
	assert_eq(door.net_state, SwingDoor.State.LOCKED)


func test_key_ring_accepts_key_with_full_bag_and_prevents_duplicates() -> void:
	var inventory := _hand.inventory()
	for index: int in PlayerInventory.CAPACITY + 1:
		assert_true(inventory.collect("banana"))
	assert_true(inventory.can_collect("upper_study_key"))
	assert_true(inventory.collect("upper_study_key"))
	assert_true(inventory.has_key("upper_study_key"))
	assert_false(inventory.collect("upper_study_key"))
	assert_eq(inventory.keys.size(), 1)
	assert_eq(inventory.backpack.count("banana"), PlayerInventory.CAPACITY)


func test_key_pickup_validates_range_and_recovers_after_holder_leaves() -> void:
	var door := _door(true)
	var key := PICKUP.instantiate() as ItemPickup
	key.set_script(KEY_SCRIPT)
	key.item_id = "upper_study_key"
	add_child_autofree(key)
	key.set("locked_door", key.get_path_to(door))
	_move(Vector3(10, 1, 10))
	key.request_pickup()
	assert_false(key.net_taken)
	_move(Vector3(0, 1, -1))
	key.request_pickup()
	assert_true(key.net_taken)
	assert_true(_hand.inventory().has_key(key.item_id))
	await wait_seconds(0.6)
	assert_true(key.net_taken)
	_hand.queue_free()
	await wait_seconds(0.6)
	assert_false(key.net_taken, "Key respawns when its holder leaves before unlocking")


func test_generated_partition_and_leaf_block_closed_door_and_clear_open_door() -> void:
	var layout := Layout.compile(_spec())
	assert_eq(layout["errors"], [])
	var world := Builder.build(layout)
	add_child_autofree(world)
	var doors := Doorways.runtime_scene(layout)
	world.add_child(doors)
	var door := doors.get_child(0) as SwingDoor
	_move(door.to_global(Vector3(0, 1, -1.5)))
	await wait_physics_frames(3)
	var space := world.get_world_3d().direct_space_state
	for x: float in [-1.8, 0, 1.8]:
		var query := PhysicsRayQueryParameters3D.create(
			door.to_global(Vector3(x, 1, -1)), door.to_global(Vector3(x, 1, 1))
		)
		query.exclude = [_player.get_rid()]
		assert_false(space.intersect_ray(query).is_empty(), "Closed partition blocks passage")
	door.request_use()
	await wait_seconds(0.5)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (_player.get_node("Collider") as CollisionShape3D).shape
	query.transform = Transform3D(door.global_basis, door.to_global(Vector3(0, 1, -1)))
	query.motion = door.global_basis * Vector3(0, 0, 2)
	query.exclude = [_player.get_rid()]
	assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Player hull clears open door")


func test_door_spec_validation_rejects_bad_ids_dimensions_and_duplicate_ids() -> void:
	for definition: Variant in [
		null, {}, {"id": "../Bad"}, {"id": "Door", "width": 5}, {"id": "Door", "height": 9}
	]:
		var spec := _spec()
		spec["connections"][0]["door"] = definition
		assert_false(Layout.compile(spec)["errors"].is_empty())
	var spec := _spec()
	spec["rooms"].append({"id": "Third", "at": [0, 40], "size": [8, 8]})
	spec["connections"].append({"from": "Upper", "to": "Third", "door": {"id": "Door"}})
	assert_false(Layout.compile(spec)["errors"].is_empty())


func _spec() -> Dictionary:
	return {
		"version": 1,
		"hall_width": 5,
		"style": {"lights": false},
		"rooms":
		[
			{"id": "Lower", "at": [0, 0], "size": [8, 8]},
			{"id": "Upper", "at": [0, 20], "size": [8, 8]}
		],
		"connections": [{"from": "Lower", "to": "Upper", "door": {"id": "Door"}}]
	}
