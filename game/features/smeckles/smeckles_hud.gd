extends CanvasLayer
## Shows the local player's Smeckle total in the top-right corner.

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.position = Vector2(-220, 12)
	_label.size = Vector2(200, 32)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)


func _process(_delta: float) -> void:
	var smeckles := get_parent() as Smeckles
	if smeckles == null:
		return
	_label.text = "Smeckles: %d" % smeckles.balance_for(multiplayer.get_unique_id())
