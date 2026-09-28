extends GutTest
## Boxing ragdoll behavior of the shooting-gallery dummy (humanoid_target.gd's
## take_punch), independent of features/boxing's input and traces.

const TargetScene := preload("res://features/shooting_gallery/humanoid_target.tscn")

var _target: HumanoidTarget


func before_each() -> void:
	_target = TargetScene.instantiate() as HumanoidTarget
	add_child_autofree(_target)
	await get_tree().physics_frame


func test_daze_wears_off_between_punches() -> void:
	_target.take_punch(2, 0.6, Vector3.FORWARD)
	_target._physics_process(3.0)
	_target.take_punch(2, 0.6, Vector3.FORWARD)
	assert_false(_target.net_ragdoll)


func test_gets_back_up_after_the_ragdoll_time() -> void:
	_target.take_punch(2, 1.0, Vector3.RIGHT)
	assert_true(_target.net_ragdoll)
	_target._physics_process(HumanoidTarget.RAGDOLL_S - 0.1)
	assert_true(_target.net_ragdoll)
	_target._physics_process(0.2)
	assert_false(_target.net_ragdoll)


func test_the_body_lies_flat_toward_the_punch() -> void:
	_target.take_punch(2, 1.0, Vector3.RIGHT)
	for _i: int in 30:
		_target._process(0.05)
	var body := _target.get_node("Body") as Node3D
	var head := body.global_transform * Vector3(0, 1.64, 0)
	var feet := body.global_transform * Vector3.ZERO
	assert_gt(head.x - feet.x, 1.5, "head fell along the punch")
	assert_lt(absf(head.y - feet.y), 0.05, "lying flat")
	assert_gte(feet.y, _target.global_position.y, "not sunk into the floor")


func test_the_collider_lies_down_with_the_body() -> void:
	_target.take_punch(2, 1.0, Vector3.RIGHT)
	for _i: int in 30:
		_target._process(0.05)
	var collider := _target.get_node("Collider") as Node3D
	var center := collider.global_position - _target.global_position
	assert_lt(center.y, 0.5)
	assert_gt(center.x, 0.5)


func test_a_shot_still_kills_a_downed_dummy_and_respawn_stands_it_home() -> void:
	var home := _target.position
	_target.take_punch(2, 1.0, Vector3.RIGHT)
	_target.take_punch(2, 1.0, Vector3.RIGHT)
	for _i: int in 20:
		_target._physics_process(1.0 / 60.0)
	_target.take_hit(2)
	_target._physics_process(HumanoidTarget.RESPAWN_DELAY_S)
	assert_true(_target.net_alive)
	assert_false(_target.net_ragdoll)
	assert_almost_eq(_target.position, home, Vector3.ONE * 0.001)


func test_late_joiners_receive_ragdoll_state_and_position() -> void:
	var config := (_target.get_node("Sync") as MultiplayerSynchronizer).replication_config
	for path: String in [".:net_ragdoll", ".:net_fall_dir", ".:position"]:
		assert_true(config.has_property(NodePath(path)), path)
		assert_true(config.property_get_spawn(NodePath(path)), path)
