extends CanvasLayer
## Local Source-style command UI. Gameplay is paused while typing.

const Commands := preload("res://features/console/commands.gd")
const ACTION := &"toggle_console"
const MAX_LINES := 200
const MAX_HISTORY := 64

var commands: Commands
var panel: PanelContainer
var entry: LineEdit
var output: RichTextLabel
var choices: ItemList
var hint: Label
var history: PackedStringArray = []
var _history_index := 0
var _draft := ""
var _lines: PackedStringArray = []
var _matches: PackedStringArray = []


func _ready() -> void:
	layer = 12
	var key := InputEventKey.new()
	key.physical_keycode = KEY_QUOTELEFT
	Controls.ensure_action(ACTION, [key])
	add_to_group(&"esc_menu_links")
	commands = Commands.new(get_tree())
	_build()
	Controls.menu_requested.connect(_menu_requested)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not panel.visible:
		if event.is_action_pressed(ACTION) and Controls.gameplay_active():
			esc_menu_open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION) or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_pressed():
		var key := event as InputEventKey
		match key.keycode:
			KEY_TAB:
				_complete()
			KEY_UP, KEY_DOWN:
				var direction := -1 if key.keycode == KEY_UP else 1
				if key.ctrl_pressed or entry.text.is_empty() or _history_index < history.size():
					_recall(direction)
				elif not _matches.is_empty():
					var selected := choices.get_selected_items()
					var index := selected[0] if not selected.is_empty() else 0
					choices.select(posmod(index + direction, _matches.size()))
					choices.ensure_current_is_visible()
					_show_hint()
			_:
				return
		get_viewport().set_input_as_handled()


func esc_menu_label() -> String:
	return "Console"


func esc_menu_open() -> void:
	panel.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	entry.grab_focus()
	_suggest(entry.text)


func close(resume: bool = true) -> void:
	panel.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _menu_requested() -> void:
	if panel.visible:
		close(false)


func _submit(raw: String) -> void:
	var text := raw.strip_edges()
	if text.is_empty():
		return
	if history.is_empty() or history[-1] != text:
		history.append(text)
		if history.size() > MAX_HISTORY:
			history.remove_at(0)
	_history_index = history.size()
	if text.to_lower() == "clear":
		_lines.clear()
	else:
		_lines.append("> " + text)
		_lines.append(commands.execute(text))
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	output.text = "\n".join(_lines)
	entry.clear()
	_draft = ""
	_suggest("")
	entry.grab_focus()


func _suggest(text: String) -> void:
	_matches = commands.suggestions(text)
	choices.clear()
	for candidate: String in _matches:
		choices.add_item(candidate)
	if not _matches.is_empty():
		choices.select(0)
	_show_hint()


func _show_hint() -> void:
	var selected := choices.get_selected_items()
	hint.text = (
		commands.describe(_matches[selected[0]])
		if not selected.is_empty()
		else commands.describe(entry.text)
	)


func _complete() -> void:
	var selected := choices.get_selected_items()
	if selected.is_empty():
		return
	entry.text = _matches[selected[0]].rstrip(" ") + " "
	entry.caret_column = entry.text.length()
	_suggest(entry.text)
	entry.grab_focus()


func _recall(direction: int) -> void:
	if _history_index == history.size():
		_draft = entry.text
	_history_index = clampi(_history_index + direction, 0, history.size())
	entry.text = _draft if _history_index == history.size() else history[_history_index]
	entry.caret_column = entry.text.length()
	_suggest(entry.text)


func _build() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_bottom = 0.78
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = 8
	var style := StyleBoxFlat.new()
	style.bg_color = Color("292d26")
	style.border_color = Color("858778")
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_color_override("font_color", Color("e1e5d3"))
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := Label.new()
	title.text = "CONSOLE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var done := Button.new()
	done.text = "Close"
	done.pressed.connect(close)
	heading.add_child(done)
	output = RichTextLabel.new()
	output.bbcode_enabled = false
	output.selection_enabled = true
	output.scroll_following = true
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.text = "Type help for commands. Tab completes; arrows select; Ctrl+arrows recall history."
	box.add_child(output)
	choices = ItemList.new()
	choices.custom_minimum_size.y = 75
	choices.item_selected.connect(func(_index: int) -> void: _show_hint())
	choices.item_activated.connect(func(_index: int) -> void: _complete())
	box.add_child(choices)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var row := HBoxContainer.new()
	box.add_child(row)
	entry = LineEdit.new()
	entry.placeholder_text = "Enter command…"
	entry.max_length = 256
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.text_changed.connect(_suggest)
	entry.text_submitted.connect(_submit)
	row.add_child(entry)
	var complete := Button.new()
	complete.text = "Tab"
	complete.pressed.connect(_complete)
	row.add_child(complete)
	var run := Button.new()
	run.text = "Run"
	run.pressed.connect(func() -> void: _submit(entry.text))
	row.add_child(run)
	panel.hide()
