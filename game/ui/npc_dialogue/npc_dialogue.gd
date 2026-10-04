class_name NpcDialogue
extends CanvasLayer
## Reusable, client-local NPC conversation panel: a framed portrait, the speaker's name,
## a short line and large action buttons (Buy, Browse, Ask, Leave...). Features add one
## as a child and call `open()` after their own validated Use; the actions only call
## back into the feature, which still sends any request to the server itself.
##
## Wide screens show the portrait beside the text with the actions in a row; narrow or
## portrait screens stack everything vertically, shrink the portrait, drop ornament and
## list one full-width action per line. Buttons stay at least 48 physical pixels tall.
## Esc / controller B / Start closes it, touch taps buttons, and the first action takes
## controller focus. It joins `modal_ui` and pauses gameplay while open.

signal closed

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const MODAL_GROUP := &"modal_ui"
const PANEL_WIDTH := 720.0
const TARGET_PX := 48.0
## Below this physical width the layout stacks vertically.
const NARROW_PX := 600.0

var _ui_scale := 1.0
var _narrow := false
var _theme: Theme
var _panel: PanelContainer
var _body: BoxContainer
var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _monogram: Label
var _speaker: Label
var _line: Label
var _rule: HSeparator
var _actions: GridContainer
var _action_count := 0


func _ready() -> void:
	layer = 9
	_build()
	visible = false
	get_viewport().size_changed.connect(_resize)
	Controls.menu_requested.connect(close.bind(false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: close(false))
	_resize()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Shows the panel. `actions` is a list of {"label": String, "action": Callable}; an
## action that should also end the conversation adds "close": true. A null `portrait`
## shows the speaker's initial in the frame instead.
func open(speaker: String, line: String, actions: Array, portrait: Texture2D = null) -> void:
	_speaker.text = speaker
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_monogram.text = speaker.left(1).to_upper()
	_monogram.visible = portrait == null
	say(line)
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	_action_count = 0
	for entry: Dictionary in actions:
		_add_action(str(entry.get("label", "")), entry.get("action", Callable()), entry)
	visible = true
	if not is_in_group(MODAL_GROUP):
		add_to_group(MODAL_GROUP)
	Controls.pause()
	_resize()
	if _actions.get_child_count() > 0:
		(_actions.get_child(0) as Button).grab_focus()


## Replaces the NPC's line, e.g. in answer to Ask.
func say(line: String) -> void:
	_line.text = line


func is_open() -> bool:
	return visible


## Hides the panel; `resume` restarts gameplay input (false when another menu takes over).
func close(resume: bool = true) -> void:
	if not visible:
		return
	visible = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	if resume:
		Controls.start()
	closed.emit()


## Labels of the current actions, in order (for tests and accessibility checks).
func action_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for child: Node in _actions.get_children():
		labels.append((child as Button).text)
	return labels


## Whether a viewport `physical_width` pixels wide should use the stacked layout.
static func is_narrow(physical_width: float, physical_height: float) -> bool:
	return physical_width < NARROW_PX or physical_height > physical_width


func _add_action(label: String, action: Callable, entry: Dictionary) -> void:
	var button := Button.new()
	button.text = label
	button.name = label.validate_node_name()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = TARGET_PX / _ui_scale
	if _action_count > 0 and bool(entry.get("secondary", label == "Leave")):
		button.theme_type_variation = &"SecondaryButton"
	var ends := bool(entry.get("close", false))
	button.pressed.connect(
		func() -> void:
			if ends:
				close()
			if action.is_valid():
				action.call()
	)
	_actions.add_child(button)
	_action_count += 1


func _build() -> void:
	_theme = UI_THEME.duplicate()
	var root := Control.new()
	root.name = "Root"
	root.theme = _theme
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.04, 0.03, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	root.add_child(_panel)
	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	_panel.add_child(_body)
	_portrait_frame = PanelContainer.new()
	_portrait_frame.name = "Portrait"
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_style())
	_body.add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_frame.add_child(_portrait)
	_monogram = Label.new()
	_monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_monogram.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_monogram.theme_type_variation = &"HeadingLabel"
	_monogram.add_theme_color_override("font_color", Color(0.88, 0.72, 0.4))
	_portrait_frame.add_child(_monogram)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	_body.add_child(column)
	_speaker = Label.new()
	_speaker.name = "Speaker"
	_speaker.theme_type_variation = &"HeadingLabel"
	column.add_child(_speaker)
	_rule = HSeparator.new()
	column.add_child(_rule)
	_line = Label.new()
	_line.name = "Line"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 120
	column.add_child(_line)
	_actions = GridContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override("h_separation", 10)
	_actions.add_theme_constant_override("v_separation", 10)
	column.add_child(_actions)


func _portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.1, 0.07)
	style.border_color = Color(0.74, 0.58, 0.29)
	style.set_border_width_all(3)
	style.set_content_margin_all(4)
	return style


## Re-lays out for the current viewport: compensates the stretched design canvas the way
## ui/login does, then picks the side-by-side or stacked arrangement.
func _resize() -> void:
	if not is_inside_tree() or _panel == null:
		return
	var viewport := get_viewport()
	_ui_scale = clampf(viewport.get_stretch_transform().get_scale().x, 0.1, 1.0)
	_theme.default_font_size = roundi(UI_THEME.default_font_size / _ui_scale)
	for type: StringName in UI_THEME.get_type_list():
		for font_size: StringName in UI_THEME.get_font_size_list(type):
			_theme.set_font_size(
				font_size, type, roundi(UI_THEME.get_font_size(font_size, type) / _ui_scale)
			)
	var canvas := viewport.get_visible_rect().size
	var physical := canvas * _ui_scale
	_narrow = is_narrow(physical.x, physical.y)
	var margin := 16.0 / _ui_scale
	var width := minf(PANEL_WIDTH / _ui_scale, canvas.x - margin * 2.0)
	_body.vertical = _narrow
	_rule.visible = not _narrow
	_actions.columns = 1 if _narrow else maxi(1, mini(_actions.get_child_count(), 4))
	var portrait := (72.0 if _narrow else 120.0) / _ui_scale
	_portrait_frame.custom_minimum_size = Vector2(portrait, portrait)
	_portrait_frame.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER if _narrow else Control.SIZE_SHRINK_BEGIN
	)
	for child: Node in _actions.get_children():
		(child as Button).custom_minimum_size.y = TARGET_PX / _ui_scale
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.size = Vector2(width, 0)
	_panel.reset_size()
	_place_panel.call_deferred()


## Bottom-center, inside safe margins; tall stacked panels shift up to stay on screen.
func _place_panel() -> void:
	if not is_instance_valid(_panel) or not is_inside_tree():
		return
	var canvas := get_viewport().get_visible_rect().size
	var margin := 16.0 / _ui_scale
	var size := _panel.get_combined_minimum_size()
	size.x = maxf(size.x, _panel.custom_minimum_size.x)
	_panel.size = size
	_panel.position = Vector2(
		(canvas.x - size.x) * 0.5, maxf(margin, canvas.y - margin - 120.0 / _ui_scale - size.y)
	)
