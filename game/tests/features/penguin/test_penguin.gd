extends GutTest
## Server-authoritative kill/respawn behavior for the penguin feature
## (features/penguin/penguin.gd). Runs single-process like test_holdables.gd, so
## peer 1 is the server and `take_hit` resolves as if called from server code.

const PenguinScene := preload("res://features/penguin/feature.tscn")

var _penguin: Penguin


func before_each() -> void:
	_penguin = PenguinScene.instantiate() as Penguin
	add_child_autofree(_penguin)
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
