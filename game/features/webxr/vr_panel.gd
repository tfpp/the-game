extends CanvasLayer
## Browser-space setup; native HUD panels remain in the browser, outside immersion.

signal enter_requested

var status: Label
var enter: Button
var panel: PanelContainer


func _ready() -> void:
	layer = 30
	panel = PanelContainer.new()
	panel.theme = preload("res://ui/theme/ui_theme.tres")

	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status = Label.new()
	status.custom_minimum_size.x = 300
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var instructions := Label.new()
	instructions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instructions.text = (
		"Quest 3 VR\n\nOpen this HTTPS page in Quest Browser.\n"
		+ "Play seated or standing in place with Touch controllers.\n\n"
		+ "Left stick: walk toward your gaze\nRight stick: snap turn 30 degrees\n"
		+ "A: jump   Trigger: Use nearby object\n"
		+ "Right grip: fire / use held item / punch\nLeft grip: reload   X: inventory\n"
		+ "B or Y: leave VR\n\n"
		+ "Menus leave VR; use them in the browser, then enter VR again."
	)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(instructions)
	enter = Button.new()
	enter.text = "Enter VR"
	enter.custom_minimum_size.y = 48
	enter.button_down.connect(func() -> void: enter_requested.emit())
	box.add_child(enter)
	var close := Button.new()
	close.text = "Back to game"
	close.custom_minimum_size.y = 48
	close.button_down.connect(hide_panel)
	box.add_child(close)
	visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var bounds := get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(520, bounds.x - 32), bounds.y - 32)
	panel.position = (bounds - panel.size) * 0.5


func show_panel(message: String, supported: bool) -> void:
	status.text = message
	enter.disabled = not supported
	visible = true
	add_to_group(&"modal_ui")
	Controls.pause()


func hide_panel() -> void:
	visible = false
	remove_from_group(&"modal_ui")
	Controls.start()
