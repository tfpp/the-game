extends GutTest
## Presentation and shell controls, using the actual existing panel.

const FEATURE := preload("res://features/starter_room/feature.tscn")
var _feature: Node3D
var _panel: GarageJobPanel
var _desktop: GarageDesktop


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_panel = _feature.get_node("JobPanel")
	_panel.set_process(false)
	_desktop = _panel.desktop
	_panel.open(_feature.get_node("Room/JobTerminal"))


func after_each() -> void:
	_panel.close(false)


func test_start_menu_launches_existing_apps_and_logoff_closes_modal_and_popup() -> void:
	var menu := _desktop._start.get_popup()
	for id: int in _desktop.APP_NAMES.size():
		assert_eq(menu.get_item_text(id), _desktop.APP_NAMES[id])
		menu.id_pressed.emit(id)
		assert_eq(_desktop.active_app, _desktop.APP_NAMES[id])
		assert_true(_desktop._tasks[_desktop.active_app].button_pressed)
	assert_eq(_desktop.running.size(), 5)
	assert_eq(_panel._buttons.size(), OperationsVan.ZONE_NAMES.size())
	_desktop.save_file("Keep", "private")
	_desktop._start.show_popup()
	assert_true(menu.visible)
	menu.id_pressed.emit(_desktop.APP_NAMES.size())
	assert_false(_panel.is_open())
	assert_false(menu.visible)
	assert_false(_panel.is_in_group("modal_ui"))
	assert_eq(_desktop.files["Keep"], "private")


func test_shortcuts_title_controls_and_taskbar_restore_the_same_windows() -> void:
	_desktop._launchers["Notes"].pressed.emit()
	var window := _desktop._windows["Notes"]
	assert_true(window is PanelContainer)
	var title := window.get_child(0).get_child(0).get_child(0)
	assert_string_contains((title.get_child(0) as Label).text, "Notes")
	(title.get_child(1) as Button).pressed.emit()
	assert_eq(_desktop.active_app, "")
	assert_true(_desktop._home.visible)
	assert_false(_desktop._tasks["Notes"].button_pressed)
	_desktop._tasks["Notes"].pressed.emit()
	assert_true(window.visible)
	assert_true(_desktop._tasks["Notes"].button_pressed)
	(title.get_child(2) as Button).pressed.emit()
	assert_false(window.visible)
	assert_false(_desktop._tasks["Notes"].visible)
	assert_false("Notes" in _desktop.running)


func test_taskbar_and_window_chrome_fit_desktop_phone_and_landscape() -> void:
	for dimensions: Vector2 in [Vector2(960, 540), Vector2(390, 844), Vector2(844, 390)]:
		_panel._root.size = dimensions
		for app: String in _desktop.APP_NAMES:
			_desktop.launch_app(app)
			await wait_process_frames(3)
			var window := _desktop._windows[app]
			var bar := _desktop._taskbar.get_parent() as Control
			assert_lte(window.get_global_rect().end.x, dimensions.x)
			assert_lte(window.get_global_rect().end.y, bar.global_position.y)
			assert_lte(bar.get_global_rect().end.y, dimensions.y)
			assert_lt(bar.global_position.y, dimensions.y)
			assert_gte(window.size.y, 100.0)
		_desktop.minimize()
		await wait_process_frames(3)
		assert_lte(_desktop._home.get_global_rect().end.y, dimensions.y)
		for shortcut: Button in _desktop._launchers.values():
			assert_true(shortcut.is_visible_in_tree())
			assert_lte(shortcut.get_global_rect().end.x, dimensions.x)


func test_classic_controls_share_readable_theme_including_existing_jobs() -> void:
	var style := _desktop.theme.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_eq(style.bg_color, Color("c0c0c0"))
	assert_eq(_desktop.theme.get_color("font_color", "Button"), Color("181818"))
	assert_eq(_panel._buttons[0].get_theme_stylebox("normal"), style)
	assert_eq(_desktop._editor.get_theme_color("font_color"), Color("181818"))
	assert_eq(_desktop._editor.get_theme_color("caret_color"), Color.BLACK)
