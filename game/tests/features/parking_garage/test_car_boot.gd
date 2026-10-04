extends GutTest

const WRECK := preload("res://features/parking_garage/car_wreck.tscn")
const CAR := preload("res://features/procedural_rooms/props/car.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const GARAGE := preload("res://features/procedural_rooms/prototype.tscn")
var _player: Player


func test_shared_wreck_keeps_paint_collision_and_damaged_variant() -> void:
	var car := WRECK.instantiate() as CarWreck
	add_child_autofree(car)
	var damaged := WRECK.instantiate() as CarWreck
	damaged.damaged = true
	damaged.position.x = 10
	add_child_autofree(damaged)
	await wait_physics_frames(2)
	var body := car.get_node("BodyPaint") as MeshInstance3D
	assert_not_null(body.mesh)
	assert_eq(body.mesh.get_surface_count(), 1)
	assert_true((car.get_node("Trim") as MeshInstance3D).mesh.get_surface_count() > 1)
	assert_eq(
		(body.get_surface_override_material(0) as StandardMaterial3D).albedo_color, car.body_color
	)
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -3), Vector3(0, 1, 3))
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	assert_eq(hit.get("collider"), car)
	assert_false((damaged.get_node("HoodPaint") as MeshInstance3D).visible)


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)


func _aim(boot: CarBoot, local_position: Vector3) -> void:
	_player.global_position = boot.get_parent().to_global(local_position)
	_player.net_position = _player.global_position
	var eye := (
		_player.global_position
		+ Vector3.UP * (_player.movement.eye_height_m() - _player.movement.hull_height_m() * .5)
	)
	var ray := (boot.global_position - eye).normalized()
	_player.yaw = atan2(-ray.x, -ray.z)
	_player.pitch = asin(ray.y)


func test_both_car_types_open_on_gaze_close_on_lookaway_and_keep_shared_loot() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	for scene: PackedScene in [WRECK, CAR]:
		var car := scene.instantiate() as Node3D
		add_child_autofree(car)
		var boot := car.get_node("Loot") as CarBoot
		boot.set_physics_process(false)
		boot.set_process(false)
		await wait_physics_frames(2)
		_aim(boot, Vector3(-3.4, .95, 0) if scene == WRECK else Vector3(0, .95, 3.3))
		assert_true(boot.can_use(_player), "Rear boot is aimed and reachable")
		boot._physics_process(.1)
		boot._process(.4)
		assert_true(boot.net_boot_open)
		assert_false(boot.net_searched, "Looking never rolls or consumes loot")
		assert_gt((car.get_node("BootLid") as Node3D).rotation.length(), 1.0)
		boot.request_search()
		assert_true(boot.net_searched)
		assert_eq(boot.net_active_searchers, 1)
		var contents := boot.net_contents.duplicate()
		_player.yaw += PI
		boot._physics_process(.1)
		assert_true(boot.net_boot_open, "Stash remains open when its viewer looks away")
		boot.request_stop_searching()
		boot._physics_process(.1)
		boot._process(.4)
		assert_false(boot.net_boot_open)
		assert_almost_eq((car.get_node("BootLid") as Node3D).rotation.length(), 0.0, .001)
		assert_eq(boot.net_contents, contents, "Closing does not reroll the shared stash")
		boot.request_search()
		assert_eq(boot.net_active_searchers, 0, "Server rejects search while facing away")
		car.free()


func test_front_distance_and_wall_block_gaze_including_rotated_cars() -> void:
	var car := CAR.instantiate() as Node3D
	car.rotation.y = PI * .5
	add_child_autofree(car)
	var boot := car.get_node("Loot") as CarBoot
	await wait_physics_frames(2)
	_aim(boot, Vector3(0, .95, -3.3))
	assert_false(boot.can_use(_player), "Cannot search through the bonnet")
	_aim(boot, Vector3(0, .95, 6))
	assert_false(boot.can_use(_player), "Out of range")
	_aim(boot, Vector3(0, .95, 3.3))
	assert_true(boot.can_use(_player), "Rotated car boot")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.1, 3, 3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = car.to_global(Vector3(0, 1.5, 2.6))
	add_child_autofree(wall)
	await wait_physics_frames(2)
	assert_false(boot.can_use(_player), "A wall between the player and boot blocks it")


func test_every_authored_garage_car_has_one_searchable_boot() -> void:
	var garage := GARAGE.instantiate() as Node3D
	add_child_autofree(garage)
	var count := 0
	for node: Node in garage.find_children("Loot", "", true, false):
		if node is CarBoot:
			count += 1
			assert_eq(node.get_parent().find_children("Loot", "", true, false).size(), 1)
	assert_gt(count, 5)


func test_remote_crouching_uses_the_replicated_lower_eye_height() -> void:
	var car := CAR.instantiate() as Node3D
	add_child_autofree(car)
	var boot := car.get_node("Loot") as CarBoot
	var crouch := preload("res://features/crouch/feature.tscn").instantiate() as Crouch
	add_child_autofree(crouch)
	crouch.set_physics_process(false)
	_player.set_multiplayer_authority(77)
	crouch.crouched = {77: true}
	var expected := (
		_player.net_position.y
		+ Crouch.EYE_HEIGHT * MovementConfig.UNIT_TO_METERS
		- _player.movement.hull_height_m() * .5
	)
	assert_almost_eq(boot.eye_for_player(_player).y, expected, .001)
	crouch.crouched = {}
	assert_gt(boot.eye_for_player(_player).y, expected + .4)
