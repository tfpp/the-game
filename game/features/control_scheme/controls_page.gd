extends VBoxContainer
## The Controls settings page (see `control_scheme.gd`, which owns the state): layout
## preset, look sensitivity for mouse, controller and touch, the touch layout, and a
## rebindable list of every action with a keyboard & mouse and a controller column.

const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const Glyphs := preload("res://features/control_scheme/input_glyphs.gd")
## Glyph tiles are 16px pixel art, drawn at 2x; taller glyphs (Enter) shrink to fit.
const GLYPH_HEIGHT := 32.0
const SLOT_WIDTH := 180.0
const CONFLICT_COLOR := Color(0.8, 0.2, 0.2)
## Tints a conflicting slot's glyphs red.
const CONFLICT_TINT := Color(1.0, 0.45, 0.45)
const HINT_COLOR := Color(0.22, 0.25, 0.33, 0.75)
## Slider ranges as (min, max, step): Source-style mouse sensitivity, and controller or
## touch look speed as a multiple of its default.
const MOUSE_RANGE := Vector3(0.1, 10.0, 0.05)
const SCALE_RANGE := Vector3(0.25, 3.0, 0.05)

## The control_scheme feature node.
var _feature: Node
var _presets: Dictionary = {}
## "<action>:<pad>" -> Button, for refreshing slot text after a rebind.
var _slots: Dictionary = {}
var _hint: Label


func _init(feature: Node) -> void:
	_feature = feature
	add_theme_constant_override("separation", 10)
	_build()
	refresh()


## Re-reads every binding and highlights the slot being captured, if any.
func refresh() -> void:
	for scheme: int in _presets:
		var preset := _presets[scheme] as Button
		var active := Controls.scheme == scheme
		preset.set_pressed_no_signal(active)
		# The active preset is the blue one; the other is a grey secondary button.
		preset.theme_type_variation = &"" if active else &"SecondaryButton"
	var capture: Dictionary = _feature.capture
	for id: String in _slots:
		var button := _slots[id] as Button
		var action := StringName(id.get_slice(":", 0))
		var pad := id.get_slice(":", 1) == "pad"
		var capturing: bool = (
			capture.get("action", &"") == action and capture.get("pad", false) == pad
		)
		var clashes := Bindings.conflicts(action, pad)
		var text := Bindings.slot_text(action, pad)
		var glyphs: Array[Texture2D] = [] if capturing else Bindings.slot_glyphs(action, pad)
		var box := button.get_node("Glyphs") as HBoxContainer
		_show_glyphs(box, glyphs)
		box.modulate = Color.WHITE if clashes.is_empty() else CONFLICT_TINT
		button.text = "Press…" if capturing else ("" if not glyphs.is_empty() else text)
		# The tooltip names the binding too, since glyphs can be ambiguous.
		button.tooltip_text = text
		if not clashes.is_empty():
			button.tooltip_text += "\n" + _conflict_text(clashes)
		for color: StringName in [&"font_color", &"font_hover_color", &"font_focus_color"]:
			if clashes.is_empty():
				button.remove_theme_color_override(color)
			else:
				button.add_theme_color_override(color, CONFLICT_COLOR)
	_hint.text = _hint_text(capture)


func _hint_text(capture: Dictionary) -> String:
	if capture.is_empty():
		return (
			"Select a binding, then press the new key, mouse button or controller button. "
			+ "Red bindings are shared with another action."
		)
	var device := "controller button" if capture.get("pad", false) else "key or mouse button"
	return (
		"Press a %s for “%s”. Esc cancels."
		% [device, Bindings.label_for(capture.get("action", &""))]
	)


static func _conflict_text(clashes: Array[StringName]) -> String:
	if clashes.is_empty():
		return ""
	var names: Array[String] = []
	for action: StringName in clashes:
		names.append(Bindings.label_for(action))
	return "Also bound to: " + ", ".join(names)


func _build() -> void:
	_section("Layout")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	add_child(presets)
	var group := ButtonGroup.new()
	for preset: Array in [
		[Controls.Scheme.RIGHT_HANDED, "Right-handed", "WASD to move, Space to jump"],
		[Controls.Scheme.LEFT_HANDED, "Left-handed", "Arrow keys to move, Shift to jump"],
	]:
		var button := Button.new()
		button.text = preset[1]
		button.tooltip_text = preset[2]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_feature.set_scheme.bind(preset[0]))
		presets.add_child(button)
		_presets[preset[0]] = button
	_note("Presets reset movement and jump keys. Everything else is kept.")

	_section("Look sensitivity")
	var sliders := GridContainer.new()
	sliders.columns = 3
	sliders.add_theme_constant_override("h_separation", 12)
	add_child(sliders)
	_slider(sliders, "Mouse", Controls.sensitivity, MOUSE_RANGE, _feature.set_mouse_sensitivity)
	_slider(
		sliders,
		"Controller",
		Controls.stick_sensitivity / Controls.STICK_SENSITIVITY,
		SCALE_RANGE,
		_feature.set_stick_scale
	)
	if Controls.touch_available:
		_slider(
			sliders,
			"Touch",
			Controls.touch_sensitivity / Controls.TOUCH_SENSITIVITY,
			SCALE_RANGE,
			_feature.set_touch_scale
		)

	if Controls.touch_available:
		_section("Touch screen")
		_note(
			(
				"Drag on the left side of the screen to move and on the right side to look. "
				+ "Tap JUMP to jump, USE to interact, and II for the menu."
			)
		)

	_section("Bindings")
	_hint = _note("")
	var header := _row("", "Keyboard & mouse", "Controller")
	add_child(header)
	for section: Dictionary in Bindings.sections():
		var heading := _section(str(section["title"]))
		heading.add_theme_font_size_override("font_size", 16)
		for entry: Array in section["actions"]:
			add_child(_binding_row(entry[0], str(entry[1])))
	var fixed := _section("Fixed")
	fixed.add_theme_font_size_override("font_size", 16)
	for row: Array in Bindings.FIXED_ROWS:
		add_child(_row(row[0], row[1], row[2]))
	var reset := Button.new()
	reset.text = "Reset all bindings"
	reset.theme_type_variation = &"SecondaryButton"
	reset.custom_minimum_size.y = 40
	reset.pressed.connect(_feature.reset_bindings)
	add_child(reset)


func _binding_row(action: StringName, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	for pad: bool in [false, true]:
		var button := Button.new()
		button.theme_type_variation = &"SecondaryButton"
		button.custom_minimum_size = Vector2(SLOT_WIDTH, 36)
		button.clip_text = true
		# Key names in the body font: Kenney Future draws Z like "2" and X like "H".
		button.add_theme_font_override("font", ThemeDB.fallback_font)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_feature.begin_capture.bind(action, pad))
		var glyphs := _glyph_box()
		glyphs.name = "Glyphs"
		glyphs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(glyphs)
		row.add_child(button)
		_slots["%s:%s" % [action, "pad" if pad else "kbm"]] = button
	return row


## A read-only row: label plus two fixed columns.
func _row(label: String, keyboard: String, pad: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var texts: Array[String] = [label, keyboard, pad]
	for index: int in texts.size():
		var glyph := Glyphs.named(texts[index]) if index > 0 else null
		if glyph:
			var box := _glyph_box()
			box.custom_minimum_size.x = SLOT_WIDTH
			box.tooltip_text = texts[index]
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			_show_glyphs(box, [glyph])
			row.add_child(box)
			continue
		var cell := Label.new()
		cell.text = texts[index]
		if index == 0:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			cell.custom_minimum_size.x = SLOT_WIDTH
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(cell)
	return row


## A centered row of input glyphs that lets clicks through to its button.
static func _glyph_box() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	return box


static func _show_glyphs(box: HBoxContainer, glyphs: Array[Texture2D]) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for glyph: Texture2D in glyphs:
		var rect := TextureRect.new()
		rect.texture = glyph
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.custom_minimum_size = glyph.get_size() * (GLYPH_HEIGHT / glyph.get_height())
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rect)


func _slider(
	grid: GridContainer, label: String, value: float, bounds: Vector3, apply: Callable
) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 100
	grid.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = bounds.z
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 28
	grid.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 56
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = "%.2f" % value
	grid.add_child(readout)
	slider.value_changed.connect(
		func(next: float) -> void:
			readout.text = "%.2f" % next
			apply.call(next)
	)


func _section(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"HeadingLabel"
	label.add_theme_font_size_override("font_size", 20)
	add_child(label)
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", HINT_COLOR)
	add_child(label)
	return label
