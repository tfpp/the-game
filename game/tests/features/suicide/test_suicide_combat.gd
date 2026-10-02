extends GutTest

const Suicide := preload("res://features/suicide/suicide.gd")
const PlayerScene := preload("res://core/player/player.tscn")

var _command: Node
var _player: Player


func before_each() -> void:
	_command = Suicide.new()
	add_child_autofree(_command)
	_player = PlayerScene.instantiate() as Player
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.global_position = Vector3(10, 1, 20)
	_player.net_position = _player.global_position


func after_each() -> void:
	_player.free()
	await wait_process_frames(1)


func test_command_uses_combat_death_and_delayed_respawn_without_self_kill_credit() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	watch_signals(combat)
	_command.handle_chat_command(1, "suicide")
	assert_signal_emitted_with_parameters(combat, "player_died", [1, 1])
	assert_eq(_player.global_position, Vector3(10, 1, 20))
	assert_eq(combat.kills_for(1), 0)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_signal_emitted_with_parameters(combat, "player_respawned", [1])
	assert_lt(_player.global_position.distance_to(Combat.RESPAWN_POINT), 4.5)


func test_command_without_combat_retains_kill_plane_fallback() -> void:
	_command.handle_chat_command(1, "sucide")
	assert_lt(_player.global_position.y, Game.KILL_Y)
	assert_eq(_player.global_position.x, 10.0)


func test_missing_peer_and_unrecognized_commands_do_not_kill_player() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	watch_signals(combat)
	_command.handle_chat_command(2, "suicide")
	_command.handle_chat_command(1, "dance")
	assert_signal_not_emitted(combat, "player_died")
	assert_eq(_player.global_position, Vector3(10, 1, 20))
