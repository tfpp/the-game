extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
var _panel: GarageJobPanel
var _desktop: GarageDesktop


func before_each() -> void:
	var feature := FEATURE.instantiate()
	add_child_autofree(feature)
	_panel = feature.get_node("JobPanel")
	_panel.set_process(false)
	_panel.open(feature.get_node("Room/JobTerminal"))
	_panel._root.size = Vector2(1200, 800)
	_desktop = _panel.desktop
	await wait_process_frames(3)


func after_each() -> void:
	_panel.close(false)


func test_concurrent_windows_focus_minimize_close_and_compact_calculator() -> void:
	_desktop.launch_app("Notes")
	_desktop.launch_app("Calculator")
	await wait_process_frames(3)
	var notes := _desktop._windows["Notes"] as GarageDesktopWindow
	var calculator := _desktop._windows["Calculator"] as GarageDesktopWindow
	assert_true(notes.visible)
	assert_true(calculator.visible)
	assert_lt(calculator.size.x, notes.size.x)
	assert_lt(calculator.size.x, _desktop._workspace.size.x / 2)
	assert_gt(calculator.get_index(), notes.get_index())
	calculator.position = notes.position + Vector2(50, 50)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = (
		_desktop._workspace.get_global_transform_with_canvas()
		* (calculator.position + Vector2(20, 20))
	)
	notes._input(click)
	assert_eq(_desktop.active_app, "Calculator", "An occluded app cannot steal a click")
	click.position = (
		_desktop._workspace.get_global_transform_with_canvas() * (notes.position + Vector2(10, 10))
	)
	notes._input(click)
	assert_eq(_desktop.active_app, "Notes")
	assert_gt(notes.get_index(), calculator.get_index())
	_desktop.close_app("Calculator")
	assert_true(notes.visible)
	assert_false(calculator.visible)
	assert_eq(_desktop.active_app, "Notes")
	_desktop.launch_app("Calculator")
	_desktop._editor.grab_focus()
	assert_eq(_desktop.active_app, "Notes", "Controller/keyboard focus raises the editor")
	_desktop.minimize("Calculator")
	_desktop.minimize("Notes")
	assert_eq(_desktop.active_app, "")
	_desktop._tasks["Notes"].pressed.emit()
	assert_true(notes.visible)


func test_touch_drag_resize_bounds_and_maximize_restore() -> void:
	_desktop.launch_app("Notes")
	var window := _desktop._windows["Notes"] as GarageDesktopWindow
	var old_position := window.position
	var old_size := window.size
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	var transform := _desktop._workspace.get_global_transform_with_canvas()
	touch.position = transform * Vector2(200, 200)
	window.begin_gesture(touch, "move")
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = transform * Vector2(240, 230)
	window._input(drag)
	assert_eq(window.position, old_position + Vector2(40, 30))
	touch.pressed = false
	window._input(touch)
	assert_eq(window._gesture, "")
	touch.pressed = true
	window.begin_gesture(touch, "resize")
	drag.position = transform * Vector2(260, 240)
	window._input(drag)
	assert_eq(window.size, old_size + Vector2(60, 40))
	drag.position = transform * Vector2(-10000, -10000)
	window._input(drag)
	assert_gte(window.size.x, 300.0)
	assert_gte(window.size.y, 220.0)
	drag.position = transform * Vector2(10000, 10000)
	window._input(drag)
	assert_lte(window.get_rect().end.x, _desktop._workspace.size.x)
	assert_lte(window.get_rect().end.y, _desktop._workspace.size.y)
	window.cancel_gesture()
	var restored := window.get_rect()
	window.toggle_maximize()
	assert_eq(window.position, Vector2.ZERO)
	assert_eq(window.size, _desktop._workspace.size)
	window.toggle_maximize()
	assert_eq(window.get_rect(), restored)
	_panel._root.size = Vector2(390, 390)
	await wait_process_frames(4)
	assert_lte(window.get_rect().end.x, _desktop._workspace.size.x)
	assert_lte(window.get_rect().end.y, _desktop._workspace.size.y)


func test_mouse_drag_uses_canvas_scale_and_hiding_cancels_gesture() -> void:
	_desktop.launch_app("Files")
	var window := _desktop._windows["Files"] as GarageDesktopWindow
	_panel.scale = Vector2(2, 2)
	var start := window.position
	var label := window.get_child(0).get_child(0).get_child(0).get_child(0) as Label
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(10, 10)
	var viewport_start := label.get_global_transform_with_canvas() * click.position
	label.gui_input.emit(click)
	assert_eq(window._gesture, "move")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = viewport_start + Vector2(40, 60)
	window._input(motion)
	assert_eq(window.position, start + Vector2(20, 30))
	_desktop.minimize("Files")
	assert_eq(window._gesture, "")
	_panel.scale = Vector2.ONE


func test_notes_toolbar_stays_above_editor_and_confirms_discard() -> void:
	_desktop.launch_app("Notes")
	await wait_process_frames(3)
	var layout := _desktop._windows["Notes"].get_child(0)
	var toolbar := layout.get_node("DocumentToolbar") as HBoxContainer
	assert_lt(toolbar.get_index(), _desktop._editor.get_parent().get_parent().get_index())
	_desktop._filename.text = "Draft"
	_desktop._editor.text = "Keep this"
	_desktop._editor.text_changed.emit()
	assert_string_contains(_desktop._status.text, "Unsaved")
	(toolbar.get_child(0) as Button).pressed.emit()
	assert_true(_desktop._discard_dialog.visible)
	assert_eq(
		_desktop._discard_dialog.content_scale_factor,
		_desktop.get_global_transform_with_canvas().get_scale().x
	)
	_desktop._discard_dialog.canceled.emit()
	await wait_process_frames(1)
	assert_eq(_desktop._editor.text, "Keep this")
	(toolbar.get_child(1) as Button).pressed.emit()
	assert_eq(_desktop.files["Draft"], "Keep this")
	assert_false(is_instance_valid(_desktop._discard_dialog))
	_desktop._editor.text = "Changed"
	_desktop.open_file("Draft")
	assert_true(_desktop._discard_dialog.visible)
	_desktop._discard_dialog.confirmed.emit()
	await wait_process_frames(1)
	assert_eq(_desktop._editor.text, "Keep this")
	_desktop._editor.text = "Again"
	_desktop._new_note()
	_panel.close(false)
	await wait_process_frames(1)
	assert_false(is_instance_valid(_desktop._discard_dialog))
	assert_eq(_desktop._editor.text, "Again")
