extends GutTest
## `features/settings/settings.gd`: the Esc menu's "Settings" hub and its pages, plus
## `SettingsStore` persistence.

const Settings := preload("res://features/settings/settings.gd")
const STORE_NAME := "test_settings_store"


## A stand-in for a feature's settings page (e.g. Controls, Audio).
class _PageStub:
	extends Node
	var label := "Test page"
	var consume := false
	var seen: Array[InputEvent] = []

	func _ready() -> void:
		add_to_group(&"settings_pages")

	func settings_page_label() -> String:
		return label

	func settings_page_build() -> Control:
		var content := Label.new()
		content.text = "%s content" % label
		return content

	func settings_page_input(event: InputEvent) -> bool:
		seen.append(event)
		return consume


var _settings: Settings
var _saved_device: int


func before_each() -> void:
	_saved_device = Controls.device
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	_settings = Settings.new()
	add_child_autofree(_settings)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	var path := ProjectSettings.globalize_path(SettingsStore.native_path(STORE_NAME))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_registers_a_settings_link_in_the_esc_menu() -> void:
	assert_true(_settings.is_in_group(&"esc_menu_links"))
	assert_eq(_settings.esc_menu_label(), "Settings")


func test_opening_pauses_and_joins_the_modal_group() -> void:
	_settings.esc_menu_open()
	assert_true(_settings.is_open())
	assert_true(_settings.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())


func test_hub_lists_pages_alphabetically() -> void:
	_page("Video")
	_page("Audio")
	_settings.open()
	var labels: Array[String] = []
	for page: Node in _settings.pages():
		labels.append(page.settings_page_label())
	assert_eq(labels.slice(0, 2), ["Audio", "Video"])
	assert_true(_button_texts().has("Audio"))
	assert_true(_button_texts().has("Video"))


func test_page_opens_in_the_panel_and_back_returns_to_the_hub() -> void:
	var page := _page("Audio")
	_settings.open()
	_settings.show_page(page)
	assert_eq(_settings._heading.text, "Audio")
	assert_eq(_settings._back.text, "Back to settings")
	_settings.go_back()
	assert_eq(_settings._heading.text, "Settings")
	assert_true(_settings.is_open())


func test_back_from_the_hub_returns_to_the_esc_menu() -> void:
	_settings.open()
	watch_signals(Controls)
	_settings.go_back()
	assert_false(_settings.is_open())
	assert_false(_settings.is_in_group(&"modal_ui"))
	assert_signal_emitted(Controls, "menu_requested")


func test_esc_steps_back_one_level() -> void:
	var page := _page("Audio")
	_settings.open()
	_settings.show_page(page)
	_settings._input(_esc())
	assert_eq(_settings._heading.text, "Settings", "Page -> hub")
	_settings._input(_esc())
	assert_false(_settings.is_open(), "Hub -> Esc menu")


func test_page_sees_input_first_and_can_consume_it() -> void:
	var page := _page("Controls")
	page.consume = true
	_settings.open()
	_settings.show_page(page)
	_settings._input(_esc())
	assert_eq(page.seen.size(), 1)
	assert_eq(_settings._heading.text, "Controls", "Consumed Esc doesn't go back")


func test_controller_menu_request_closes_settings() -> void:
	_settings.open()
	Controls.menu_requested.emit()
	assert_false(_settings.is_open())


func test_store_round_trips_a_dictionary() -> void:
	assert_eq(SettingsStore.load_data(STORE_NAME), {})
	SettingsStore.save_data(STORE_NAME, {"volume": 0.5, "name": "x"})
	assert_eq(SettingsStore.load_data(STORE_NAME), {"volume": 0.5, "name": "x"})


func _page(label: String) -> _PageStub:
	var page := _PageStub.new()
	page.label = label
	add_child_autofree(page)
	return page


func _button_texts() -> Array[String]:
	var result: Array[String] = []
	for node: Node in _settings._body.get_children():
		if node is Button:
			result.append((node as Button).text)
	return result


func _esc() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event
