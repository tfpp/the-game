extends GutTest
## Integration coverage for the soccer_ball feature (features/soccer_ball/soccer_ball.gd):
## rolling, being bumped by a nearby player, and being kicked by a hitscan hit. Runs
## single-process, so `multiplayer.is_server()` is true, the same trick
## tests/features/frogs/test_frog_death.gd uses to call server-only methods directly.

const SOCCER_BALL := preload("res://features/soccer_ball/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const BallPhysics := preload("res://features/soccer_ball/ball_physics.gd")

var _ball: SoccerBall


func before_each() -> void:
	_ball = SOCCER_BALL.instantiate() as SoccerBall
	add_child_autofree(_ball)
	_ball.set_physics_process(false)


## A flat, floor-only stand-in for world/room.tscn's Structure, just enough for
## move_and_slide to have something to settle on.
func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 1, 20)
	collider.shape = shape
	collider.position.y = -0.5
	floor_body.add_child(collider)
	add_child_autofree(floor_body)


func test_is_killable_so_any_weapon_can_hit_it() -> void:
	assert_true(_ball.is_in_group(&"killable"))


func test_does_not_block_player_movement() -> void:
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	assert_eq(player.collision_mask & _ball.collision_layer, 0)


func test_a_physics_step_replicates_the_new_position() -> void:
	_add_floor()
	_ball.global_position.y = 3.0
	_ball._physics_process(1.0 / 60.0)
	assert_eq(_ball.net_position, _ball.global_position)


func test_falling_settles_on_the_floor_instead_of_sinking_through() -> void:
	_add_floor()
	_ball.global_position = Vector3(0, 3, 0)
	_ball.set_physics_process(true)
	await wait_physics_frames(240)
	assert_almost_eq(_ball.global_position.y, BallPhysics.RADIUS_M, 0.05)
	assert_almost_eq(_ball.velocity.length(), 0.0, 0.05)


func test_take_hit_kicks_the_ball_away_from_the_shooter() -> void:
	var shooter := PLAYER.instantiate() as Player
	shooter.name = "1"
	shooter.set_multiplayer_authority(1)
	# A local (authority-1) Player recomputes net_position from position in _ready,
	# so both must be set beforehand — see test_holdables.gd's shooter/target setup.
	shooter.position = _ball.global_position + Vector3(-1, 0, 0)
	shooter.net_position = shooter.position
	add_child_autofree(shooter)
	_ball.take_hit(1)
	assert_gt(_ball.velocity.x, 0.0, "A shot from the -X side should send the ball toward +X")
	assert_gt(_ball.velocity.y, 0.0, "A kick should pop the ball up a little")


func test_take_hit_falls_back_to_a_forward_kick_with_no_matching_player() -> void:
	_ball.take_hit(999)
	assert_gt(_ball.velocity.length(), 0.0)


func test_a_nearby_player_bumps_the_ball_away() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	player.position = _ball.global_position + Vector3(0.1, 0, 0)
	player.net_position = player.position
	player.net_velocity = Vector3(-3, 0, 0)
	add_child_autofree(player)
	_ball._apply_bumps()
	assert_lt(_ball.velocity.x, 0.0, "A player pushing in from +X should shove the ball toward -X")


func test_a_distant_player_does_not_bump_the_ball() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	player.position = _ball.global_position + Vector3(20, 0, 0)
	player.net_position = player.position
	add_child_autofree(player)
	_ball._apply_bumps()
	assert_eq(_ball.velocity, Vector3.ZERO)
