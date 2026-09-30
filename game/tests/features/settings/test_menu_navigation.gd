extends GutTest

const Login := preload("res://ui/login/login_screen.gd")
const Settings := preload("res://features/settings/settings.gd")


class Link:
	extends Node
	var label := ""
	var opened := false

	func esc_menu_label() -> String:
		return label

	func esc_menu_open() -> void:
		opened = true
		add_to_group(&"modal_ui")
		Controls.pause()


class SessionApi:
	extends AccountApi

	func has_session() -> bool:
		return true


var _menu: Login
var _saved_device: int


func before_each() -> void:
	_saved_device = Controls.device
	Controls.device = Controls.Device.TOUCH
	_menu = Login.new()
	add_child_autofree(_menu)
	_menu.open_menu()


func after_each() -> void:
	await wait_frames(2)
	Controls.pause()
	Controls.device = _saved_device


func test_home_keeps_settings_direct_and_groups_other_links() -> void:
	for label: String in ["Settings", "Inventory", "GPS", "Leaderboard", "Profiler", "New panel"]:
		_link(label)
	_menu.open_menu()
	assert_eq(_buttons(), ["Resume", "Settings", "Activities", "More"])
	assert_true(_menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())


func test_activities_and_more_keep_every_link_sorted_and_reachable() -> void:
	for label: String in ["Inventory", "GPS", "Leaderboard", "Profiler", "New panel"]:
		_link(label)
	_press("Activities")
	assert_eq(_buttons(), ["Back to menu", "GPS", "Inventory", "Leaderboard"])
	_press("Back to menu")
	_press("More")
	assert_true(_buttons().has("Profiler"))
	assert_true(_buttons().has("New panel"), "Unknown links must not disappear")
	assert_false(_buttons().has("Inventory"))


func test_start_steps_back_before_resuming() -> void:
	_press("Activities")
	_menu._on_menu_requested()
	assert_true(_menu.visible)
	assert_false(_menu._submenu)
	assert_false(Controls.gameplay_active())
	_menu._on_menu_requested()
	assert_false(_menu.visible)
	assert_true(Controls.gameplay_active())


func test_cancel_steps_back_before_resuming_on_native() -> void:
	_press("More")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	_menu._input(cancel)
	assert_true(_menu.visible)
	assert_false(_menu._submenu)
	_menu._input(cancel)
	assert_false(_menu.visible)
	assert_true(Controls.gameplay_active())


func test_resume_still_runs_on_press_and_starts_touch_play() -> void:
	var resume := _button("Resume")
	assert_eq(resume.action_mode, BaseButton.ACTION_MODE_BUTTON_PRESS)
	resume.pressed.emit()
	assert_false(_menu.visible)
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_feature_handoff_keeps_gameplay_paused() -> void:
	var inventory := _link("Inventory")
	_press("Activities")
	_press("Inventory")
	assert_true(inventory.opened)
	assert_false(_menu.visible)
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())


func test_settings_handoff_and_back_reopens_home() -> void:
	var settings := Settings.new()
	add_child_autofree(settings)
	_menu.open_menu()
	_press("Settings")
	assert_true(settings.is_open())
	assert_false(_menu.visible)
	settings.go_back()
	assert_false(settings.is_open())
	assert_true(_menu.visible)
	assert_true(_buttons().has("Resume"))
	assert_false(Controls.gameplay_active())


func test_game_menu_hides_session_actions_until_more() -> void:
	_menu._show_game_menu("")
	assert_false(_buttons().has("Leave and play offline"))
	assert_false(_buttons().has("Sign out"))
	assert_true(_buttons().has("More"))


func test_online_account_and_leave_actions_remain_reachable_under_more() -> void:
	var saved_mode := Network.mode
	Network.mode = Network.Mode.CLIENT
	_menu._api = SessionApi.new("")
	add_child_autofree(_menu._api)
	_menu._account = {"display_name": "MenuTester", "discord_linked": true}
	_menu.open_menu()
	assert_false(_buttons().has("Change display name"))
	assert_false(_buttons().has("Sign out"))
	_press("More")
	assert_true(_buttons().has("Change display name"))
	assert_true(_buttons().has("Sign out"))
	assert_true(_buttons().has("Leave and play offline"))
	_press("Back to menu")
	assert_true(_buttons().has("Resume"))
	Network.mode = saved_mode


func _link(label: String) -> Link:
	var link := Link.new()
	link.label = label
	add_child_autofree(link)
	link.add_to_group(&"esc_menu_links")
	return link


func _buttons() -> Array[String]:
	var labels: Array[String] = []
	for child: Node in _menu._box.get_children():
		if child is Button:
			labels.append((child as Button).text)
	return labels


func _button(text: String) -> Button:
	for child: Node in _menu._box.get_children():
		if child is Button and (child as Button).text == text:
			return child as Button
	return null


func _press(text: String) -> void:
	var button := _button(text)
	assert_not_null(button, text)
	if button != null:
		button.pressed.emit()
