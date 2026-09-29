extends GutTest
## Tests the Bird scene and server-authoritative state machine.

const BirdScene := preload("res://features/bird/feature.tscn")

var _bird: Bird


func before_each() -> void:
	_bird = BirdScene.instantiate() as Bird
	add_child_autofree(_bird)
	await get_tree().physics_frame


func test_starts_alive() -> void:
	assert_true(_bird.net_alive)
	assert_true(_bird.net_flying)


func test_is_in_killable_and_birds_groups() -> void:
	assert_true(_bird.is_in_group(&"killable"))
	assert_true(_bird.is_in_group(&"birds"))


func test_take_hit_kills_bird() -> void:
	_bird.take_hit(2)
	assert_false(_bird.net_alive)


func test_dead_bird_ignores_further_hits() -> void:
	_bird.take_hit(2)
	_bird._respawn_timer = Bird.RESPAWN_DELAY_S
	_bird.take_hit(2)
	assert_almost_eq(_bird._respawn_timer, Bird.RESPAWN_DELAY_S, 0.001)


func test_stays_dead_before_respawn_delay() -> void:
	_bird.take_hit(2)
	_bird._physics_process(Bird.RESPAWN_DELAY_S - 0.1)
	assert_false(_bird.net_alive)


func test_respawns_after_respawn_delay() -> void:
	_bird.take_hit(2)
	_bird._physics_process(Bird.RESPAWN_DELAY_S)
	assert_true(_bird.net_alive)


func test_flies_toward_active_player_when_present() -> void:
	var dummy_player := Node3D.new()
	dummy_player.name = "DummyPlayer"
	dummy_player.add_to_group(&"players")
	add_child_autofree(dummy_player)
	dummy_player.global_position = Vector3(10.0, 1.5, 0.0)

	_bird.global_position = Vector3.ZERO
	_bird._flight_start = Vector3.ZERO
	_bird._target = dummy_player
	_bird._flight_progress = 0.0
	_bird._state = Bird.State.STATE_FLYING

	_bird._physics_process(0.1)
	assert_gt(_bird._flight_progress, 0.0, "Progress advanced toward player")
	assert_gt(_bird.global_position.x, 0.0, "Moved toward player on X axis")


func test_wing_flapping_animates_wings() -> void:
	_bird.net_flying = true
	_bird._process(0.1)
	var left_wing := _bird.get_node("Body/WingLeft") as Node3D
	var right_wing := _bird.get_node("Body/WingRight") as Node3D
	assert_ne(left_wing.rotation.z, 0.0, "Left wing flaps")
	assert_almost_eq(
		left_wing.rotation.z, -right_wing.rotation.z, 0.001, "Wings flap symmetrically"
	)
