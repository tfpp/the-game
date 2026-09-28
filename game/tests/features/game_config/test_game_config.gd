extends GutTest
## features/game_config/game_config.gd: the Settings menu's "Game" page and its
## server-authoritative jump height / frog hop rate knobs. Runs single-process, so
## `multiplayer.is_server()` is true (see tests/features/soccer_ball/test_soccer_ball.gd),
## and a freshly added Player defaults to authority 1, the same as `multiplayer`'s
## default unique id, so it lands in the "local_player" group without extra setup
## (see tests/features/trampoline/test_trampoline_pad.gd).

const GAME_CONFIG := preload("res://features/game_config/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const FROG := preload("res://features/frogs/frog.tscn")

var _config: GameConfig


func before_each() -> void:
	_config = GAME_CONFIG.instantiate() as GameConfig
	add_child_autofree(_config)
	_config.set_process(false)


func test_registers_as_a_settings_page() -> void:
	assert_true(_config.is_in_group(&"settings_pages"))
	assert_eq(_config.settings_page_label(), "Game")


func test_defaults_to_unscaled() -> void:
	assert_eq(_config.jump_height_scale, 1.0)
	assert_eq(_config.frog_hop_rate, 1.0)


func test_request_jump_height_scale_is_clamped_to_range() -> void:
	_config.request_jump_height_scale(999.0)
	assert_eq(_config.jump_height_scale, GameConfig.JUMP_HEIGHT_RANGE.y)
	_config.request_jump_height_scale(-5.0)
	assert_eq(_config.jump_height_scale, GameConfig.JUMP_HEIGHT_RANGE.x)


func test_request_frog_hop_rate_is_clamped_to_range() -> void:
	_config.request_frog_hop_rate(999.0)
	assert_eq(_config.frog_hop_rate, GameConfig.FROG_HOP_RATE_RANGE.y)
	_config.request_frog_hop_rate(-5.0)
	assert_eq(_config.frog_hop_rate, GameConfig.FROG_HOP_RATE_RANGE.x)


func test_applies_jump_height_to_the_local_player_only() -> void:
	var base := MovementConfig.new().jump_speed
	var local_player := PLAYER.instantiate() as Player
	add_child_autofree(local_player)
	_config.request_jump_height_scale(1.5)
	_config._apply_jump_height()
	assert_almost_eq(local_player.movement.jump_speed, base * 1.5, 0.001)


func test_applies_frog_hop_rate_to_every_frog() -> void:
	var frog := FROG.instantiate() as Frog
	add_child_autofree(frog)
	frog.set_physics_process(false)
	_config.request_frog_hop_rate(2.0)
	_config._apply_frog_hop_rate()
	assert_eq(frog.hop_rate_scale, 2.0)
