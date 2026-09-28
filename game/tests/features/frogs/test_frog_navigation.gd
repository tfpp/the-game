extends GutTest

const FROG_SCENE := preload("res://features/frogs/frog.tscn")

var _world: Node3D
var _navigation: FrogNavigation


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_navigation = FrogNavigation.new()
	_navigation.configure(1.0, RID())
	_box(Vector3(0, -0.5, 0), Vector3(20, 1, 20))
	await wait_physics_frames(2)


func test_clear_floor_allows_hops() -> void:
	var hop := _navigation.find_hop(_space(), Vector3.ZERO, Vector3.FORWARD, 2.0, 0.6)
	assert_false(hop.is_empty())
	assert_almost_eq((hop["target"] as Vector3).z, -2.0, 0.01)


func test_wall_forces_a_different_route() -> void:
	_box(Vector3(0, 1.5, -1.0), Vector3(4, 3, 0.2))
	await wait_physics_frames(2)
	assert_false(_navigation.arc_is_clear(_space(), Vector3.ZERO, Vector3(0, 0, -2), 0.6))
	var hop := _navigation.find_hop(_space(), Vector3.ZERO, Vector3.FORWARD, 2.0, 0.6)
	assert_false(hop.is_empty(), "A frog can turn along a wall")
	assert_gt(absf((hop["target"] as Vector3).x), 0.5)


func test_escape_along_wall_never_moves_toward_player() -> void:
	_box(Vector3(0, 1.5, -1.0), Vector3(4, 3, 0.2))
	await wait_physics_frames(2)
	var threat := Vector3(0, 0, 1)
	var hop := _navigation.find_hop(_space(), Vector3.ZERO, Vector3.FORWARD, 2.0, 0.6, threat)
	assert_false(hop.is_empty())
	assert_gt((hop["target"] as Vector3).distance_to(threat), 1.0)


func test_unsupported_ground_and_edges_are_rejected() -> void:
	assert_true(_navigation.supported_ground(_space(), Vector3(11, 0, 0)).is_empty())
	assert_true(_navigation.supported_ground(_space(), Vector3(9.9, 0, 0)).is_empty())


func test_low_ceiling_blocks_the_whole_arc() -> void:
	_box(Vector3(0, 1.3, -1), Vector3(5, 0.2, 5))
	await wait_physics_frames(2)
	assert_false(_navigation.arc_is_clear(_space(), Vector3.ZERO, Vector3(0, 0, -2), 0.6))


func test_low_step_can_be_landed_on_but_tall_wall_cannot() -> void:
	_box(Vector3(0, 0.15, -2), Vector3(2, 0.3, 2))
	await wait_physics_frames(2)
	var ground := _navigation.supported_ground(_space(), Vector3(0, 0, -2))
	assert_false(ground.is_empty())
	assert_almost_eq((ground["position"] as Vector3).y, 0.3, 0.01)
	assert_true(_navigation.arc_is_clear(_space(), Vector3.ZERO, ground["position"], 0.6))


func test_live_frog_flees_player_and_keeps_its_profile() -> void:
	var frog := FROG_SCENE.instantiate() as Frog
	frog.body_size = 0.65
	frog.jump_distance = 0.85
	frog.rest_time = 20.0
	_world.add_child(frog)
	var player := Node3D.new()
	_world.add_child(player)
	player.position = Vector3(0, 0.9, 1.2)
	player.add_to_group(&"players")
	await wait_physics_frames(85)
	assert_lt(frog.position.z, -0.4, "Nearby players interrupt the long idle and cause escape hops")
	assert_almost_eq(frog.body_size, 0.65, 0.001)
	assert_true(frog.net_position.is_equal_approx(frog.position))
	assert_gt(frog.position.y, -0.1, "Frog stays on or above the ground")


func test_player_above_frog_does_not_trigger_escape() -> void:
	var frog := FROG_SCENE.instantiate() as Frog
	_world.add_child(frog)
	frog.set_physics_process(false)
	var player := Node3D.new()
	_world.add_child(player)
	player.position = Vector3(0, 6, 0)
	player.add_to_group(&"players")
	frog._sense_players()
	assert_false(frog._fleeing)
	player.position = Vector3(1, 0.9, 0)
	frog._sense_players()
	assert_true(frog._fleeing)
	player.position = Vector3(8, 0.9, 0)
	frog._sense_players()
	assert_false(frog._fleeing, "Return to wandering once the player leaves")


func test_obstacle_entering_active_hop_stops_frog() -> void:
	var frog := FROG_SCENE.instantiate() as Frog
	_world.add_child(frog)
	frog.set_physics_process(false)
	frog._settling = false
	frog._hopping = true
	frog._hop_from = Vector3.ZERO
	frog._hop_to = Vector3(0, 0, -3)
	frog._hop_duration = 0.5
	frog._hop_height = 0.6
	# Insert a blocker after the hop was chosen.
	_box(Vector3(0, 1.5, -1.5), Vector3(8, 3, 0.2))
	await wait_physics_frames(2)
	for frame: int in 32:
		frog._physics_process(1.0 / 64.0)
		await wait_physics_frames(1)
	assert_gt(frog.position.z, -1.0, "The live collision body stops before the wall")
	assert_false(frog._hopping)


func test_spawn_profiles_and_materials_are_independent() -> void:
	var feature := preload("res://features/frogs/feature.tscn").instantiate()
	autofree(feature)
	var frogs: Array[Frog] = []
	for index: int in 6:
		var profile := FrogHop.profile_for_index(index)
		var frog := (
			feature._spawn_frog(
				{
					"index": index,
					"position": Vector3(index, 0, 0),
					"color": FrogHop.color_for_index(index),
					"profile": profile
				}
			)
			as Frog
		)
		_world.add_child(frog)
		frog.set_physics_process(false)
		frogs.append(frog)
		assert_eq(frog.body_size, profile["size"])
		assert_eq(frog.jump_distance, profile["distance"])
		var material := (
			(frog.get_node("Body/Torso") as MeshInstance3D).material_override as StandardMaterial3D
		)
		assert_eq(material.albedo_color, FrogHop.color_for_index(index))
	var first := (frogs[0].get_node("Body/Torso") as MeshInstance3D).material_override
	var second := (frogs[1].get_node("Body/Torso") as MeshInstance3D).material_override
	assert_ne(first, second, "Frogs must not share mutable skin materials")


func _space() -> PhysicsDirectSpaceState3D:
	return _world.get_world_3d().direct_space_state


func _box(at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collider.shape = shape
	body.add_child(collider)
	body.position = at
	_world.add_child(body)


func test_moving_platform_is_not_a_supported_landing() -> void:
	var platform := AnimatableBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 0.4, 3)
	collider.shape = shape
	platform.add_child(collider)
	platform.position = Vector3(0, 0.2, -2)
	_world.add_child(platform)
	await wait_physics_frames(2)
	assert_true(
		_navigation.supported_ground(_space(), Vector3(0, 0, -2)).is_empty(),
		"AnimatableBody3D inherits StaticBody3D, but its surface can move before a frog lands"
	)


func test_first_remote_snapshot_snaps_instead_of_sliding_from_original_spawn() -> void:
	var frog := FROG_SCENE.instantiate() as Frog
	_world.add_child(frog)
	frog.set_physics_process(false)
	frog.net_position = Vector3(15, 2, 20)
	frog.net_yaw = 1.2
	frog._render_remote(0.25)
	assert_eq(frog.position, frog.net_position)
	assert_almost_eq(frog.get_node("Body").rotation.y, frog.net_yaw, 0.001)
	frog.net_position.x = 19.0
	frog._render_remote(0.25)
	assert_almost_eq(frog.position.x, 16.0, 0.001, "Later updates still interpolate")
