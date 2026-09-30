extends GutTest
## Server-authoritative kill/respawn behavior for the penguin feature
## (features/penguin/penguin.gd). Runs single-process like test_holdables.gd, so
## peer 1 is the server and `take_hit` resolves as if called from server code.

const PenguinScene := preload("res://features/penguin/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const PlayerModelsScene := preload("res://features/player_models/feature.tscn")

var _penguin: Penguin


func before_each() -> void:
	var feature := PenguinScene.instantiate() as Node3D
	add_child_autofree(feature)
	_penguin = feature.get_node("Penguin") as Penguin
	# Drive physics through manual `_physics_process` calls: AnimatableBody3D
	# transform sets outside the physics step are unreliable in headless runs.
	_penguin.set_physics_process(false)
	(feature.get_node("Wife") as Penguin).set_physics_process(false)
	await get_tree().physics_frame


func test_starts_alive() -> void:
	assert_true(_penguin.net_alive)


func test_take_hit_kills_her() -> void:
	_penguin.take_hit(2)
	assert_false(_penguin.net_alive)


func test_a_dead_penguin_ignores_further_hits() -> void:
	_penguin.take_hit(2)
	_penguin._respawn_timer = Penguin.RESPAWN_DELAY_S
	_penguin.take_hit(2)
	assert_almost_eq(_penguin._respawn_timer, Penguin.RESPAWN_DELAY_S, 0.001)


func test_stays_dead_before_the_respawn_delay_elapses() -> void:
	_penguin.take_hit(2)
	_penguin._physics_process(Penguin.RESPAWN_DELAY_S - 0.1)
	assert_false(_penguin.net_alive)


func test_respawns_at_home_after_the_respawn_delay() -> void:
	var home := _penguin.position
	_penguin.take_hit(2)
	_penguin._physics_process(Penguin.RESPAWN_DELAY_S)
	assert_true(_penguin.net_alive)
	assert_eq(_penguin.position, home)


func test_is_in_the_killable_group() -> void:
	assert_true(_penguin.is_in_group(&"killable"))


func test_waves_and_hops_when_a_nearby_player_becomes_a_penguin() -> void:
	var models := PlayerModelsScene.instantiate() as PlayerModels
	add_child_autofree(models)
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = _penguin.global_position + Vector3(1, 0, 0)
	_penguin._process(0.0)
	assert_eq(_penguin._body.position.y, 0.0, "Not reacting to a default-model player nearby")
	assert_eq(_penguin._wave_flipper.rotation.z, 0.0)
	models.body_types = {1: "penguin"}
	_penguin._elapsed = 0.1
	_penguin._process(0.0)
	assert_gt(_penguin._body.position.y, 0.0, "Hops once a nearby player becomes a penguin")
	assert_ne(_penguin._wave_flipper.rotation.z, 0.0, "Waves a flipper at them")


func test_does_not_react_to_a_penguin_player_far_away() -> void:
	var models := PlayerModelsScene.instantiate() as PlayerModels
	add_child_autofree(models)
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = _penguin.global_position + Vector3(50, 0, 0)
	models.body_types = {1: "penguin"}
	_penguin._elapsed = 0.1
	_penguin._process(0.0)
	assert_eq(_penguin._body.position.y, 0.0, "Too far away to notice")
	assert_eq(_penguin._wave_flipper.rotation.z, 0.0)


func test_beak_points_along_patrol_travel() -> void:
	for phase: float in [0.0, 0.25, 0.5, 0.75]:
		_penguin._elapsed = phase / PenguinWaddle.WADDLE_FREQUENCY
		for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			_penguin.net_yaw = PenguinWaddle.facing_yaw(angle)
			_penguin._process(0.0)
			var torso := _penguin.get_node("Body/Torso") as Node3D
			var beak := torso.get_node("Beak") as Node3D
			# Remove the beak's height in model space before the waddle roll turns
			# that vertical offset into a sideways displacement. Facing is the
			# forward offset, not the torso-to-beak diagonal at an arbitrary frame.
			var facing := torso.global_basis * (beak.position * Vector3(1, 0, 1))
			var before := PenguinWaddle.position_on_circle(Vector3.ZERO, 2.0, angle - 0.001)
			var after := PenguinWaddle.position_on_circle(Vector3.ZERO, 2.0, angle + 0.001)
			assert_gt(facing.normalized().dot((after - before).normalized()), 0.99)
