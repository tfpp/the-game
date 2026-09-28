extends GutTest
## `hop_rate_scale` (set externally by features/game_config/game_config.gd) speeds up
## or slows down how often a frog rests between hops.

const FROG := preload("res://features/frogs/frog.tscn")

var _frog: Frog


func before_each() -> void:
	_frog = FROG.instantiate() as Frog
	_frog.rest_time = 1.0
	add_child_autofree(_frog)
	_frog.set_physics_process(false)


func test_joins_the_frogs_group() -> void:
	assert_true(_frog.is_in_group(&"frogs"))


func test_default_hop_rate_leaves_rest_time_unscaled() -> void:
	_frog._fleeing = false
	_frog._finish_hop()
	assert_between(_frog._rest_timer, 0.7, 1.3)


func test_doubling_hop_rate_halves_the_rest_between_hops() -> void:
	_frog.hop_rate_scale = 2.0
	_frog._fleeing = false
	_frog._finish_hop()
	assert_between(_frog._rest_timer, 0.35, 0.65)


func test_respawn_uses_the_scaled_resting_time() -> void:
	_frog.hop_rate_scale = 4.0
	_frog.take_hit(1)
	_frog._respawn()
	assert_almost_eq(_frog._rest_timer, 0.25, 0.001)
