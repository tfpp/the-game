extends GutTest

const MALL := preload("res://features/strip_mall/feature.tscn")
const FROGS := preload("res://features/frogs/feature.tscn")

var _mall: Node3D
var _room: StreamedRoom
var _display: Node3D


func before_each() -> void:
	_mall = MALL.instantiate() as Node3D
	add_child_autofree(_mall)
	_room = _mall.get_node("Room") as StreamedRoom
	_room.set_physics_process(false)
	_display = _room.get_node("FrogDisplay") as Node3D


func test_fourth_bay_floor_and_approach_are_grounded_and_clear() -> void:
	_room.load_room(60000)
	await wait_physics_frames(3)
	var space := _room.get_world_3d().direct_space_state
	for local: Vector3 in [Vector3(26, 1, 38), Vector3(26, 1, 42.5), Vector3(29.5, 1, 43.5)]:
		var point := _room.to_global(local)
		var ray := PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 3, 0), 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, .01)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.transform.origin = _room.to_global(Vector3(26, .95, 36))
	query.motion = Vector3(0, 0, 7.5)
	assert_almost_eq(space.cast_motion(query)[0], 1.0, .001)
	query.transform.origin = _room.to_global(Vector3(26, .95, 43.5))
	query.motion = Vector3(3.5, 0, 0)
	assert_almost_eq(space.cast_motion(query)[0], 1.0, .001)
	assert_true(_room.contains((_room.get_node("ZabkaDestination") as Node3D).global_position))


func test_green_white_polish_wordmark_faces_plaza_and_has_real_glyph() -> void:
	_room.load_room()
	var sign := _room.get_node("Content/Zabka/Wordmark") as SignBoard
	assert_eq(sign.text, "żabka")
	assert_lt((sign.global_basis * Vector3.BACK).x, -.99)
	var backing := sign.get_node("Board/Backing") as MeshInstance3D
	var color := (backing.material_override as StandardMaterial3D).albedo_color
	assert_gt(color.g, color.r * 2)
	assert_eq(sign.neon_color, Color.WHITE)
	assert_ne(SignLetterAtlas.index_of("ż"), SignLetterAtlas.index_of("?"))
	assert_eq(SignLetterAtlas.index_of("ż"), SignLetterAtlas.index_of("Ż"))


func test_original_colony_defaults_and_authored_spawn_profiles() -> void:
	var original := FROGS.instantiate()
	add_child_autofree(original)
	assert_true(original.spawn_points.is_empty())
	assert_eq(original.profile_scale, 1.0)
	original._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(original.get_node("Pond").get_child_count(), 12)
	for frog: Frog in original.get_node("Pond").get_children():
		frog.set_physics_process(false)
		assert_lte(frog.position.length(), FrogHop.HOP_RADIUS)
	var first := original.get_node("Pond/Frog0") as Frog
	assert_eq(first.body_size, FrogHop.profile_for_index(0)["size"])
	var colony := _display.get_node("Colony")
	colony._on_mode_changed(Network.Mode.OFFLINE)
	var pond := colony.get_node("Pond")
	assert_eq(pond.get_child_count(), 3)
	for index: int in 3:
		var frog := pond.get_child(index) as Frog
		frog.set_physics_process(false)
		assert_eq(frog.position, colony.spawn_points[index])
		assert_eq(frog.net_position, frog.position)
		assert_eq(frog.body_color, FrogHop.color_for_index(index))
		assert_almost_eq(frog.body_size, float(FrogHop.profile_for_index(index)["size"]) * .5, .001)
		assert_eq(frog.get_multiplayer_authority(), 1)
		var sync := frog.get_node("Sync") as MultiplayerSynchronizer
		for property: NodePath in sync.replication_config.get_properties():
			assert_true(sync.replication_config.property_get_spawn(property))


func test_frogs_survive_room_unload_respawn_at_home_and_session_reset() -> void:
	var colony := _display.get_node("Colony")
	colony._on_mode_changed(Network.Mode.OFFLINE)
	var pond := colony.get_node("Pond")
	var frog := pond.get_child(0) as Frog
	frog.set_physics_process(false)
	var home := frog.global_position
	_room.load_room()
	_room.unload_room()
	assert_true(is_instance_valid(frog))
	assert_eq(pond.get_child_count(), 3)
	await wait_physics_frames(2)
	var ray := PhysicsRayQueryParameters3D.create(home, home - Vector3(0, .5, 0), 1)
	var hit := _room.get_world_3d().direct_space_state.intersect_ray(ray)
	assert_false(hit.is_empty(), "Habitat floor exists without streamed geometry")
	frog.take_hit(1)
	assert_false(frog.net_alive)
	frog._physics_process(Frog.RESPAWN_DELAY_S + .1)
	assert_true(frog.net_alive)
	assert_eq(frog.global_position, home)
	colony._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(pond.get_child_count(), 3, "Session reset recreates exactly one colony")
	await wait_physics_frames(2)


func test_live_frogs_remain_in_closed_habitat_without_streamed_floor() -> void:
	var colony := _display.get_node("Colony")
	colony._on_mode_changed(Network.Mode.OFFLINE)
	await wait_physics_frames(640)
	for frog: Frog in colony.get_node("Pond").get_children():
		var point := _display.to_local(frog.global_position)
		assert_between(point.x, -1.5, 1.5)
		assert_between(point.z, -1.25, 1.25)
		assert_between(point.y, .75, 2.3)
		assert_false(frog._settling, "Server frogs find the persistent display floor")
