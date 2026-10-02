extends Control
## Local radial picker. Only the selected name goes to the existing server endpoint.

var selected := -1
var held := false
var _player: Player

@onready var models: PlayerModels = get_parent().get_parent() as PlayerModels


func _ready() -> void:
	hide()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_resize)
	_resize()
	add_to_group(&"esc_menu_links")
	get_window().focus_exited.connect(func() -> void: close(false, false))
	Controls.menu_requested.connect(func() -> void: close(false, false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: close(false, false))


func esc_menu_label() -> String:
	return "Emotes"


func esc_menu_open() -> void:
	open(false)


func open(from_hold: bool) -> void:
	if visible or get_tree().get_first_node_in_group(&"modal_ui") != null:
		return
	_player = null
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is Player and node.is_local() and not node.is_queued_for_deletion():
			_player = node as Player
	if _player == null:
		return
	held = from_hold
	selected = -1
	add_to_group(&"modal_ui")
	Controls.pause()
	show()
	queue_redraw()


func close(confirm: bool, resume: bool = true) -> void:
	if not visible:
		return
	var choice := selected
	hide()
	remove_from_group(&"modal_ui")
	selected = -1
	if resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()
	if confirm and choice >= 0 and is_instance_valid(_player):
		models.entity.request_action(&"emote", {"name": PlayerModels.SELECTABLE_EMOTES[choice]})
	_player = null


func _unhandled_input(event: InputEvent) -> void:
	if (
		not visible
		and Controls.gameplay_active()
		and event.is_action_pressed(PlayerModels.EMOTE_ACTION)
		and not event.is_echo()
	):
		open(true)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		close(false)
	elif held and event.is_action_released(PlayerModels.EMOTE_ACTION):
		close(true)
	elif event is InputEventMouseMotion:
		_select_pointer((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch and event.is_pressed():
		_select_pointer((event as InputEventScreenTouch).position)
		close(true)
	elif event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not held:
			_select_pointer(button.position)
			close(true)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			close(false)
	elif not held and event.is_action_pressed(&"ui_accept"):
		close(true)
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_player) or _player.is_queued_for_deletion():
		close(false)
		return
	if Controls.device == Controls.Device.GAMEPAD and Controls.joypad >= 0:
		select_direction(Controls.stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y) * radius())
	queue_redraw()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	size = logical / ui_scale
	queue_redraw()


func _select_pointer(screen_position: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_position
	select_direction(local - size * 0.5)


func radius() -> float:
	return minf(size.x, size.y) * 0.38


static func sector(direction: Vector2, deadzone: float) -> int:
	if direction.length() <= deadzone:
		return -1
	return posmod(int(floor((direction.angle() + PI / 2.0 + PI / 4.0) / (PI / 2.0))), 4)


func select_direction(direction: Vector2) -> void:
	selected = sector(direction, radius() * 0.28)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.04, 0.72))
	var center := size * 0.5
	var outer := radius()
	var inner := outer * 0.28
	var font := ThemeDB.fallback_font
	var font_size := maxi(14, int(outer * 0.12))
	for index: int in 4:
		var angle := -PI / 2.0 + index * PI / 2.0
		var points := PackedVector2Array()
		for step: int in 17:
			points.append(center + Vector2.from_angle(angle - PI / 4.0 + step * PI / 32.0) * outer)
		for step: int in 17:
			points.append(center + Vector2.from_angle(angle + PI / 4.0 - step * PI / 32.0) * inner)
		var color := Color(0.55, 0.39, 0.14, 0.95) if selected == index else Color(0.12, 0.15, 0.19)
		draw_colored_polygon(points, color)
		var text := PlayerModels.EMOTE_LABELS[index]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := center + Vector2.from_angle(angle) * outer * 0.65
		draw_string(
			font,
			at + Vector2(-width / 2.0, font_size * 0.35),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		)
	var hint := (
		"Release to emote • Center / Esc cancels" if held else "Pick an emote • Center cancels"
	)
	var hint_size := maxi(12, int(outer * 0.09))
	var hint_width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size).x
	draw_string(
		font,
		center + Vector2(-hint_width / 2.0, outer + hint_size * 1.8),
		hint,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		hint_size
	)
