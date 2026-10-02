extends GutTest

const CombatScene := preload("res://features/combat/feature.tscn")

var _combat: Combat
var _was_playing := false
var _mouse_mode: Input.MouseMode
var _device: Controls.Device


func before_each() -> void:
	_was_playing = Controls.playing
	_mouse_mode = Input.mouse_mode
	_device = Controls.device
	Controls.device = Controls.Device.GAMEPAD
	_combat = CombatScene.instantiate() as Combat
	add_child_autofree(_combat)


func after_each() -> void:
	Controls.device = _device
	Controls.playing = _was_playing
	Input.mouse_mode = _mouse_mode
	await wait_process_frames(1)


func test_screen_uses_exact_text_and_blocks_local_gameplay_until_respawn() -> void:
	Controls.start()
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	var screen := _combat.get_node("Hud/DeathScreen") as ColorRect
	assert_true(screen.visible)
	assert_eq((screen.get_node("Died") as Label).text, "u died gg")
	assert_eq(screen.anchor_right, 1.0)
	assert_eq(screen.anchor_bottom, 1.0)
	assert_false(Controls.gameplay_active())
	assert_true(_combat.get_node("Hud").is_in_group(&"modal_ui"))
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_false(screen.visible)
	assert_false(_combat.get_node("Hud").is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_other_victim_does_not_show_local_screen() -> void:
	_combat.apply_damage(2, Combat.MAX_HEALTH, 3)
	assert_false((_combat.get_node("Hud/DeathScreen") as Control).visible)


func test_repeated_damage_during_delay_cannot_duplicate_kills_or_extend_delay() -> void:
	watch_signals(_combat)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 3)
	assert_eq(_combat.kills_for(2), 1)
	assert_eq(_combat.kills_for(3), 0)
	assert_signal_emit_count(_combat, "player_died", 1)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_signal_emit_count(_combat, "player_respawned", 1)
	_combat.apply_damage(1, 25.0, 2)
	assert_eq(_combat.health_for(1), 75.0)


func test_separate_victims_finish_independently() -> void:
	watch_signals(_combat)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 3)
	_combat.apply_damage(2, Combat.MAX_HEALTH, 3)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_signal_emit_count(_combat, "player_respawned", 2)
	assert_eq(_combat.kills_for(3), 2)


func test_disconnect_cancels_pending_respawn() -> void:
	watch_signals(_combat)
	_combat.apply_damage(2, Combat.MAX_HEALTH, 3)
	_combat.multiplayer.peer_disconnected.emit(2)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_signal_not_emitted(_combat, "player_respawned")


func test_session_reset_cancels_respawn_and_cleans_modal() -> void:
	watch_signals(_combat)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	Network.mode_changed.emit(Network.Mode.OFFLINE)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_signal_not_emitted(_combat, "player_respawned")
	assert_false((_combat.get_node("Hud/DeathScreen") as Control).visible)
	assert_false(_combat.get_node("Hud").is_in_group(&"modal_ui"))


func test_respawn_does_not_resume_over_another_menu() -> void:
	Controls.start()
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	var menu := Node.new()
	add_child_autofree(menu)
	menu.add_to_group(&"modal_ui")
	Controls.pause()
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_false(Controls.playing)
	assert_false((_combat.get_node("Hud/DeathScreen") as Control).visible)


func test_death_while_already_paused_does_not_capture_mouse_on_respawn() -> void:
	Controls.pause()
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	await wait_seconds(Combat.RESPAWN_DELAY_S + 0.1)
	assert_false(Controls.playing)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
