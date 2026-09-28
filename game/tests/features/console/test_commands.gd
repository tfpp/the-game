extends GutTest

const Commands := preload("res://features/console/commands.gd")
const ControlScheme := preload("res://features/control_scheme/control_scheme.gd")
const Audio := preload("res://features/audio_settings/audio_settings.gd")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")

var commands: Commands
var controls: ControlScheme
var audio: Audio
var game: GameConfig
var saved_controls: String
var saved_audio: String
var saved_bindings: Dictionary = {}
var saved_values: Array = []


func before_each() -> void:
	saved_controls = SettingsStore.load_text("controls")
	saved_audio = SettingsStore.load_text("audio")
	saved_values = [
		Controls.scheme,
		Controls.sensitivity,
		Controls.stick_sensitivity,
		Controls.touch_sensitivity,
		AudioServer.get_bus_volume_db(0),
		AudioServer.is_bus_mute(0)
	]
	for action: StringName in InputMap.get_actions():
		saved_bindings[action] = InputMap.action_get_events(action)
	controls = ControlScheme.new()
	add_child_autofree(controls)
	audio = Audio.new()
	add_child_autofree(audio)
	game = preload("res://features/game_config/feature.tscn").instantiate()
	add_child_autofree(game)
	commands = Commands.new(get_tree())


func after_each() -> void:
	SettingsStore.save_text("controls", saved_controls)
	SettingsStore.save_text("audio", saved_audio)
	Controls.scheme = saved_values[0]
	Controls.sensitivity = saved_values[1]
	Controls.stick_sensitivity = saved_values[2]
	Controls.touch_sensitivity = saved_values[3]
	AudioServer.set_bus_volume_db(0, saved_values[4])
	AudioServer.set_bus_mute(0, saved_values[5])
	for action: StringName in saved_bindings:
		Bindings.set_events(action, saved_bindings[action])


func test_local_settings_reuse_setters_and_persistence() -> void:
	commands.execute("sensitivity 3.5")
	commands.execute("stick_scale 2")
	commands.execute("touch_scale 0.5")
	commands.execute("scheme left")
	assert_eq(Controls.sensitivity, 3.5)
	assert_eq(Controls.stick_sensitivity, Controls.STICK_SENSITIVITY * 2)
	assert_eq(Controls.touch_sensitivity, Controls.TOUCH_SENSITIVITY * 0.5)
	assert_eq(SettingsStore.load_data("controls")["scheme"], "left")
	commands.execute("volume 0.25")
	commands.execute("effects_volume 0.5")
	commands.execute("mute 1")
	assert_eq(audio.volumes["master"], 0.25)
	assert_eq(SettingsStore.load_data("audio")["effects"], 0.5)
	assert_true(AudioServer.is_bus_mute(0))
	assert_true(commands.execute("volume").contains("0.25"))


func test_invalid_values_do_not_mutate_and_ranges_use_existing_clamps() -> void:
	commands.execute("sensitivity 2")
	for value: String in ["nan", "inf", "oops", "2 3", "1;quit"]:
		commands.execute("sensitivity " + value)
		assert_eq(Controls.sensitivity, 2.0)
	commands.execute("sensitivity 99")
	assert_eq(Controls.sensitivity, 10.0)
	assert_true(commands.execute("quit").begins_with("Unknown"))


func test_shared_commands_follow_game_config_rpc() -> void:
	commands.execute("jump_height_scale 2")
	commands.execute("frog_hop_rate 2.5")
	commands.execute("frog_jump_height_scale 3")
	assert_eq(game.jump_height_scale, 2.0)
	assert_eq(game.frog_hop_rate, 2.5)
	assert_eq(game.frog_jump_height_scale, 3.0)
	game.request_jump_height_scale(NAN)
	assert_eq(game.jump_height_scale, 2.0)


func test_bindings_preserve_other_slot_and_persist() -> void:
	commands.execute("bind jump J")
	commands.execute("bind jump pad:3")
	assert_eq(SettingsStore.load_data("controls")["bindings"]["jump"]["kbm"]["key"], float(KEY_J))
	assert_eq(SettingsStore.load_data("controls")["bindings"]["jump"]["pad"]["pad"], 3.0)
	assert_true(commands.execute("bind jump Escape").contains("reserved"))
	assert_true(commands.execute("bind missing K").begins_with("bind <action>"))
	assert_true(commands.execute("bind jump").contains("J"))
	commands.execute("reset_bindings")
	assert_true(SettingsStore.load_data("controls")["bindings"].is_empty())


func test_suggestions_rank_prefixes_and_offer_arguments() -> void:
	assert_eq(commands.suggestions("SENS")[0], "sensitivity")
	assert_true(commands.suggestions("frog").has("frog_hop_rate"))
	assert_eq(commands.suggestions("sv_cheats "), PackedStringArray(["sv_cheats 0", "sv_cheats 1"]))
	assert_eq(commands.suggestions("scheme r"), PackedStringArray(["scheme right"]))
	assert_true(commands.suggestions("bind ju").has("bind jump "))
	assert_true(commands.suggestions("bind jump sp").has("bind jump space"))
	assert_true(commands.suggestions("not_a_command").is_empty())
	assert_true(commands.execute("help frog").contains("frog_jump_height_scale"))
