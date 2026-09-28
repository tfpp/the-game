extends GutTest
## `features/audio_settings/audio_settings.gd`: the Settings > Audio page.

const AudioSettings := preload("res://features/audio_settings/audio_settings.gd")
const STORE_PATH := "user://audio.cfg"

var _saved_db: float
var _saved_mute: bool


func before_each() -> void:
	_saved_db = AudioServer.get_bus_volume_db(0)
	_saved_mute = AudioServer.is_bus_mute(0)
	_clear_store()


func after_each() -> void:
	AudioServer.set_bus_volume_db(0, _saved_db)
	AudioServer.set_bus_mute(0, _saved_mute)
	_clear_store()


func test_registers_an_audio_page_in_settings() -> void:
	var node := _new_node()
	assert_true(node.is_in_group(&"settings_pages"))
	assert_eq(node.settings_page_label(), "Audio")
	var page := node.settings_page_build()
	add_child_autofree(page)
	assert_eq(page.find_children("*", "HSlider", true, false).size(), 2)


func test_volume_sets_the_master_bus_and_persists() -> void:
	var node := _new_node()
	node.set_volume("master", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01)
	AudioServer.set_bus_volume_db(0, 0.0)
	var reloaded := _new_node()
	reloaded.apply()
	assert_almost_eq(reloaded.volumes["master"], 0.5, 0.0001)
	assert_almost_eq(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01)


func test_zero_volume_and_mute_silence_the_bus() -> void:
	var node := _new_node()
	node.set_volume("master", 0.0)
	assert_true(AudioServer.is_bus_mute(0))
	node.set_volume("master", 1.0)
	assert_false(AudioServer.is_bus_mute(0))
	node.set_muted(true)
	assert_true(AudioServer.is_bus_mute(0))
	node.set_muted(false)
	assert_false(AudioServer.is_bus_mute(0))


func _new_node() -> AudioSettings:
	var node := AudioSettings.new()
	add_child_autofree(node)
	return node


func _clear_store() -> void:
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
