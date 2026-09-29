extends GutTest
## Wall holes, outings, killing and respawning for features/gnomes/gnome_train.gd.

const Feature := preload("res://features/gnomes/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const WALL := 34.0
var _feature: Node3D


func before_each() -> void:
	_feature = Feature.instantiate()
	add_child_autofree(_feature)


func _train(side: String) -> Node3D:
	return _feature.get_node("Train" + side) as Node3D


func _run(train: Node3D, seconds: float) -> void:
	var step := 1.0 / 30.0
	var t := 0.0
	while t < seconds:
		train._physics_process(step)
		train._process(step)
		t += step


func test_every_hole_is_on_an_outer_wall_facing_into_the_room() -> void:
	for side: String in ["North", "South", "East", "West"]:
		var train := _train(side)
		for number in 4:
			var hole := train.get_node("Hole%d" % number) as Node3D
			var pos := hole.global_position
			assert_almost_eq(maxf(absf(pos.x), absf(pos.z)), WALL, 0.01, hole.name)
			assert_lt(pos.y, 0.5, "doors sit at floor level")
			var normal: Vector3 = train.hole_normal(number)
			var inward := (
				Vector3(-signf(pos.x), 0, 0)
				if absf(pos.x) > absf(pos.z)
				else Vector3(0, 0, -signf(pos.z))
			)
			assert_gt(normal.dot(inward), 0.99, "faces into the room")


func test_gnomes_stay_hidden_until_they_come_out_of_a_hole() -> void:
	var train := _train("North")
	for gnome: Gnome in train._gnomes:
		assert_false(gnome.is_shown())
	train.start_outing()
	_run(train, 0.5)
	assert_true((train._gnomes[0] as Gnome).is_shown(), "leader is out")


func test_each_gnome_wanders_through_several_stops() -> void:
	var train := _train("South")
	train.start_outing()
	for i: int in train._gnomes.size():
		var route: PackedVector3Array = train._routes[i]
		assert_gte(route.size(), GnomeMath.WANDER_STOPS_MIN + 2)
		assert_eq(route[route.size() - 1], train._hole_positions[train._to_hole])


func test_killed_gnome_is_hidden_not_freed_and_respawns_next_outing() -> void:
	var train := _train("East")
	train.start_outing()
	_run(train, 0.5)
	var gnome := train._gnomes[0] as Gnome
	assert_true(gnome.is_shown())
	assert_true(gnome.is_in_group(&"killable"))
	gnome.take_hit(1)
	train._process(0.0)
	assert_false(gnome.is_shown())
	assert_true((gnome.get_node("Collider") as CollisionShape3D).disabled)
	assert_true(is_instance_valid(gnome) and gnome.get_parent() == train, "kept in the scene")
	_run(train, 0.2)
	assert_false(gnome.is_shown(), "stays dead for the rest of the outing")
	train.start_outing()
	_run(train, 0.5)
	assert_true(gnome.is_shown(), "respawns when the burrow comes out again")


func test_gnomes_return_to_a_hole_and_rest() -> void:
	var train := _train("West")
	train.start_outing()
	var target: int = train._to_hole
	var step := 1.0 / 30.0
	var t := 0.0
	while not train.is_resting() and t < 120.0:
		train._physics_process(step)
		train._process(step)
		t += step
	assert_true(train.is_resting(), "every gnome went into the target hole")
	assert_eq(train._from_hole, target, "next outing starts from that hole")
	for gnome: Gnome in train._gnomes:
		assert_false(gnome.is_shown())


func test_gnomes_sidestep_a_player_in_their_way() -> void:
	var train := _train("North")
	train.start_outing()
	_run(train, 1.0)
	var free_pos: Vector3 = train.net_positions[0]
	var route: PackedVector3Array = train._routes[0]
	var distance := GnomeMath.route_distance(train._elapsed, train._delays[0], train._speeds[0])
	var dir := GnomeMath.direction_on_path(route, distance)
	var player := PlayerScene.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = train.to_global(free_pos + dir.cross(Vector3.UP) * 0.5)
	train._sense_timer = 0.0
	_run(train, 0.3)
	var pushed: Vector3 = train._avoid[0]
	assert_gt(pushed.length(), 0.05, "moves aside")
	assert_lt(pushed.dot(dir.cross(Vector3.UP)), 0.0, "away from the player")
