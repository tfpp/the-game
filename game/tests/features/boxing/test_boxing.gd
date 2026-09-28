extends GutTest
## Server path of features/boxing: who can punch, jab vs power punch, and what a
## punch does to the shooting-gallery dummy, players and other killables. Runs
## single-process, so peer 1 is the server and the puncher.

const BoxingScene := preload("res://features/boxing/feature.tscn")
const TargetScene := preload("res://features/shooting_gallery/humanoid_target.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")

var _boxing: Boxing
var _player: Player
var _hand: Hand
var _target: HumanoidTarget


class _KillableStub:
	extends StaticBody3D
	var hits: Array = []

	func _init() -> void:
		add_to_group(&"killable")
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 2.0, 1.0)
		collider.shape = shape
		add_child(collider)

	func take_hit(attacker_peer: int) -> void:
		hits.append(attacker_peer)


func before_each() -> void:
	_boxing = BoxingScene.instantiate() as Boxing
	add_child_autofree(_boxing)
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_yaw = 0.0
	_player.net_pitch = 0.0
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_target = TargetScene.instantiate() as HumanoidTarget
	add_child_autofree(_target)
	# Standing just ahead of the player (forward is -Z), inside punching reach.
	_target.global_position = _player.net_position + Vector3(0, -0.9, -1.0)
	await wait_physics_frames(2)


func _ready_to_punch() -> void:
	_boxing._ready_at_ms.clear()


func test_a_jab_lands_but_does_not_knock_down() -> void:
	assert_eq(_boxing.punch(1, 0.1), _target)
	assert_false(_target.net_ragdoll)
	assert_true(_target.net_alive, "punches never gib the dummy")


func test_a_full_power_punch_ragdolls_the_dummy() -> void:
	_boxing.punch(1, BoxingMath.FULL_CHARGE_S)
	assert_true(_target.net_ragdoll)
	assert_almost_eq(_target.net_fall_dir, Vector3(0, 0, -1), Vector3.ONE * 0.001)


func test_enough_jabs_in_a_row_knock_it_down() -> void:
	for _i: int in 3:
		_ready_to_punch()
		_boxing.punch(1, 0.0)
	assert_false(_target.net_ragdoll)
	_ready_to_punch()
	_boxing.punch(1, 0.0)
	assert_true(_target.net_ragdoll)


func test_cooldown_blocks_rapid_punches() -> void:
	assert_not_null(_boxing.punch(1, 0.0))
	assert_null(_boxing.punch(1, 0.0))


func test_holding_a_weapon_blocks_punching() -> void:
	_hand.net_item_id = "pistol"
	assert_null(_boxing.punch(1, BoxingMath.FULL_CHARGE_S))
	assert_false(_target.net_ragdoll)


func test_punching_without_a_player_does_nothing() -> void:
	assert_null(_boxing.punch(7, BoxingMath.FULL_CHARGE_S))
	assert_false(_target.net_ragdoll)


func test_a_miss_out_of_reach_does_nothing() -> void:
	_target.global_position += Vector3(0, 0, -5)
	await wait_physics_frames(2)
	assert_null(_boxing.punch(1, BoxingMath.FULL_CHARGE_S))
	assert_false(_target.net_ragdoll)


func test_the_server_times_the_hold_between_wind_up_and_release() -> void:
	_boxing.request_wind_up()
	_boxing._wind_up_ms[1] -= int(BoxingMath.FULL_CHARGE_S * 1000.0)
	_boxing.request_punch()
	assert_true(_target.net_ragdoll)
	assert_false(_boxing._wind_up_ms.has(1))


func test_a_power_punch_knocks_a_downed_dummy_a_short_way() -> void:
	_boxing.punch(1, BoxingMath.FULL_CHARGE_S)
	var start := _target.global_position
	_ready_to_punch()
	# Look down at the dummy lying on the floor.
	_player.net_pitch = -0.6
	for _i: int in 30:
		_target._process(0.05)
	await wait_physics_frames(2)
	assert_eq(_boxing.punch(1, BoxingMath.FULL_CHARGE_S), _target)
	for _i: int in 120:
		_target._physics_process(1.0 / 60.0)
	var moved := _target.global_position - start
	assert_lt(moved.z, -1.5, "knocked away from the puncher")
	assert_lt(moved.length(), 4.0, "only a small distance")
	assert_almost_eq(moved.y, 0.0, 0.001)


func test_a_jab_on_a_downed_dummy_does_not_move_it() -> void:
	_boxing.punch(1, BoxingMath.FULL_CHARGE_S)
	var start := _target.global_position
	_ready_to_punch()
	_boxing.punch(1, 0.0)
	for _i: int in 30:
		_target._physics_process(1.0 / 60.0)
	assert_almost_eq(_target.global_position, start, Vector3.ONE * 0.001)


func test_a_power_punch_on_another_killable_is_a_hit_but_a_jab_is_not() -> void:
	_target.global_position += Vector3(0, 0, 20)
	var stub := _KillableStub.new()
	add_child_autofree(stub)
	stub.global_position = _player.net_position + Vector3(0, 0, -1.2)
	await wait_physics_frames(2)
	_boxing.punch(1, 0.0)
	assert_eq(stub.hits, [])
	_ready_to_punch()
	_boxing.punch(1, BoxingMath.FULL_CHARGE_S)
	assert_eq(stub.hits, [1])


func test_disconnect_forgets_the_peer() -> void:
	_boxing.request_wind_up()
	_boxing.punch(1, 0.0)
	_boxing._forget_peer(1)
	assert_false(_boxing._wind_up_ms.has(1))
	assert_false(_boxing._ready_at_ms.has(1))
