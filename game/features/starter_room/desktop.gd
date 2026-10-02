class_name GarageDesktop
extends VBoxContainer
## Private simulated desktop. No host files, executable code or network access.

signal exit_requested

const APP_NAMES := ["Jobs", "Notes", "Files", "Calculator", "Help"]
const MAX_FILES := 12
const MAX_TEXT := 4096

var body_font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var files: Dictionary[String, String] = {}
var active_app := ""
var running: Array[String] = []
var _windows: Dictionary[String, Control] = {}
var _launchers: Dictionary[String, Button] = {}
var _tasks: Dictionary[String, Button] = {}
var _workspace: VBoxContainer
var _taskbar: HFlowContainer
var _home: Label
var _editor: TextEdit
var _filename: LineEdit
var _status: Label
var _file_list: VBoxContainer
var _display: Label
var _entry := "0"
var _left := 0.0
var _operator := ""
var _fresh := true


func _ready() -> void:
	theme = Theme.new()
	for type: String in ["Label", "Button", "LineEdit", "TextEdit"]:
		theme.set_font("font", type, body_font)
		theme.set_font_size("font_size", type, 16)
		theme.set_color("font_color", type, Color("b4f5c7"))
	for type: String in ["LineEdit", "TextEdit"]:
		for state: String in ["normal", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("102018")
			style.border_color = Color("90d6a6")
			style.set_border_width_all(1)
			style.set_content_margin_all(8)
			theme.set_stylebox(state, type, style)
	add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = "CROWN OS / PERSONAL DESKTOP"
	add_child(heading)
	var launch := HFlowContainer.new()
	add_child(launch)
	for app: String in APP_NAMES:
		var button := _button(launch, app, launch_app.bind(app))
		_launchers[app] = button
	_button(launch, "Log off", func() -> void: exit_requested.emit())
	_taskbar = HFlowContainer.new()
	add_child(_taskbar)
	for app: String in APP_NAMES:
		_tasks[app] = _button(_taskbar, app, launch_app.bind(app))
		_tasks[app].hide()
	_workspace = VBoxContainer.new()
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.custom_minimum_size.y = 300
	add_child(_workspace)
	_home = Label.new()
	_home.text = (
		"Welcome to Crown OS. Launch an application above.\n"
		+ "Running apps stay in the taskbar when minimized.\n"
		+ "Personal files are private and reset on disconnect.\n"
		+ "Log off or Esc returns to the garage."
	)
	_home.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace.add_child(_home)
	_build_notes()
	_file_list = app_body("Files")
	_build_calculator()
	var help := Label.new()
	help.text = (
		"CROWN OS / USER GUIDE\n\n"
		+ "Jobs: accept surveys and submit reports through the existing garage terminal.\n\n"
		+ "Notes: name a document and Save. Open or delete it in Files. "
		+ "Up to 12 documents, 4096 characters each. Save before closing Notes.\n\n"
		+ "Calculator: use the keypad for basic arithmetic. C clears it.\n\n"
		+ "Windows are maximized to work on phones. Minimize keeps an app running; "
		+ "Close removes it from the taskbar. Jobs keep progressing while closed.\n\n"
		+ "This is a simulation: no real files, shell commands or internet. "
		+ "Documents survive log off, but not a connection change or game restart."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app_body("Help").add_child(help)


func app_body(app: String) -> VBoxContainer:
	var window := VBoxContainer.new()
	window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.add_child(window)
	_windows[app] = window
	var title := HFlowContainer.new()
	window.add_child(title)
	var label := Label.new()
	label.text = app.to_upper() + ".EXE"
	title.add_child(label)
	_button(title, "Minimize", minimize)
	_button(title, "Close", close_app.bind(app))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	window.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	window.hide()
	return body


func launch_app(app: String) -> void:
	if not _windows.has(app):
		return
	if app not in running:
		running.append(app)
	active_app = app
	_home.hide()
	for name: String in _windows:
		_windows[name].visible = name == app
		_tasks[name].visible = name in running
	if app == "Files":
		_refresh_files()
	_tasks[app].grab_focus()


func minimize() -> void:
	for window: Control in _windows.values():
		window.hide()
	active_app = ""
	_home.show()
	_launchers["Jobs"].grab_focus()


func close_app(app: String) -> void:
	running.erase(app)
	_tasks[app].hide()
	if active_app == app:
		minimize()


func reset_session() -> void:
	files.clear()
	running.clear()
	_filename.text = ""
	_editor.text = ""
	_status.text = ""
	for task: Button in _tasks.values():
		task.hide()
	calculator_key("C")
	minimize()


func save_file(title: String, contents: String) -> bool:
	var key := title.strip_edges()
	if key.is_empty() or key.length() > 32 or contents.length() > MAX_TEXT:
		return false
	if not files.has(key) and files.size() >= MAX_FILES:
		return false
	files[key] = contents
	return true


func open_file(title: String) -> void:
	if not files.has(title):
		return
	_filename.text = title
	_editor.text = files[title]
	_status.text = "Opened " + title
	launch_app("Notes")


func delete_file(title: String) -> void:
	files.erase(title)
	_refresh_files()
	_tasks["Files"].grab_focus()


func _build_notes() -> void:
	var body := app_body("Notes")
	_filename = LineEdit.new()
	_filename.placeholder_text = "Document name (32 characters)"
	_filename.max_length = 32
	body.add_child(_filename)
	_editor = TextEdit.new()
	_editor.custom_minimum_size.y = 180
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(_editor)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_button(body, "Save document", _save_note)
	_button(body, "New document", _new_note)


func _save_note() -> void:
	_status.text = (
		"Saved locally for this session."
		if save_file(_filename.text, _editor.text)
		else "Not saved: name required, max 12 files / 4096 characters."
	)


func _new_note() -> void:
	_filename.text = ""
	_editor.text = ""
	_status.text = "New unsaved document"
	_filename.grab_focus()


func _refresh_files() -> void:
	for child: Node in _file_list.get_children():
		_file_list.remove_child(child)
		child.queue_free()
	var label := Label.new()
	label.text = "PERSONAL / %d of %d documents" % [files.size(), MAX_FILES]
	_file_list.add_child(label)
	var names := files.keys()
	names.sort()
	for title: String in names:
		var row := HFlowContainer.new()
		_file_list.add_child(row)
		_button(row, "Open " + title, open_file.bind(title))
		_button(row, "Delete " + title, delete_file.bind(title))


func _build_calculator() -> void:
	var body := app_body("Calculator")
	_display = Label.new()
	_display.text = "0"
	body.add_child(_display)
	var grid := GridContainer.new()
	grid.columns = 4
	body.add_child(grid)
	for key: String in [
		"7", "8", "9", "/", "4", "5", "6", "*", "1", "2", "3", "-", "C", "0", "=", "+", "."
	]:
		var button := _button(grid, key, calculator_key.bind(key))
		button.custom_minimum_size.x = 64
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func calculator_key(key: String) -> void:
	if key == "C":
		_entry = "0"
		_left = 0
		_operator = ""
		_fresh = true
	elif key in ["+", "-", "*", "/", "="]:
		if not _operator.is_empty() and not _fresh:
			var right := _entry.to_float()
			if _operator == "/" and right == 0:
				calculator_key("C")
				_display.text = "Cannot divide by zero"
				return
			match _operator:
				"+":
					_left += right
				"-":
					_left -= right
				"*":
					_left *= right
				"/":
					_left /= right
			_entry = str(_left) if is_finite(_left) else "0"
		_left = _entry.to_float()
		_operator = "" if key == "=" else key
		_fresh = true
	elif key in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "."]:
		if _fresh:
			_entry = "0"
			_fresh = false
		if key == "." and "." in _entry:
			return
		if _entry.length() < 16:
			_entry = key if _entry == "0" and key != "." else _entry + key
	_display.text = _entry


func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(100, 44)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("102f20")
		style.border_color = Color("90d6a6") if state == "focus" else Color("386c4a")
		style.set_border_width_all(2)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_hover_color", Color("e0ffe9"))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
