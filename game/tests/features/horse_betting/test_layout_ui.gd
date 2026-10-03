extends GutTest

const SCENE := preload("res://features/horse_betting/feature.tscn")
const CASINO := preload("res://features/casino_hub/casino_gridmap.tscn")


func test_terminal_has_floor_and_keeps_promenade_route_clear() -> void:
	var level := CASINO.instantiate() as Node3D
	add_child_autofree(level)
	var race := SCENE.instantiate() as HorseBetting
	add_child_autofree(race)
	await wait_physics_frames(3)
	assert_eq(race.position, Vector3(23.3, 0, -5))
	assert_almost_eq(race.global_basis.z, Vector3.LEFT, Vector3.ONE * 0.001)
	var destination := race.get_node("HorseRacing") as GpsDestination
	assert_almost_eq(destination.global_position, Vector3(20.3, 0, -5), Vector3.ONE * 0.001)
	var query := PhysicsRayQueryParameters3D.create(Vector3(20.3, 2, -5), Vector3(20.3, -2, -5), 1)
	var floor := race.get_world_3d().direct_space_state.intersect_ray(query)
	assert_almost_eq((floor["position"] as Vector3).y, 0.0, 0.01)
	# Walk along the east promenade between the pit rail and the terminal.
	for z: float in [-8.0, -6.0, -5.0, -4.0, -2.0]:
		query = PhysicsRayQueryParameters3D.create(Vector3(18, 1, z), Vector3(21, 1, z), 1)
		assert_true(race.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	var monitor := race.get_node("Monitor") as StaticBody3D
	var shape := monitor.get_node("Collider") as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size * monitor.scale
	assert_almost_eq(size.x, 6.0, 0.001, "six metre display")
	assert_almost_eq(monitor.position.y, 1.4, 0.001, "mounted above player route")
	assert_eq((race.get_node("Display/Broadcast") as SubViewport).size, Vector2i(128, 128))


func test_menu_blocks_gameplay_supports_phone_controls_and_closes() -> void:
	var race := SCENE.instantiate() as HorseBetting
	add_child_autofree(race)
	var menu := HorseBettingMenu.new()
	menu.race = race
	add_child_autofree(menu)
	assert_true(menu.is_in_group(&"modal_ui"))
	assert_eq(menu._horse.item_count, 4)
	assert_eq(menu._stake.item_count, 3)
	assert_gte(menu._place.custom_minimum_size.y, 48.0)
	assert_false(menu._place.disabled)
	var next := race.state.duplicate(true)
	next["phase"] = "racing"
	race.state = next
	menu._process(0.0)
	assert_true(menu._place.disabled)
	menu.close()
	assert_false(menu.is_in_group(&"modal_ui"))
	Controls.pause()
