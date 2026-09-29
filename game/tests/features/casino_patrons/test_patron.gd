extends GutTest
## Server path of a casino patron: walking its route, punches, ragdoll, getting
## back up, being shot and respawning. Runs single-process, so peer 1 is the server.

const PatronScene := preload("res://features/casino_patrons/patron.tscn")

var _patron: CasinoPatron


func before_each() -> void:
	_patron = PatronScene.instantiate() as CasinoPatron
	_patron.route = [Vector3(0, 0, 0), Vector3(0, 0, -10)] as Array[Vector3]
	_patron.look = 2
	add_child_autofree(_patron)
	await get_tree().physics_frame
	_patron.set_physics_process(false)


func _step(seconds: float) -> void:
	var dt := 1.0 / 30.0
	for _i: int in int(seconds / dt):
		_patron._physics_process(dt)
		_patron._process(dt)


func test_walks_toward_the_next_waypoint_facing_forward() -> void:
	_step(1.0)
	assert_lt(_patron.position.z, -1.0)
	assert_almost_eq(_patron.net_position.z, _patron.position.z, 0.001)
	var forward := Basis(Vector3.UP, _patron.net_yaw) * Vector3.FORWARD
	assert_almost_eq(forward.z, -1.0, 0.01)


func test_waits_for_a_player_standing_in_the_way() -> void:
	var blocker := Node3D.new()
	blocker.add_to_group(&"players")
	add_child_autofree(blocker)
	blocker.global_position = _patron.position + Vector3(0, 0, -0.5)
	var start := _patron.position
	_step(1.0)
	assert_almost_eq(_patron.position.distance_to(start), 0.0, 0.001)
	_step(PatronMath.MAX_WAIT_S)
	assert_lt(_patron.position.z, start.z - 0.3, "squeezes past a player who stays put")


func test_a_jab_staggers_but_does_not_knock_down() -> void:
	_patron.take_punch(2, 0.25, Vector3.BACK)
	assert_false(_patron.net_ragdoll)
	assert_almost_eq((Basis(Vector3.UP, _patron.net_yaw) * Vector3.FORWARD).z, -1.0, 0.01)
	_step(0.3)
	assert_gt(_patron.position.z, 0.1, "shoved back")


func test_a_power_punch_ragdolls_and_they_walk_back_after_getting_up() -> void:
	_patron.take_punch(2, 1.0, Vector3.RIGHT)
	assert_true(_patron.net_ragdoll)
	_step(1.0)
	assert_gt(_patron.position.x, 0.3, "knocked sideways")
	var body := _patron.get_node("Body") as Node3D
	var head := body.get_node("Hips/Torso/Head") as Node3D
	assert_lt(head.global_position.y - _patron.global_position.y, 0.6, "lying down")
	assert_gt(head.global_position.x, _patron.global_position.x + 1.0, "fell along the punch")
	_step(HumanoidTarget.RAGDOLL_S + CasinoPatron.STAGGER_S + 1.5)
	assert_false(_patron.net_ragdoll)
	assert_gt(head.global_position.y - _patron.global_position.y, 1.4, "standing again")
	_step(2.0)
	assert_almost_eq(_patron.position.x, 0.0, 0.1, "back on the route")


func test_a_shot_gibs_them_and_they_respawn_on_their_route() -> void:
	_step(1.0)
	_patron.take_hit(2)
	assert_false(_patron.net_alive)
	_patron.take_punch(2, 1.0, Vector3.RIGHT)
	assert_false(_patron.net_ragdoll, "the dead can't be punched")
	_step(CasinoPatron.RESPAWN_DELAY_S + 0.1)
	assert_true(_patron.net_alive)
	assert_true(_patron.position.distance_to(Vector3.ZERO) < 0.2)
