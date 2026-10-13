extends GutTest
## In the live game (main.tscn): guard posts stand on clear promenade floor out of
## everyone's way, and the grid built from the hall's real collision routes guards
## from every post to the pit, the promenade and the Crown metro doors.

const MAIN := preload("res://main.tscn")
## Crown spawn square (features/crown_spawn) and the metro cab behind its threshold.
const SPAWN := Rect2(-3, -19, 6, 6)
const METRO_CAB := Rect2(-13.6, 19.8, 3.2, 3.2)
## Places offenders stand: pit aisles, slot rows, promenade corners, the spawn.
const SPOTS: Array[Vector3] = [
	Vector3(0.5, -1.25, -6),
	Vector3(12, -1.25, 10.5),
	Vector3(-12, -1.25, 7),
	Vector3(8.5, -1.25, -11),
	Vector3(-20, 0, -16),
	Vector3(20, 0, 16),
	Vector3(-20, 0, 12),
	Vector3(0, 0, -16),
]

var _game: Node
var _security: CasinoSecurity


func before_all() -> void:
	_game = MAIN.instantiate()
	add_child(_game)
	await wait_physics_frames(4)
	_security = get_tree().get_first_node_in_group(&"casino_security") as CasinoSecurity
	_security.build_grid_now()


func after_all() -> void:
	_game.free()


func test_the_live_game_loads_three_guards_at_their_posts() -> void:
	assert_not_null(_security)
	assert_eq(_security.guards().size(), 3)
	assert_true(_security.grid.is_ready())
	for guard: CasinoGuard in _security.guards():
		assert_eq(guard.position, guard.post)


func test_posts_are_clear_promenade_floor_inside_the_safe_crown() -> void:
	var space := _security.get_world_3d().direct_space_state
	for guard: CasinoGuard in _security.guards():
		var post := guard.post
		assert_true(_security.grid.is_walkable(post), "%s on walkable floor" % guard.name)
		assert_almost_eq(_security.grid.floor_at(post, NAN), 0.0, 0.02, "%s floor" % guard.name)
		assert_true(SecurityRules.in_jurisdiction(post + Vector3.UP), guard.name)
		assert_true(SafeZone.covers(get_tree(), post + Vector3.UP), guard.name)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 2.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = 1
		query.transform = Transform3D(Basis.IDENTITY, post + Vector3.UP * 1.05)
		var hits := space.intersect_shape(query, 4)
		var names: Array[String] = []
		for hit: Dictionary in hits:
			if not hit["collider"] is Player:
				names.append(str((hit["collider"] as Node).get_path()))
		assert_eq(names, [] as Array[String], "%s body clear of geometry" % guard.name)


func test_posts_keep_out_of_the_spawn_doorways_and_interactions() -> void:
	for guard: CasinoGuard in _security.guards():
		var at := Vector2(guard.post.x, guard.post.z)
		assert_false(SPAWN.grow(0.6).has_point(at), "%s clear of the spawn square" % guard.name)
		assert_false(METRO_CAB.grow(1.0).has_point(at), "%s clear of the metro doors" % guard.name)
		for node: Node in get_tree().get_nodes_in_group(&"interactables"):
			var thing := node as Node3D
			if (
				thing == null
				or thing is CasinoGuard
				or absf(thing.global_position.y - guard.post.y) > 2.5
			):
				continue
			var gap := Vector2(thing.global_position.x, thing.global_position.z).distance_to(at)
			assert_gt(gap, 1.5, "%s clear of %s" % [guard.name, thing.get_path()])
		for other: CasinoGuard in _security.guards():
			if other != guard:
				assert_gt(guard.post.distance_to(other.post), 15.0, "posts spread over the hall")


func test_every_post_reaches_the_pit_the_promenade_and_the_metro_doors() -> void:
	var grid := _security.grid
	var stand := _security.cab_marker() * SecurityRules.THROW_STAND
	assert_true(grid.is_walkable(stand), "the throw stand is clear floor")
	for spot: Vector3 in SPOTS:
		assert_true(grid.is_walkable(spot), "%s is open floor" % spot)
	for guard: CasinoGuard in _security.guards():
		for spot: Vector3 in SPOTS:
			var route := grid.route(
				guard.post, spot, SecurityRules.APPROACH, SecurityRules.GRAB_DROP
			)
			assert_false(route.is_empty(), "%s reaches %s" % [guard.name, spot])
			if not route.is_empty():
				var end := route[route.size() - 1]
				assert_true(
					SecurityRules.can_grab(end, spot), "%s ends beside %s" % [guard.name, spot]
				)
				assert_true(_legs_clear(grid, guard.post, route), "%s to %s" % [guard.name, spot])
		var to_doors := grid.route(guard.post, stand, 0.5, 0.6)
		assert_false(to_doors.is_empty(), "%s reaches the metro doors" % guard.name)
		var back := grid.route(stand, guard.post, 0.5, 0.6)
		assert_false(back.is_empty(), "%s walks back to its post" % guard.name)


func test_the_pit_is_reached_by_its_ramps_not_over_the_retaining_wall() -> void:
	var grid := _security.grid
	var route := grid.route(Vector3(19.5, 0, 3.5), Vector3(12, -1.25, 0), 0.75, 1.6)
	assert_false(route.is_empty())
	var previous := Vector3(19.5, 0, 3.5)
	for point: Vector3 in route:
		var drop := previous.y - point.y
		var run := Vector2(point.x - previous.x, point.z - previous.z).length()
		assert_true(
			drop < 0.31 or run > drop * 3.0, "no straight drop %s -> %s" % [previous, point]
		)
		previous = point


## True when each straight leg of `route` crosses only joined walkable cells.
func _legs_clear(grid: SecurityGrid, from: Vector3, route: Array[Vector3]) -> bool:
	var last := grid.nearest(from, 1.5, 1.0, 1.0)
	for point: Vector3 in route:
		var index := grid.index_at(point)
		if index < 0 or not grid.clear_leg(last, index):
			return false
		last = index
	return true
