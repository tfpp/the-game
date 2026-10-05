extends GutTest
## The workbench always shows a tappable close control on phone screens.

const FEATURE := preload("res://features/starter_room/feature.tscn")


func _open_at(window: Vector2i) -> CanvasLayer:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var bench := feature.get_node("Room/Workbench") as GearWorkbench
	bench.items = [
		{"slot": -1, "id": "pistol", "available": true},
		{"slot": 0, "id": "pistol", "available": false},
		{"slot": 1, "id": "pistol", "available": false},
	]
	var screen := feature.get_node("WorkbenchScreen") as CanvasLayer
	screen.set_process(false)
	get_window().size = window
	screen.call("_resize")
	screen.call("open", bench)
	return screen


func _assert_on_screen(screen: CanvasLayer, button: Button) -> void:
	var root := screen.get("_root") as Control
	var fit := Rect2(Vector2.ZERO, screen.get("_fit_size"))
	var rect := Rect2(button.global_position - root.global_position, button.size)
	assert_true(button.is_visible_in_tree())
	assert_gte(rect.size.y, 44.0)
	assert_true(fit.encloses(rect), "%s inside %s" % [rect, fit])


func test_close_buttons_stay_on_screen_on_phones() -> void:
	var original := get_window().size
	for window: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(640, 300)]:
		var screen := _open_at(window)
		await wait_process_frames(3)
		_assert_on_screen(screen, screen.get("_close") as Button)
		_assert_on_screen(screen, screen.get("_back") as Button)
		screen.call("close")
	get_window().size = original


func test_close_button_hides_panel_and_resumes_play() -> void:
	var screen := _open_at(get_window().size)
	await wait_process_frames(1)
	assert_true(screen.is_in_group(&"modal_ui"))
	(screen.get("_close") as Button).pressed.emit()
	assert_false((screen.get("_root") as Control).visible)
	assert_false(screen.is_in_group(&"modal_ui"))
