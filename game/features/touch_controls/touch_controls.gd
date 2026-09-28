extends Control
## Floating left joystick, independent right look pointer, jump and menu targets.

const INK := Color(0.9, 0.96, 1.0)
const ACCENT := Color(0.34, 0.94, 0.76)
var ui_scale := 1.0
var ui_size := Vector2.ZERO
var safe_bounds := Rect2()
var move_finger := -1
var look_finger := -1
var jump_finger := -1
var use_finger := -1
var move_origin := Vector2.ZERO
var look_position := Vector2.ZERO
var _browser: JavaScriptObject
var _safe_area_refresh := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if OS.has_feature("web"):
		_browser = JavaScriptBridge.get_interface("window")
	Controls.input_reset.connect(_clear_fingers)
	resized.connect(_resize_layout)
	_resize_layout()


func _process(delta: float) -> void:
	visible = Controls.touch_visible() and Controls.gameplay_active()
	_safe_area_refresh -= delta
	if _safe_area_refresh <= 0.0:
		_update_safe_area()
		_safe_area_refresh = 0.5
	queue_redraw()


func _resize_layout() -> void:
	# Reserve separate thumb zones even with the mobile portrait UI layout.
	ui_scale = minf(1.0, maxf(size.x, 1.0) / 600.0)
	ui_size = size / ui_scale
	_update_safe_area()
	_clear_fingers()


func _update_safe_area() -> void:
	safe_bounds = Rect2(Vector2.ZERO, ui_size)
	if _browser == null:
		return
	var area: Variant = JSON.parse_string(str(_browser.getGameSafeArea()))
	if not area is Dictionary:
		return
	var css_size := Vector2(float(area.get("width", 0)), float(area.get("height", 0)))
	if css_size.x <= 0.0 or css_size.y <= 0.0:
		return
	var css_to_ui := ui_size / css_size
	var start := Vector2(float(area.get("left", 0)), float(area.get("top", 0))) * css_to_ui
	var end := Vector2(float(area.get("right", 0)), float(area.get("bottom", 0))) * css_to_ui
	safe_bounds = Rect2(start, ui_size - start - end)


func _clear_fingers() -> void:
	move_finger = -1
	look_finger = -1
	jump_finger = -1
	use_finger = -1
	Controls.touch_move = Vector2.ZERO
	Controls.look_delta = Vector2.ZERO
	Controls.jump_queued = false


func pause_button() -> Rect2:
	return Rect2(safe_bounds.end.x - 100, safe_bounds.position.y + 100, 76, 64)


func jump_center() -> Vector2:
	return safe_bounds.end - Vector2(106, 150)


func use_center() -> Vector2:
	return jump_center() - Vector2(145, 0)


func _input(event: InputEvent) -> void:
	if not Controls.touch_visible() or not Controls.gameplay_active():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var point := touch.position / ui_scale
		if not touch.pressed or touch.canceled:
			_release_finger(touch.index)
		elif pause_button().has_point(point):
			Controls.menu_requested.emit()
		elif point.distance_to(use_center()) <= 54 and use_finger == -1:
			use_finger = touch.index
			get_tree().call_group(&"interaction", "use")
		elif point.distance_to(jump_center()) <= 62 and jump_finger == -1:
			jump_finger = touch.index
			Controls.jump_queued = true
		elif point.x < ui_size.x * 0.45 and move_finger == -1:
			move_finger = touch.index
			move_origin = point
		elif point.x >= ui_size.x * 0.45 and look_finger == -1:
			look_finger = touch.index
			look_position = touch.position
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == move_finger:
			Controls.touch_move = ((drag.position / ui_scale - move_origin) / 76.0).limit_length()
		elif drag.index == look_finger:
			# Track each finger's position: web multitouch relative deltas can mix pointers.
			var change := drag.position - look_position
			look_position = drag.position
			var screen_delta := get_viewport().get_screen_transform().basis_xform(change)
			Controls.look_delta += screen_delta * Controls.touch_sensitivity
		get_viewport().set_input_as_handled()


func _release_finger(index: int) -> void:
	if index == move_finger:
		move_finger = -1
		Controls.touch_move = Vector2.ZERO
	if index == look_finger:
		look_finger = -1
	if index == jump_finger:
		jump_finger = -1
	if index == use_finger:
		use_finger = -1


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * ui_scale)
	_draw_touch()
	draw_circle(use_center(), 54, Color(0.06, 0.1, 0.14, 0.6))
	draw_arc(use_center(), 54, 0, TAU, 48, ACCENT, 2, true)
	draw_string(
		ThemeDB.fallback_font,
		use_center() + Vector2(-20, 7),
		"USE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		20,
		INK
	)
	_button(pause_button(), "II")


func _draw_touch() -> void:
	var center := (
		Vector2(safe_bounds.position.x + 132, safe_bounds.end.y - 132)
		if move_finger == -1
		else move_origin
	)
	draw_circle(center, 76, Color(0.06, 0.1, 0.14, 0.45))
	draw_arc(center, 76, 0, TAU, 48, Color(0.9, 0.96, 1, 0.55), 2, true)
	draw_circle(center + Controls.touch_move * 56, 28, Color(0.34, 0.94, 0.76, 0.65))
	draw_circle(jump_center(), 62, Color(0.06, 0.1, 0.14, 0.6))
	draw_arc(jump_center(), 62, 0, TAU, 48, ACCENT, 2, true)
	draw_string(
		ThemeDB.fallback_font,
		jump_center() + Vector2(-26, 7),
		"JUMP",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		20,
		INK
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(safe_bounds.get_center().x - 54, safe_bounds.end.y - 230),
		"DRAG TO LOOK",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		INK
	)


func _button(rect: Rect2, label: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.17, 0.21, 0.95)
	style.set_corner_radius_all(12)
	draw_style_box(style, rect)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(
		font,
		rect.get_center() + Vector2(-width * 0.5, 6),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		INK
	)
