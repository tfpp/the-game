extends Control
## Floating move stick, optional first-person aim stick, look swipes and action targets.

const AttackInput := preload("res://features/touch_controls/attack_input.gd")

const INK := Color(0.9, 0.96, 1.0)
const ACCENT := Color(0.34, 0.94, 0.76)
const STICK_RADIUS := 76.0
const ACTION_RADIUS := 34.0
const STORE_NAME := "touch_controls"
var first_person_aim_enabled := false
var ui_scale := 1.0
var ui_size := Vector2.ZERO
var safe_bounds := Rect2()
var move_finger := -1
var look_finger := -1
var aim_finger := -1
var aim_value := Vector2.ZERO
var jump_finger := -1
var use_finger := -1
var fire_finger := -1
var move_origin := Vector2.ZERO
var look_position := Vector2.ZERO
var _browser: JavaScriptObject
var _safe_area_refresh := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(&"settings_pages")
	first_person_aim_enabled = (
		SettingsStore.load_data(STORE_NAME).get("first_person_aim_enabled", false) == true
	)
	if OS.has_feature("web"):
		_browser = JavaScriptBridge.get_interface("window")
	Controls.input_reset.connect(_clear_fingers)
	resized.connect(_resize_layout)
	_resize_layout()


func _process(delta: float) -> void:
	visible = Controls.touch_visible() and Controls.gameplay_active()
	_sync_aim()
	if visible:
		Controls.look_delta += Controls.deadzone(aim_value) * Controls.stick_sensitivity * delta
	elif [move_finger, look_finger, aim_finger, jump_finger, use_finger, fire_finger].any(
		func(finger: int) -> bool: return finger != -1
	):
		_clear_fingers()
	_safe_area_refresh -= delta
	if _safe_area_refresh <= 0.0:
		_update_safe_area()
		_safe_area_refresh = 0.5
	queue_redraw()


func settings_page_label() -> String:
	return "Touch controls"


func settings_page_build() -> Control:
	var box := VBoxContainer.new()
	var toggle := CheckButton.new()
	toggle.text = "First-person aim joystick"
	toggle.custom_minimum_size.y = 48
	toggle.button_pressed = first_person_aim_enabled
	toggle.toggled.connect(set_first_person_aim_enabled)
	box.add_child(toggle)
	var hint := Label.new()
	hint.text = "Off by default. Swipe to aim in first person with or without the joystick."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return box


func set_first_person_aim_enabled(value: bool) -> void:
	first_person_aim_enabled = value
	SettingsStore.save_data(STORE_NAME, {"first_person_aim_enabled": value})
	_sync_aim()
	queue_redraw()


func aim_stick_active() -> bool:
	var camera := get_tree().get_first_node_in_group(&"third_person_camera")
	var third_person: bool = camera != null and camera.enabled and not get_viewport().use_xr
	return first_person_aim_enabled or third_person


func _sync_aim() -> void:
	if not aim_stick_active():
		aim_finger = -1
		aim_value = Vector2.ZERO


func _resize_layout() -> void:
	# Reserve separate thumb zones even with the mobile portrait UI layout.
	ui_scale = minf(1.0, minf(maxf(size.x, 1.0) / 600.0, maxf(size.y, 1.0) / 540.0))
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
	aim_finger = -1
	aim_value = Vector2.ZERO
	jump_finger = -1
	use_finger = -1
	if fire_finger != -1:
		fire_finger = -1
		AttackInput.send_attack(false)
	Controls.touch_move = Vector2.ZERO
	Controls.look_delta = Vector2.ZERO
	Controls.jump_queued = false


func pause_button() -> Rect2:
	return Rect2(safe_bounds.end.x - 100, safe_bounds.position.y + 72 / ui_scale, 76, 48)


## Beside the menu, outside the movement and action targets.
func camera_button() -> Rect2:
	return Rect2(safe_bounds.end.x - 176, safe_bounds.position.y + 72 / ui_scale, 64, 48)


func move_center() -> Vector2:
	return Vector2(safe_bounds.position.x + 132, safe_bounds.end.y - 132)


func aim_center() -> Vector2:
	return safe_bounds.end - Vector2(132, 132)


func jump_center() -> Vector2:
	return use_center() + Vector2(82, 0)


func use_center() -> Vector2:
	return aim_center() - Vector2(0, 168)


## Compact action row above the aim stick, clear of CAM and the menu.
func fire_center() -> Vector2:
	return use_center() - Vector2(82, 0)


func _input(event: InputEvent) -> void:
	if not Controls.touch_visible() or not Controls.gameplay_active():
		return
	_sync_aim()
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var point := touch.position / ui_scale
		if not touch.pressed or touch.canceled:
			_release_finger(touch.index)
		elif camera_button().has_point(point):
			get_tree().call_group(&"third_person_camera", "toggle_camera")
		elif pause_button().has_point(point):
			Controls.menu_requested.emit()
		elif point.distance_to(use_center()) <= ACTION_RADIUS and use_finger == -1:
			use_finger = touch.index
			get_tree().call_group(&"interaction", "use")
		elif point.distance_to(fire_center()) <= ACTION_RADIUS and fire_finger == -1:
			fire_finger = touch.index
			AttackInput.send_attack(true)
		elif point.distance_to(jump_center()) <= ACTION_RADIUS and jump_finger == -1:
			jump_finger = touch.index
			Controls.jump_queued = true
		elif aim_stick_active() and point.distance_to(aim_center()) <= STICK_RADIUS:
			if aim_finger == -1:
				aim_finger = touch.index
				aim_value = ((point - aim_center()) / STICK_RADIUS).limit_length()
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
		elif drag.index == aim_finger:
			aim_value = ((drag.position / ui_scale - aim_center()) / STICK_RADIUS).limit_length()
		elif drag.index == look_finger:
			# Track each finger's position: web multitouch relative deltas can mix pointers.
			var change := drag.position - look_position
			look_position = drag.position
			var screen_delta := get_viewport().get_screen_transform().basis_xform(change)
			var look := screen_delta * Controls.touch_sensitivity
			var camera := get_tree().get_first_node_in_group(&"third_person_camera")
			if camera == null or not camera.orbit_look(look):
				Controls.look_delta += look
		get_viewport().set_input_as_handled()


func _release_finger(index: int) -> void:
	if index == move_finger:
		move_finger = -1
		Controls.touch_move = Vector2.ZERO
	if index == look_finger:
		look_finger = -1
	if index == aim_finger:
		aim_finger = -1
		aim_value = Vector2.ZERO
	if index == jump_finger:
		jump_finger = -1
	if index == use_finger:
		use_finger = -1
	if index == fire_finger:
		fire_finger = -1
		AttackInput.send_attack(false)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * ui_scale)
	_draw_touch()
	draw_circle(use_center(), ACTION_RADIUS, Color(0.06, 0.1, 0.14, 0.6))
	draw_arc(use_center(), ACTION_RADIUS, 0, TAU, 48, ACCENT, 2, true)
	draw_string(
		ThemeDB.fallback_font,
		use_center() + Vector2(-20, 7),
		"USE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		20,
		INK
	)
	draw_circle(fire_center(), ACTION_RADIUS, Color(0.2, 0.06, 0.06, 0.6))
	draw_arc(fire_center(), ACTION_RADIUS, 0, TAU, 48, Color(1.0, 0.45, 0.4), 2, true)
	draw_string(
		ThemeDB.fallback_font,
		fire_center() + Vector2(-22, 7),
		"FIRE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		20,
		INK
	)
	_button(pause_button(), "II")
	_button(camera_button(), "CAM")


func _draw_touch() -> void:
	var center := move_center() if move_finger == -1 else move_origin
	draw_circle(center, 76, Color(0.06, 0.1, 0.14, 0.45))
	draw_arc(center, 76, 0, TAU, 48, Color(0.9, 0.96, 1, 0.55), 2, true)
	draw_circle(center + Controls.touch_move * 56, 28, Color(0.34, 0.94, 0.76, 0.65))
	if aim_stick_active():
		draw_circle(aim_center(), STICK_RADIUS, Color(0.06, 0.1, 0.14, 0.45))
		draw_arc(aim_center(), STICK_RADIUS, 0, TAU, 48, Color(0.9, 0.96, 1, 0.55), 2, true)
		draw_circle(aim_center() + aim_value * 56, 28, Color(0.34, 0.94, 0.76, 0.65))
	draw_circle(jump_center(), ACTION_RADIUS, Color(0.06, 0.1, 0.14, 0.6))
	draw_arc(jump_center(), ACTION_RADIUS, 0, TAU, 48, ACCENT, 2, true)
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
		aim_center() + Vector2(-16 if aim_stick_active() else -65, 110),
		"AIM" if aim_stick_active() else "SWIPE TO AIM",
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
