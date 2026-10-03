extends GutTest
## View yaw must never turn a seated torso, locally or on replicated puppets.

const COURT := preload("res://features/food_court/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const CAMERA := preload("res://features/third_person/third_person.gd")
const SUITES := preload("res://features/table_games/feature.tscn")

var _court: FoodCourt


func before_each() -> void:
	_court = COURT.instantiate() as FoodCourt
	add_child_autofree(_court)
	_court.set_physics_process(false)


func _avatar(peer: int) -> BlockPlayerModel:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	var model := BlockPlayerModel.new()
	model.player = player
	player.get_node("Body").add_child(model)
	return model


func _occupy(peer: int, index: int) -> void:
	var snapshot := _court.net_seats.duplicate()
	snapshot[index] = peer
	_court.net_seats = snapshot


func _assert_pose(model: BlockPlayerModel, heading: float, offset: float) -> void:
	var body := model.get_parent() as Node3D
	assert_almost_eq(wrapf(body.global_rotation.y - heading, -PI, PI), 0.0, 0.001)
	assert_almost_eq(model._head.rotation.y, offset, 0.001)
	assert_almost_eq(model._head.rotation.x, model.player.net_pitch, 0.001)
	assert_almost_eq(model._torso.rotation.y, 0.0, 0.001)
	var skeleton := model.human.skeleton
	var head := skeleton.find_bone("Head")
	var spine := skeleton.find_bone("Spine")
	var rotation := skeleton.get_bone_global_pose(head).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(head).basis.orthonormalized()
	var posed := rotation * rest.inverse()
	assert_true(posed.is_equal_approx(model._head.basis), "Actual weighted head follows look")
	assert_true(
		skeleton.get_bone_global_pose(spine).basis.orthonormalized().is_equal_approx(
			skeleton.get_bone_global_rest(spine).basis.orthonormalized()
		),
		"Spine stays fixed"
	)


func test_local_first_and_third_person_keep_body_fixed_and_camera_free() -> void:
	var model := _avatar(1)
	var player := model.player
	var camera_feature := CAMERA.new()
	add_child_autofree(camera_feature)
	_occupy(1, 0)
	_court._update_local_pin(0.0)
	var heading := _court.sit_yaw(0)
	for third_person: bool in [false, true]:
		camera_feature.enabled = third_person
		player.yaw = heading + 0.7
		player.pitch = -0.3
		_court._pin(player, _court.sit_position(0))
		player._process(1.0)
		camera_feature._process(1.0)
		model._process(1.0)
		_assert_pose(model, heading, 0.7)
		var camera := player.get_node("Camera") as Camera3D
		assert_almost_eq(camera.global_rotation.y, player.yaw, 0.001)
		assert_almost_eq(camera.global_rotation.x, player.pitch, 0.001)
	_court._reset_session(Network.Mode.OFFLINE)
	player._process(1.0)
	camera_feature._process(1.0)
	model._process(1.0)
	assert_false(model.seated)
	assert_true(is_nan(_court.seated_yaw(1)))
	assert_almost_eq(model._head.rotation.y, 0.0, 0.001)
	assert_almost_eq((model.get_parent() as Node3D).rotation.y, player.yaw, 0.001)


func test_gaming_suite_provider_preserves_pose_and_cross_system_exclusivity() -> void:
	var suites := SUITES.instantiate()
	add_child_autofree(suites)
	var seats := suites.get_node("Room/Poker/Seats") as CrownTableSeating
	seats.set_physics_process(false)
	assert_eq(get_tree().get_first_node_in_group(&"seating"), _court)
	for peer: int in [1, 2]:
		var model := _avatar(peer)
		var player := model.player
		var snapshot := seats.net_seats.duplicate()
		snapshot[0] = peer
		seats.net_seats = snapshot
		var heading := seats.sit_yaw(0)
		player.yaw = heading + 0.7
		player.net_yaw = player.yaw
		player.pitch = 0.2
		player.net_pitch = player.pitch
		player._process(1.0)
		model._process(1.0)
		assert_true(model.seated, "Find the occupied provider after the empty food court")
		_assert_pose(model, heading, 0.7)
		player.net_position = _court.seats[0].global_position
		assert_false(_court._may_sit(peer, {"seat": 0}), "Cannot claim a booth while at a table")
		seats._free_peer(peer)
		assert_true(_court._may_sit(peer, {"seat": 0}))
		_occupy(peer, 0)
		player.net_position = seats.seats[0].global_position
		assert_false(seats._may_sit(peer, {"seat": 0}), "Cannot claim a table while in a booth")
		_court._free_peer(peer)
		assert_true(seats._may_sit(peer, {"seat": 0}))
		player._process(1.0)
		model._process(1.0)
		assert_false(model.seated)
		assert_almost_eq(model._head.rotation.y, 0.0, 0.001)


func test_remote_snapshot_locks_body_across_wrap_and_restores_on_stand() -> void:
	var model := _avatar(2)
	var player := model.player
	# Opposite bench faces PI: exercise world-space angle wrapping and late snapshot.
	_occupy(2, 2)
	var heading := _court.sit_yaw(2)
	for offset: float in [0.7, -0.8]:
		player.net_yaw = wrapf(heading + offset, -PI, PI)
		player.net_pitch = 0.2
		player._process(1.0)
		model._process(1.0)
		_assert_pose(model, heading, offset)
	_court._free_peer(2)
	player._process(1.0)
	model._process(1.0)
	assert_false(model.seated)
	assert_almost_eq(model._head.rotation.y, 0.0, 0.001)
	assert_almost_eq(
		wrapf((model.get_parent() as Node3D).rotation.y - player.net_yaw, -PI, PI), 0.0, 0.001
	)
