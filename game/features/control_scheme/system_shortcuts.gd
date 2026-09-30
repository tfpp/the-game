extends Node
## Yield the pointer before macOS consumes a screenshot shortcut's final key.
## The OS owns the screenshot; this invisible modal only suspends local game input.

var macos := false


func _ready() -> void:
	macos = OS.has_feature("macos")
	if OS.has_feature("web"):
		macos = bool(JavaScriptBridge.eval("/^Mac/.test(navigator.platform)"))


func _input(event: InputEvent) -> void:
	if not macos:
		return
	if is_in_group(&"modal_ui"):
		if event.is_action_pressed("release_mouse"):
			remove_from_group(&"modal_ui")
			Controls.menu_requested.emit()
		elif (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
			and not event.meta_pressed
		):
			remove_from_group(&"modal_ui")
			if not get_tree().get_first_node_in_group(&"modal_ui"):
				Controls.select_device(Controls.Device.KEYBOARD)
				Controls.start()
		else:
			return
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventKey
		and event.pressed
		and (event.keycode == KEY_META or event.physical_keycode == KEY_META or event.meta_pressed)
		and Controls.gameplay_active()
	):
		# Waiting for 4 is too late: macOS may never deliver it to the game.
		add_to_group(&"modal_ui")
		Controls.pause()
		get_viewport().set_input_as_handled()
