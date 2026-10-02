extends CanvasLayer
## Compact read-only task HUD; no mouse capture or input bindings.

var _label: Label
var _last := {}


func _ready() -> void:
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 70
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("ead6a4"))
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	visible = false


func _process(_delta: float) -> void:
	var shift := get_parent() as BusboyShift
	var state := shift.snapshot
	_label.offset_top = (
		120 if Controls.touch_visible() or get_viewport().get_visible_rect().size.x < 600 else 70
	)
	visible = (
		int(state.get("worker", 0)) == multiplayer.get_unique_id()
		and str(state.get("phase", "idle")) in ["active", "failed", "prize"]
		and Network.mode != Network.Mode.SERVER
	)
	if state == _last:
		return
	_last = state.duplicate(true)
	var phase := str(state.get("phase", "idle"))
	if phase == "failed":
		_label.text = "Busboy: shift failed — no prize\nUse the bar station to retry"
	elif phase == "prize":
		_label.text = "Busboy: shift complete!\nReturn to the bar and Use for $10"
	else:
		var cargo := int(state.get("cargo", -1))
		var goal := "Pick up EMPTY glasses"
		if cargo == -2:
			goal = "Return glass to bar"
		elif cargo >= 0:
			goal = "Deliver drink to table %d" % (cargo + 1)
		elif not (state.get("orders", {}) as Dictionary).is_empty():
			goal = "Take ordered drink from bar"
		_label.text = (
			"Busboy: %ds • Dirty %d/8\nOrders %d • %s"
			% [
				int(state.get("left", 0)),
				(state.get("dirty", []) as Array).size(),
				(state.get("orders", {}) as Dictionary).size(),
				goal
			]
		)
