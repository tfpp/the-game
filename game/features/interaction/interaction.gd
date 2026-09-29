extends CanvasLayer
## Shared Use action. Features expose can_use(player), interaction_text(), and use().

var _target: Node3D
var _prompt: Label


func _ready() -> void:
	add_to_group(&"interaction")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	# End sits beside the arrow keys, so left-handed players can Use without letting go.
	var end_key := InputEventKey.new()
	end_key.physical_keycode = KEY_END
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_B
	Controls.ensure_action(&"use", [key, end_key, button])
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-250, -165)
	_prompt.size = Vector2(500, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	add_child(_prompt)


func _physics_process(_delta: float) -> void:
	_target = _find_target()
	_prompt.visible = _target != null
	if _target != null:
		var hint := "[E]"
		if Controls.device == Controls.Device.GAMEPAD:
			hint = "[B / Circle]"
		elif Controls.touch_visible():
			hint = "[USE]"
		_prompt.text = "%s %s" % [hint, str(_target.call("interaction_text"))]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"use") and Controls.gameplay_active():
		use()
		get_viewport().set_input_as_handled()


## Also called by the mobile Use button. Re-check instead of using a stale target.
func use() -> void:
	var target := _find_target()
	if target != null:
		target.call("use")


func _find_target() -> Node3D:
	if not Controls.gameplay_active():
		return null
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null:
		return null
	var nearest: Node3D
	var distance := INF
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
		var candidate := node as Node3D
		if candidate == null or not bool(candidate.call("can_use", player)):
			continue
		var next := candidate.global_position.distance_squared_to(player.global_position)
		if next < distance:
			nearest = candidate
			distance = next
	return nearest


## Current eligible interaction, also shown by the immersive VR prompt.
func target_text() -> String:
	var target := _find_target()
	return str(target.call("interaction_text")) if target != null else ""
